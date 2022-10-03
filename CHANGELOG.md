# CHANGELOG
As always, `npTools -h` to see the full list of current options.

## v2.3.1, 2022-10-03
- [Fixed] bug with improperly closed frontmatter

## v2.3.0, 2022-06-26
- [Added] supports new Weekly notes, available with NotePlan 3.6.0.

## v2.2.2, 2022-05-17
- [Change] Removed the code to make new notes where linked notes aren't found, as it was unreliable. It will now simply warn the user.

## v2.2.0, 2022-05-10
- [Add] Adds the `--movecomplete` option to move a task from a calendar note to the project note indicated by [[note#title]] but only when the task has been completed. (The earlier '--move' option remains; this does the same, but operates whether or not the task has been completed.)
- [Add] Understands notes with titles in the frontmatter (added NP v3.4.x)
- [Change] Removed `--archive` option, as it isn't ready for use. (It was already turned off by default.)
- [Change] Tidy up logging

## v2.1.0, 31.10.2021
- [Change] The @repeat(..) function now creates the next copy of the repeated task without using the scheduled indicator `[>]` but the regular open task indicator `[ ]`.

## v2.0.0, 31.10.2021
- [Change] Change to using `#!/usr/bin/env ruby` at the start of scripts to make it easier to pick up whatever ruby installation is the user's preference.

## v1.9.7, 28.2.2021
- [Improve] The place where lines moved from daily notes are inserted is now smarter still.
- [Fix] Bugs introduced in refactoring regexes in last release.

## v1.9.4, 23.1.2021
- [Improve] The place where lines moved from daily notes are inserted is now smarter [Issue 39]. Note this removes the NUM_HEADER_LINES user-settable variable.

## v1.9.3, 23.1.2021
- [Fix] Fixed cosmetic bug in moving titled section from daily notes to a project note
- [Fix] Removed stray `>dates` when creating new `@repeat(...)`s

## v1.9.2, 14.2.2021
- [New] Now allow for `>date` events to be moved to from one daily to the one it points to. This has to be activated with the `-m` option, as it will be quite a significant change for some users.

## v1.9.1, 18.1.2021
- [Fix] Fixed bug in file-matching logic [thanks to Dimitry for reporting]
- [Fix] Fixed bug that stopped date pattern matching in calendar files [thanks to Dimitry for reporting]
- [Improve] Clarified the README for how dates are defined when using #create_event.

## v1.9.0, 16.1.2021
- [Add] Command line option `-c` to override how many hours to look back to find changed notes to process
- [Improve] Allow more types of time spec when creating events (e.g. "2.45PM" or "3.15-5.00"
- [Improve] For template dates be more discriminating about where to find dates to match on, so now ignores dates embedded in certain URLs.
- [Fix] spacing around processed template dates (e.g. {3d})
- [Fix] removing headers with empty sections now won't remove header if next content is a lower-level header
- [Clean up] Remove some obsolete code and add some more logging

## v1.8.6 8.1.2021
- [Fix] Allow event creation to work with "Language & Region" settings that use a 12-hour not a 24-hour clock [Issue 37]

## v1.8.6 8.1.2021
- [Add] Works with tasks that use the `- ` and `- [ ]` markers, as well as `* ` and `* [ ]` [Issue 24]

## v1.8.5 8.1.2021
- [Add] For event creation can now also specify time patterns of form 4-6PM and just 3-4
- [Add] Extend logging to see why some files aren't matching for a user

## v1.8.4 8.1.2021
- [Add] Add a second custom date match style for base dates to use in date offset patterns. See README for RE_DATE_OFFSET_CUSTOM.
- [Change] The built-in date match style for base dates is now NotePlan's usual YYYY-MM-DD, not DD-MM-YYYY etc.

## v1.8.3 6.1.2021
- [Improve] Can now use simpler '3PM' type of time spec when creating events.

## v1.8.2. 2.1.2021
- [Improve] Can now customise the `#create_event` tag used to trigger creating events. Also opens the selected Calendar app if needed first, and reduces the delay if not. [Issue 36]

## v1.8.1. 23.12.2020
- [Improve] Can now add location to created events, and copies any description from following indented lines. [Issue 36]

## v1.8.0. 21.12.2020
- [New] Add ability to create events in the Calendar, based on time-blocking syntax. See README for more details. [Issue 36]

## v1.7.4. 19.12.2020
- [Improve] Clarify documentation to show all sorts of lines in daily notes are moved to the mentioned [[note title]], not just task or header lines. Also loosened unnecessarily strict regexes used here.

## v1.7.3. 10.12.2020
- [New] Allow use of weekdays in repeats and template dates (using 'b' rather than usual 'd' for days) [Issue 32]

## v1.7.2, 5.12.2020
- [Improve] Extended the command line option --skiptoday to allow comma-separated list of notes to ignore [thanks to @BMStroh PR32]

## 1.7.1, 26.11.2020
- [New] add --skipfile=file option to ignore particular files [thanks to @BMStroh, issue 30]
- [Fix] Blank headers at EOF not removed [thanks to @BMStroh, PR31]

## 1.7.0, 19.11.2020
- [New] where the note for a  `[[Note link]]` doesn't exist, it is created in the top-level Notes folder first

## v1.6.1, 13.11.2020
- [New] remove [>] tasks from calendar notes, as there will be a duplicate (whether or not the 'Append links when scheduling' option is set or not)

## v1.6, 13.11.2020
- [New] Added the command line info for --skiptoday [thanks to @BMStroh, PR28]
- [Improve] Make the configuration easier for first time users [thanks to @BMStroh, PR27]

## v1.5.1, 3.11.2020
- [Change] Now default to using the sandbox location for CloudKit storage (change from NotePlan 3.0.15 beta)
- [Fix] Calendar files apparently disappearing if the default file extension is set to .md

## v1.5.0, 25.10.2020
- [New] Remove empty header lines and empty header sections

## v1.4.9, 17.10.2020
- [New] Add -q (--quiet) option to suppress all output apart from errors

## v1.4.8, 23.9.2020
- [Improve] Handling of edge case where there are two identically-named notes in different sub-folders. When moving a task to them, pick the most recently note to move it to. (issue 21)

## v1.4.7, 20.9.2020
- [Fix] Improve finding files with .md as well as .txt extensions, as well as more smartly handling supplied filename patterns

## v1.4.6, 19.8.2020
- [Improve] Ignore empty NotePlan data files (issue 12), and simplify file-glob coding to ignore @Archive and @Trash sub-directories

## v1.4.5, 19.8.2020
- [Fix] nil error in moving tasks to [[Note]] (issue 19)

## v1.4.4, 19.8.2020
- [New] Allow for future NP change to allow .md files not just .txt files (issue 20)

## v1.4.3, 2.8.2020
- [Fix] Error in calculation of yearly repeats (issue 18)

## v1.4.2, 1.8.2020
- [Change] allow @done(date) to be tided up when time has AM/PM suffix (issue 17)

## v1.4.1, 1.8.2020
- [New] add new --noarchive option (issue 16)
- [New] add new --keepscheduled option (issue 14,15)

## v1.4.0,  26.7.2020
- [Change] Script now called `npTools`
- [Improve] Significant improvements to documentation

## v1.3.0,  19.7.2020
- [New] Make work with CloudKit storage, available for NP v3 beta (issue 11), 

## v1.2.8, 13.2020
- [Fix] infinite loop on missing note (issue 8)

## v1.2.6, 8.6.2020
- [New] remove empty trailing lines (issue 10)

## v1.2.4, 2.5.2020
- [New] also move headings with a [[Note]] marker and all its child tasks, notes and comments (issue 6)

## v1.2, 1.5.2020
- [New] add generation of @repeat-ed tasks (issue 2)
- [Improve] documentation

## v1.1, 16.3.2020
- [New] add ability to find and clean notes in folders (from NP v2.4) (issue 1)
- [Improve] file error handling

## v1.0, 28.2.2020
- [New] added first set of command line options (-h, -v, -w)
- [Change] date offsets are now ignored in a section with a heading that includes a #template hashtag.

## v0.6.9, 26.2.2020
* [New] changes any mentions of date offset patterns (e.g. {-10d}, {+2w}, {-3m}) to being scheduled dates (e.g. >2020-02-27), if it can find a DD-MM-YYYY date pattern in the previous markdown heading

## v0.6.7, 24.2.2020
* [New] adds colouration of output (using https://github.com/fazibear/colorize)
* [Change] move open and now closed tasks with [[Note]] mentions

## v0.6.0, 27.11.2019
- [New] remove a set of user-specified tags from @done tasks, via constant `TagsToRemove`

## 0.5.0, 26.11.2019
Initial commit to GitHub repository. Already does the following cleaning up:

- removes the time component of any @done() mentions that NP automatically adds
- removes #waiting or #high tags from @done tasks
- remove any lines with just * or -
- moves any calendar entries with [[Note link]] in it to that note, after the header section.
