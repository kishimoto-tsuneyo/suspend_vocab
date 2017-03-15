# suspend_vocab
Edit Anki collection to suspend/resume vocab based on mature kanji

**Before using this script, review the disclaimers in the `LICENSE` file.** Modifing the Anki SQLite database directly is probably **not supported by anyone**, so you may not find help if something goes wrong. **Make sure to back up your data frequently.**

This script opens your Anki database and finds your mature kanji by looking at the `Kanji` field in `Kanji` notes. Then, it compares that with a list of the canonical Unicode code points for all 漢検 kanji (plus two name list kanji not in the 漢検 set). Finally, it changes cards as follows:

* for notes (any type) with an `Expression` field containing unknown kanji, suspend all cards
* for notes (any type) with an `Expression` field containing no unknown kanji, unsuspend any suspended cards

When determining if a kanji is known, this script checks if number of days until the next review is greater than 21.

`suspend_vocab` depends on `ruby` (version 2.0 or later). If you have Ruby, run `gem install active_record sqlite3 json --no-document` to install the dependencies.

You will also need to update the script with the username of the Anki profile that you want to modify. If you are not running Anki on macOS, you will also need to edit the script to specify the path to your `Anki2` folder.