# NotePlan Cleaner
Ruby script to clean up NotePlan app files.

When cleaning, it
1. removes the time part of any `@done(...)` mentions that NotePlan automatically adds
1. removes `#waiting` or `#high` tags from `@done` tasks (configurable)
1. remove any lines with just * or -
1. removes any trailing blank lines
1. moves any calendar entries with `[[Note link]]` in it to that note, directly after the header section. Further:
   1. where the line is a task, it moves the task and any following indented lines (optionally terminated by a blank line)
   2. where the line is a heading, it moves the heading and all following lines until a blank line, or the next heading of the same level
1. changes any mentions of **date offset patterns** (e.g. `{-10d}`, `{+2w}`, `{-3m}` or special case `{0d}`) to being scheduled dates (e.g. `>2020-02-27`), if it can find a DD-MM-YYYY date pattern in the previous markdown heading. (It also ignores offsets in a section with a heading that includes a #template hashtag.)
1. for newly completed tasks with a `@repeat(_interval_)` **create a new repeat** of the task on the appropriate future date. (Valid intervals are `[0-9][dwmqy]`.) There are two types of _interval_:
  - When _interval_ is of the form `+2w` it will duplicate the task for 2 weeks after the date the task was completed.
   - When _interval_ is of the form `2w` it will duplicate the task for 2 weeks after the date the task was last due. If this can't be determined, then default to the first option.

## Running the Cleaner
There are 2 ways of running this:
1. with passed filename pattern(s), where it works on any matching Calendar or Note files. For example, `202003*.txt` 
2. with no arguments, it checks all files updated in the last 24 hours. 

It works with both iCloud or Dropbox storage.

You can also specific command-line options: 
- `-h` for help, 
- `-v` for verbose output 
- `-w` for more verbose output

## Configuration
Set the following constants at the top of the file:
- `StorageType`: select whether you're using iCloud for storage (the default) or Dropbox
- `NumHeaderLines`: number of lines at the start of a note file to regard as the header. The default is 1. Relevant when moving lines around.
- `Username`: your username
- `TagsToRemove`: list of tags to remove. Default ["#waiting","#high"]

## Automatic running
If you wish to run this automatically in the background on macOS, you can do this using the launchctl system. Here's the configuration file `jgc.npClean.plist` that I use to run npClean several times a day:
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- To load this:   launchctl load ~/Library/LaunchAgents/jgc.npClean.plist
     To unload this: launchctl unload ~/Library/LaunchAgents/jgc.npClean.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>jgc.npClean</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ruby</string>
        <string>/Users/jonathan/bin/npClean</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>09</integer>
            <key>Minute</key>
            <integer>09</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>12</integer>
            <key>Minute</key>
            <integer>09</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>18</integer>
            <key>Minute</key>
            <integer>09</integer>
        </dict>
     </array>
    <key>StandardOutPath</key>
     <string>/tmp/jgc.npClean.stdout</string>
     <key>StandardErrorPath</key>
     <string>/tmp/jgc.npClean.stderr</string>
</dict>
</plist>
```
Update the filepaths to suit your particular configuration, place this in the `~/Library/LaunchAgents` directory,  and then run the following terminal command:
```
launchctl load ~/Library/LaunchAgents/jgc.npClean.plist
```

## TODO
See the [GitHub project](https://github.com/jgclark/NotePlan-cleaner) for ideas and issues.
