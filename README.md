# NotePlan Cleaner
Ruby script to clean up recently-changed NotePlan app files.

When cleaning, it
1. removes the time part of any @done() mentions that NotePlan automatically adds
1. removes #waiting or #high tags from @done tasks (configurable)
1. remove any lines with just * or -
1. moves any calendar entries with [[Note link]] in it to that note, after the header section
1. changes any mentions of **date offset patterns** (e.g. {-10d}, {+2w}, {-3m}) to being scheduled dates (e.g. >2020-02-27), if it can find a DD-MM-YYYY date pattern in the previous markdown heading. (It also ignores offsets in a section with a heading that includes a #template hashtag.)
1. for newly completed tasks with a @repeat(_interval_) **create a new repeat** of the task on the appropriate future date. (Valid intervals are [0-9][dwmqy].) There are two types of _interval_:
  - When _interval_ is of the form +2w it will duplicate the task for 2 weeks after the date the task was completed.
   - When _interval_ is of the form 2w it will duplicate the task for 2 weeks after the date the task was last due. If this can't be determined, then default to the first option.

## Running the Cleaner
There are 2 ways of running this:
1. with passed filename pattern(s), where it works on any matching Calendar or Note files. For example, '202003*.txt' 
2. with no arguments, it checks all files updated in the last 24 hours. 

It works with both iCloud or Dropbox storage.

You can also specific command-line options: 
- -h for help, 
- -v for verbose output 
- -w for more verbose output

## Configuration
Set the following constants at the top of the file:
- StorageType: select whether you're using iCloud for storage (the default) or Drobpox
- NumHeaderLines: number of lines at the start of a note file to regard as the header. The default is 1. Relevant when moving lines around.
- Username: your username
- TagsToRemove: list of tags to remove. Default ["#waiting","#high"]

## Automatic running
This can be configured to run automatically using macOS launchctl.

## TODO
See GitHub project for ideas and issues.
