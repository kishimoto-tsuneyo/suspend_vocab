#!/usr/bin/env ruby

require 'active_record'
require 'sqlite3'
require 'json'
require 'pp'

MATURE_DAYS = 21
KANJI_MODEL_NAME = 'Kanji' # note type
KANJI_FIELD_NAME = 'Kanji'
EXPR_FIELD_NAME = 'Expression'
ANKI_USER = 'example'
KANJI_NORM_MAP = {?填 => ?塡, ?剥 => ?剝, ?頬 => ?頰, ?叱 => ?𠮟, ?喻 => ?喩, ?䇳 => ?箋, ?篭 => ?籠}
KANJI_NORM_REGEXP = /(填|剥|頬|叱|喻|䇳|篭)/
EMPTY_STR = %q{}
DB_PATH = case RUBY_PLATFORM
when /darwin/ # macOS 10
  File.join Dir.home, 'Library/Application Support/Anki2', ANKI_USER, 'collection.anki2'
else # customize as needed 
  File.join Dir.home, 'example_path_to_anki2_dir', ANKI_USER, 'collection.anki2'
end

File.exist?(DB_PATH) \
  or abort 'Anki database not found. Please exit script constants so we know where to look.'
ActiveRecord::Base.establish_connection adapter: 'sqlite3', database: DB_PATH

module PrimaryKeyFix
  def initialize(options={})
    super(options.merge! limit: 8)
  end
end

class ActiveRecord::Type::Integer
  prepend PrimaryKeyFix
end

class Card < ActiveRecord::Base
  self.inheritance_column = 'nonexistant_col'
  belongs_to :note, foreign_key: :nid

  def suspended?
    queue == -1
  end

  def mature?
    ivl.to_i >= 21
  end
end

class Collection < ActiveRecord::Base
  self.table_name = 'col'

  def self.models
    JSON.parse first.models
  end

  def self.find_model_by_name(name)
    models.detect do |(model_id, model_configuration)|
      model_configuration['name'] == name
    end or fail ArgumentError, "#{name} not found"
  end

  def self.model_field_index_for(model, field_name)
    field = model.last['flds'].find do |field|
      field['name'] == field_name
    end or fail ArgumentError, "could not find #{field_name} on #{model}"
    field['ord'].to_i
  end
end

class Note < ActiveRecord::Base
  FLD_SENTINEL = ?\u001F
  has_many :cards, foreign_key: :nid

  def mature?
    cards.count == cards.where('ivl >= ?', MATURE_DAYS).count
  end

  def split_by_fields
    flds.split FLD_SENTINEL
  end

  def self.not_kanji
    where.not mid: Collection.find_model_by_name(KANJI_MODEL_NAME)[0]
  end
end

class Review < ActiveRecord::Base
  self.table_name = 'revlog'
end

def self.mature_kanji
  kanji_model = Collection.find_model_by_name KANJI_MODEL_NAME
  kanji_model_id = kanji_model[0].to_i
  kanji_model_kanji_field_index = Collection.model_field_index_for kanji_model, KANJI_FIELD_NAME
  kanji_notes = Note.joins(:cards).where(mid: kanji_model_id.to_s)
  kanji_notes_mature = kanji_notes.select &:mature?
  # take first char of kanji field and normalize
  kanji_notes_mature \
    .map {|note| note.split_by_fields[kanji_model_kanji_field_index][0] } \
    .join \
    .unicode_normalize \
    .gsub(KANJI_NORM_REGEXP) {|match_char| KANJI_NORM_MAP[match_char] } \
    .split(EMPTY_STR) \
    .uniq
end

def kk_chars
  File.read(File.join File.dirname(__FILE__), 'kanji_list.txt').strip.split EMPTY_STR
end

IMMATURE_KANJI = kk_chars - mature_kanji
puts "mature kanji count: #{kk_chars.size - IMMATURE_KANJI.size}"

def self.suspend_and_unsuspend_expr_cards
  mod_time_sec = Time.now.to_i
  cards_changed = 0
  Collection.models.each do |(model_id, model_configuration)|
    next if model_configuration['name'] == KANJI_MODEL_NAME # skip kanji notes
    model_expr_field = model_configuration['flds'].find {|field| field['name'] == EXPR_FIELD_NAME } \
      or next
    model_expr_field_index = model_expr_field['ord'].to_i
    Note.where(mid: model_id.to_s).find_each do |note|
      expression = note.split_by_fields[model_expr_field_index].unicode_normalize
      expression.gsub!(KANJI_NORM_REGEXP) {|match_char| KANJI_NORM_MAP[match_char] }
      if expression.split(EMPTY_STR).any? {|char| IMMATURE_KANJI.include? char }
        cards_changed += note.cards.where.not(queue: -1).update_all queue: -1, mod: mod_time_sec, usn: -1 # set non-suspended cards to suspended
      elsif expression.split(EMPTY_STR).none? {|char| IMMATURE_KANJI.include? char }
        cards_changed += note.cards.where(queue: -1).update_all queue: 0, mod: mod_time_sec, usn: -1 # set suspended cards to new
      end
    end
  end
  cards_changed
end

puts 'checking database (this could take a few minutes)'
Collection.transaction do
  begin
    puts "updated card count: #{suspend_and_unsuspend_expr_cards}"
  rescue ActiveRecord::StatementInvalid => e
    e.message.include?(SQLite3::BusyException.name) and abort 'Anki database is locked'
  end
end
