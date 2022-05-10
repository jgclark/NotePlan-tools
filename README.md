# NotePlan Tools

**Note: Much of the capability of this script is now available through the Plugins I've written that are available through NotePlan v3.  Please see [this overview](https://help.noteplan.co/article/65-commandbar-plugins), and the individual [plugins' details in the GitHub repository](https://github.com/NotePlan/plugins).**

`npTools.rb` is a Ruby script that adds functionality to the [NotePlan app](https://noteplan.co/). Particularly when run frequently, this provides a more flexible system for repeating tasks, allows for due dates to be expressed as offsets and therefore templates, moves items from Daily files to Note files, and creates events. It incorporates an earlier script to 'clean' or tidy up NotePlan's data files.

Each time the script runs, it does a number of things, explained in each section:

### Tidy up

It **tidies up** data files, by:
1. removing the time part of any `@done(...)` mentions that NotePlan automatically adds when the 'Append Completion Date' option is on.
2. removing `#waiting` or `#high` tags or `<dates` from completed or cancelled tasks (configurable)
3. removing scheduled (`* [>] task`) items in calendar files (as they've been copied to a new day)
4. removing any lines with just `* `or `-` or starting `#`s
5. removing header lines without any content before the next header line of the same or higher level (i.e. fewer `#`s)
6. removing any multiple consecutive blank lines.

### Moves Daily (Calendar) note items
(From v1.9.2) The script can now move any Daily note entries with a **`>date`** in it to the mentioned Daily note. To do so requires turning on through the `-m` option.

In more detail:
- where the line is a heading, it moves the heading and all following lines until a blank line, or the next heading of the same level
- where the line isn't a heading, it moves the line and any following indented lines (optionally terminated by a blank line)
- the lines are inserted after a section heading (e.g. '### Tasks') as defined in the DAILY_TASKS_SECTION_NAME constant (or after header if this is blank). (To configure this constant, see below.)
- where the note for the mentioned `>date` doesn't exist, it is created first

NB: This only operates from Daily (Calendar) notes; it therefore doesn't interfere with **linking and back-linking** between main notes.

### Files Daily (Calendar) note tasks
The script can move any Daily note tasks with **a `[[Note title]]`** in it to the mentioned note, **filing** them directly after the header section.

In more detail:
- where the line is a heading, it moves the heading and all following lines until a blank line, or the next heading of the same level
- where the line isn't a heading, it moves the line and any following indented lines (optionally terminated by a blank line)
- where the note for a  `[[Note link]]` doesn't exist, it is created in the top-level Notes folder first
- if there is a `>YYYY-MM-DD` date specified in the line already, then carry that over, otherwise  add today's date

This feature can be turned on using two different options, with slightly different triggers:
- `-m` (`--move`): move tasks with such a note link, _whether or not the task is complete_;
- `-t` (`--movecomplete`): move only _completed tasks_.

NB: This only operates from Daily (Calendar) notes; therefore it _doesn't_ interfere with linking and back-linking between regular notes.

### Templates for dates
It changes any mentions of **date offset patterns** (such as `{-10d}`, `{+2w}`, `{-3m}`) into scheduled dates (e.g. `>2020-02-27`), if it can find a valid date pattern in the previous heading, previous main task if it has sub-tasks, or in the line itself. This allows for users to define simple **template sections** and copy and paste them into the note, set the due date at the start, and the other dates are then worked out for you.

| For example ...                                                                                                                                                                        | ... becomes                                                                                                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| \#\#\# Christmas Cards 25/12/2020<br />\* Write cards {-20d}<br />\* Post overseas cards {-15d}<br />\* Post cards to this country {-10d}<br />\* Store spare cards for next year {+3d} | \#\#\# Christmas Cards 25/12/2020<br />\* Write cards >2020-12-05<br />\* Post overseas cards >2020-12-10<br />* Post cards to this country >2020-12-15<br />\* Store spare cards for next year >2020-12-28 |
| \* Bob's birthday on 14/09/2020<br />&nbsp;&nbsp;\* Find present {-6d}<br />&nbsp;&nbsp;\* Wrap & post present {-3d} <br />&nbsp;&nbsp;\* Call Bob {0d}                                 | \* Bob's birthday on 14/09/2020<br />&nbsp;&nbsp;\* Find present >2020-09-08<br />&nbsp;&nbsp;\* Wrap & post present >2020-09-11<br />&nbsp;&nbsp;\* Call Bob >2020-09-14                                   |

You can use this within a line to have both a **deadline** and a calculated **start date**:

| For example ...                                                      | ... becomes                                                                       |
| ---------------------------------------------------------- | -------------------------------------------------------------------- |
| * Post cards deadline 2020-12-18 {-10d} | * Post cards deadline 2020-12-18 >2020-12-08 |

In more detail:

- Valid **date offsets** are specified as `[+][0-9][bdwmqy]`. This allows for `b`usiness days,  `d`ays, `w`eeks, `m`onths, `q`uarters or `y`ears. (Business days skip weekends. If the existing date happens to be on a weekend, it's treated as being the next working day. Public holidays aren't accounted for.)  There's also the special case `{0d}` meaning on the day itself.
- It ignores offsets in a section with a heading that includes a `#template` hashtag
- The base date is by default of the form `YYYY-MM-DD`, not preceded by characters `0-9(<>`, all of which could confuse.
- But you can add another custom date format to use by setting the `RE_DATE_FORMAT_CUSTOM` variable (see below). The dates matched by this regular expression must additionally be caapble of being correctly parsed by ruby's Date.parse() built-in command, over which I have no control.

### Create new Calendar Events
NotePlan allows for time-blocking, but this only works to its in-built calendar display. With npTools you also **create events** that are visible and editable in Apple Calendar, or any other apps that use iCloud, *not just NotePlan*.  To do this use the `#create_event` tag on a line (task, comment or heading) with a timeblocking command such as `3:00-3:45[AM|PM]` or `3-5pm` or `3PM` and optional location such as `at Jim's`. This allows for meeting events to be listed on a day, and also created in the calendar. In combination with the date offset patterns above, it further allows scheduling preparation time (for example) days or hours before events.

The date of the event is determined in this order:
1. it will use a `>YYYY-MM-DD` mentioned in the line. NB:  date offset patterns get calculated before it looks to create events.
2. if it's a calendar note, then use that date
3. otherwise use today's date.

For example to create a meeting event for a certain day put this in it's daily (calendar) note:
```
### Project X Meeting #create_event 10:30am at Jim's
```

To extend this and use the date templates, add a timed task with calendar entry to do some associated tasks 5 days before it, and the following morning:
```
### Project X Meeting 21-12-2020 #create_event 10:30am at Jim's
* write and circulate agenda {-5d} #create_event 4pm
* send out actions {1d} #create_event 9am
```

![Video showing event creation](npTools-create_event.gif)

Notes on this:
- If no date is given on the line, and 
- If no finish time is set, then the event defaults to an hour.
- You can use the shortcut `3PM` or `3-5PM` when you don't need to specify the minutes -- though NotePlan itself currently doesn't recognise this syntax for time blocks. You can specify minutes as well either using `3:45` or `3.15` formats.
- If am/AM or pm/PM isn't given, then the hours are assumed to be in 24-hour clock
- It's best to put any `at place` location at the end of the line, as there's no easy way of telling how a location finishes, so it will use the rest of the line as the location.
- Any indented following lines are copied to the event description, with leading whitespace removed.
- Under the hood this uses AppleScript, and takes a few seconds per event.  Once it has run succesfully the `#create_event` is changed to `#event_created` so that it won't be triggered again.  
- There are some calendar settings that need to be configured for this: see Installation and Configuration below.

### Extend the existing @repeat mechanism
It **creates new repeats** for newly completed tasks that include a `@repeat(interval)`, on the appropriate future date.

- Valid intervals are specified as `[+][0-9][bdwmqy]`. This allows for `b`usiness days, `d`ays, `w`eeks, `m`onths, `q`uarters or `y`ears.
- When _interval_ is of the form `+2w` it will duplicate the task for 2 weeks after the date the _task was completed_.
- When _interval_ is of the form `2w` it will duplicate the task for 2 weeks after the date the _task was last due_. If this can't be determined, then it defaults to the first option.

NB: For this feature to work, you need to have the 'Append Completion Date'  NotePlan setting turned on, and to have the first type of tidy up (above) happening.

<!-- In future, extending the **archiving** system. -->

## Running the Tools
There are 2 ways of running the script:
1. with no arguments (`ruby npTools.rb`), it checks all note and daily files updated in the last 24 hours. This is the way to use it automatically, running one or more times each day. (This is configurable by `HOURS_TO_PROCESS` below.)
2. with passed filename pattern(s), where it works on any matching Calendar or Note files. For example, to match the Daily file from 24/3/2020 use `ruby npTools.rb 20200324.txt`. It can include wildcard *patterns* to match multiple files, for example `"202003*.txt"` to process all Daily files from March 2020.  (It now needs to be in double quotes for the file pattern matching to work.) If no `.` is found in the pattern, the pattern matches all files as `"*pattern*.*"`.

You can also specify the following **options**:
- `-h` (`--help`) for a list of options, 
<!-- - `-a` (`--noarchive`) don't archive completed tasks into the `## Done` section. -->
- `c` (`--changes HOURS`) how many hours to look back to find note changes to process, overriding the default of 24 hours (though this can be changed; see below)
- `-d` (`--moveondailies`) turn on moving mentions of `>date` in a daily calendar note to the specified date
- `-i` (`--skiptoday`) don't process today's file
- `-f` (`--skipfile=NOTETITLE[,NOTETITLE2,etc]`) don't process specific note(s)
- `-m` (`--move`) moves mentions of [[Note#Heading]] in tasks in daily calendar day notes to the [[Note]], _whether or note the task has been completed_
- `-t` (`--movecomplete`) moves mentions of [[Note#Heading]] in tasks in daily calendar day notes to the [[Note]], _but only when the task has been completed_
- `-q` (`--quiet`) suppress all output, other than error messages
- `-s` (`--keepschedules`) keep the scheduled (>) dates of completed tasks
- `-v` for verbose (logging) output 
- `-w` for more verbose (logging) output

It works with all 3 storage options for storing NotePlan data: CloudKit (the default from NotePlan v3), iCloud Drive and Dropbox.

**NB**: NotePlan has several options in the Markdown settings for how to mark a task, including `-`, `- [ ]', `*` and `* [ ]`. All are supported by this script.

## Installation and Configuration
1. Check you have a working Ruby installation.
2. Install two ruby gems (libraries) (`sudo gem install colorize optparse`)
3. Download and copy the script to a place where it can be found on your FILE filepath (perhaps `sudo cp npTools.rb /usr/local/bin/`)
4. Make the script executable (`chmod 755 npTools.rb`)
5. Change the following constants at the top of the script, as required:
- `hours_to_process`: will process all files changed within this number of hours (default 24)
- `TAGS_TO_REMOVE`: list of tags to remove. Default ["#waiting","#high"]
- `DAILY_TASKS_SECTION_NAME`: the section heading name (without `#` marks) to file moved tasks in
- `DATE_TIME_LOG_FORMAT`: date string format to use in logs
- `DATE_TIME_APPLESCRIPT_FORMAT`: date string format to use in AppleScript for event creation -- depends on various locale settings
- `CALENDAR_APP_TO_USE`: name of Calendar app to use in create_event AppleScript. Default is 'Calendar'. Can ignore if not using this for event creation.
- `CALENDAR_NAME_TO_USE`: name of Calendar to create any new events in. Can ignore if not using this for event creation.
- `CREATE_EVENT_TAG_TO_USE`: name of tag to use to trigger creating events. Default is `#create_event`. Can ignore if not using this for event creation.
- for completeness, `NP_BASE_DIR` automatically works out where NotePlan data files are located. (If there are multiple isntallations it selects using the priority CloudKit > iCloudDrive > DropBox.)
- `RE_DATE_OFFSET_FORMAT`: regular expression to find date strings in your chosen format, to use as the base date in date offset patterns. See example in the code, but don't change unless you're familiar with regular expressions.
6. Then run `ruby npTools.rb [-options]`

The first time you attempt to `#create_event`, macOS (at least Catalina and Big Sur) will probably ask for permission to update your Calendar.

### Automatic running
If you wish to run this automatically in the background on macOS, you can do this using the built-in `launchctl` system. (For more info on this see for example [How to Use launchd to Run Services in macOS](https://medium.com/swlh/how-to-use-launchd-to-run-services-in-macos-b972ed1e352).)

Here's the configuration file `jgc.npTools.plist` that I use to automatically run `npTools.rb` three times a day:
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- To load this:   launchctl load ~/Library/LaunchAgents/jgc.npTools.plist
     To unload this: launchctl unload ~/Library/LaunchAgents/jgc.npTools.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>jgc.npTools</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ruby</string>
        <string>/Users/jonathan/bin/npTools</string>
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
     <string>/tmp/jgc.npTools.stdout</string>
     <key>StandardErrorPath</key>
     <string>/tmp/jgc.npTools.stderr</string>
</dict>
</plist>
```
Update the filepaths to suit your particular configuration, place this in the `~/Library/LaunchAgents` directory,  and then run the following terminal command:
```
launchctl load ~/Library/LaunchAgents/jgc.npTools.plist
```

## Problems? Suggestions?
See the [GitHub project](https://github.com/jgclark/NotePlan-tools) for issues, or suggest improvements.
