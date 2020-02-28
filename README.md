# NotePlan Cleaner
Ruby script to clean up recently-changed NotePlan app files.
Runs with both iCloud or Dropbox storage.

## Running the Cleaner
There are 2 ways of running this:
1. with passed filename pattern, where it works on any matching Calendar or Note files. For example, '202003*.txt' for example
2. with no arguments, it checks all files updated in the last 24 hours. 

When cleaning, it
- removes the time part of any @done() mentions that NotePlan automatically adds
- removes #waiting or #high tags from @done tasks (configurable)
- remove any lines with just * or -
- moves any calendar entries with [[Note link]] in it to that note, after the header section
- changes any mentions of date offset patterns (e.g. {-10d}, {+2w}, {-3m}) to being scheduled dates (e.g. >2020-02-27), if it can find a DD-MM-YYYY date pattern in the previous markdown heading

## Configuration
Set the following constants at the top of the file:
- StorageType: select whether you're using iCloud for storage (the default) or Drobpox
- NumHeaderLines: number of lines at the start of a note file to regard as the header. The default is 1. Relevant when moving lines around.
- Username: your username
- TagsToRemove: list of tags to remove. Default ["#waiting","#high"]

## Automatic running
This can be configured to run automatically using macOS launchctl.

## TODO
[ ] Extend the built-in archive capability with a more powerful version that understands sub-heads with a file, and information-only lines.
