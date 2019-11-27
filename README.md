# NotePlan Cleaner
Ruby script to clean up recently-changed NotePlan app files.
Runs with both iCloud or Dropbox storage.

## Running the Cleaner
There are 2 ways of running this:
1. with passed filename pattern, when it does this just for that file (if it exists). NB: it's a pattern so can pass 'a*.txt' for example
2. with no arguments, it checks all files updated in the last 24 hours. 

When cleaning, it
- removes the time component of any @done() mentions that NotePlan automatically adds
- removes #waiting or #high tags from @done tasks (configurable)
- remove any lines with just * or -
- moves any calendar entries with [[Note link]] in it to that note, after the header section

## Configuration
Set the following Constants at the top of the file:
- StorageType: select whether you're using iCloud for storage (the default) or Drobpox
- NumHeaderLines: number of lines at the start of a note file to regard as the header. The default is 1. Relevant when moving lines around.
- Username: your username
- TagsToRemove: list of tags to remove. Default '#waiting,#high'

## Automatic running
This can be configured to run automatically using macOS launchctl.

## TODO
[ ] Extend the built-in archive capability with a more powerful version that understands sub-heads with a file, and information-only lines.
