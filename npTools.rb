#!/usr/bin/ruby
#-------------------------------------------------------------------------------
# NotePlan Tools script
# by Jonathan Clark, v1.9.5, 24.2.2021
#-------------------------------------------------------------------------------
# See README.md file for details, how to run and configure it.
# Repository: https://github.com/jgclark/NotePlan-tools/
#-------------------------------------------------------------------------------
VERSION = "1.9.5"

require 'date'
require 'time'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
hours_to_process = 24 # by default will process all files changed within this number of hours
TAGS_TO_REMOVE = ['#waiting', '#high', '#started', '#⭐'].freeze # simple array of strings
DAILY_TASKS_SECTION_NAME = '### Tasks' # set to a section heading you'd like to file tasks to in daily notes
DATE_TIME_LOG_FORMAT = '%e %b %Y %H:%M'.freeze # only used in logging
# DATE_TIME_APPLESCRIPT_FORMAT = '%e %b %Y %I:%M %p'.freeze # format for creating Calendar events (via AppleScript) when Region setting is 12-hour clock
DATE_TIME_APPLESCRIPT_FORMAT = '%e %b %Y %H:%M:%S'.freeze # format for creating Calendar events (via AppleScript) when Region setting is 24-hour clock
CALENDAR_APP_TO_USE = 'Calendar' # Name of Calendar app to use in create_event AppleScript. Default is 'Calendar'.
CALENDAR_NAME_TO_USE = 'Jonathan (iCloud)' # Apple (iCal) Calendar name to create new events in (if required)
CREATE_EVENT_TAG_TO_USE = '#create_event' # customise if you want a different tag
NOTE_EXT = 'md' # or 'txt'

#-------------------------------------------------------------------------------
# Other Constants & Settings
#-------------------------------------------------------------------------------
DATE_TODAY_FORMAT = '%Y%m%d'.freeze # using this to identify the "today" daily note
USERNAME = ENV['LOGNAME'] # pull username from environment
USER_DIR = ENV['HOME'] # pull home directory from environment
DROPBOX_DIR = "#{USER_DIR}/Dropbox/Apps/NotePlan/Documents".freeze
ICLOUDDRIVE_DIR = "#{USER_DIR}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents".freeze
CLOUDKIT_DIR = "#{USER_DIR}/Library/Containers/co.noteplan.NotePlan3/Data/Library/Application Support/co.noteplan.NotePlan3".freeze
np_base_dir = DROPBOX_DIR if Dir.exist?(DROPBOX_DIR) && Dir[File.join(DROPBOX_DIR, '**', '*')].count { |file| File.file?(file) } > 1
np_base_dir = ICLOUDDRIVE_DIR if Dir.exist?(ICLOUDDRIVE_DIR) && Dir[File.join(ICLOUDDRIVE_DIR, '**', '*')].count { |file| File.file?(file) } > 1
np_base_dir = CLOUDKIT_DIR if Dir.exist?(CLOUDKIT_DIR) && Dir[File.join(CLOUDKIT_DIR, '**', '*')].count { |file| File.file?(file) } > 1
NP_NOTES_DIR = "#{np_base_dir}/Notes".freeze
NP_CALENDAR_DIR = "#{np_base_dir}/Calendar".freeze

#-------------------------------------------------------------------------------
# Regex definitions (where they're likely to be re-used)
#-------------------------------------------------------------------------------
RE_DATE = '\d{4}[\-\.//][01]?\d[\-\.//]\d{1,2}' # built-in format for finding dates of form YYYY-MM-DD and similar
RE_DATE_TIME = "#{RE_DATE} \d{2}:\d{2}(?:.(?:AM|PM))?" # YYYY-MM-DD HH:MM[AM|PM]
RE_DATE_FORMAT_CUSTOM = '\d{1,2}[\-\.//][01]?\d[\-\.//]\d{4}'.freeze # regular expression of alternative format used to find dates in templates. This matches DD.MM.YYYY and similar.
RE_DUE_DATE = ">#{RE_DATE}" # find '>2021-02-23' etc.
RE_DUE_DATE_CAPTURE = ">(#{RE_DATE})" # find ' >2021-02-23' and return just date part
RE_RESCHED_FROM_DATE = "<#{RE_DATE}" # find '<2021-02-23' etc.
RE_DATE_INTERVAL = "[+\-]?\d+[bdwm]"
RE_DATE_INTERVAL_CAPTURE = "(#{RE_DATE_INTERVAL})"
RE_NOTE_LINK = '\[\[.+?\]\]' # find '[[note title]]' (not greedy)
RE_NOTE_LINK_CAPTURE = '\[\[(.+?)\]\]' # find '[[note title]]' (not greedy)

# Colours to use with the colorization gem
# to show some possible combinations, run  String.color_samples
# to show list of possible modes, run   puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
InfoColour = :yellow
WarningColour = :light_red

# Variables that need to be globally available
time_now = Time.now
time_now_fmttd = time_now.strftime(DATE_TIME_LOG_FORMAT)
$verbose = 0
$archive = 0
$remove_rescheduled = 1
$allNotes = []  # to hold all note objects
$notes    = []  # to hold all note objects selected for processing
$date_today = time_now.strftime(DATE_TODAY_FORMAT)
$npfile_count = -1 # number of NPFile objects created so far (incremented before first use)

#-------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------

def main_message_screen(message)
  puts message.colorize(CompletedColour)
end

def warning_message_screen(message)
  puts message.colorize(InfoColour)
end

def error_message_screen(message)
  puts message.colorize(ErrorColour)
end

def log_message_screen(message)
  puts message if $verbose
end

def calc_offset_date(old_date, interval)
  # Calculate next review date, assuming:
  # - old_date is type
  # - interval is string of form nn[bdwmq]
  #   - where 'b' is weekday (i.e. Monday-Friday in English)
  # puts "    c_o_d: old #{old_date} interval #{interval} ..."
  days_to_add = 0
  unit = interval[-1] # i.e. get last characters
  num = interval.chop.to_i
  case unit
  when 'b' # week days
    # Method from Arjen at https://stackoverflow.com/questions/279296/adding-days-to-a-date-but-excluding-weekends
    # Avoids looping, and copes with negative intervals too
    current_day_of_week = old_date.strftime("%u").to_i  # = day of week with Monday = 0, .. Sunday = 6
    dayOfWeek = num.negative? ? (current_day_of_week - 12).modulo(7) : (current_day_of_week + 6).modulo(7)
    num -= 1 if dayOfWeek == 6
    num += 1 if dayOfWeek == -6
    days_to_add = num + (num + dayOfWeek).div(5) * 2
  when 'd'
    days_to_add = num
  when 'w'
    days_to_add = num * 7
  when 'm'
    days_to_add = num * 30 # on average. Better to use >> operator, but it only works for months
  when 'q'
    days_to_add = num * 91 # on average
  when 'y'
    days_to_add = num * 365 # on average
  else
    puts "    Error in calc_offset_date from #{old_date} by #{interval}".colorize(WarningColour)
  end
  puts "    c_o_d: with #{old_date} interval #{interval} found #{days_to_add} days_to_add" if $verbose > 1
  return old_date + days_to_add
end

def create_new_note_file(title, ext)
  # Populate empty NPFile object for a *non-daily note*, adding just title.
  # Returns id of new note

  # Use x-callback scheme to add a new note in NotePlan,
  # as defined at http://noteplan.co/faq/General/X-Callback-Url%20Scheme/
  #   noteplan://x-callback-url/addNote?text=New%20Note&openNote=no
  # Open a note identified by the title or date.
  # Parameters:
  # - noteTitle optional, will be prepended if it is used
  # - text optional, text will be added to the note
  # - openNote optional, values: yes (opens the note, if not already selected), no
  # - subWindow optional (only Mac), values: yes (opens note in a subwindow) and no

  # NOTE: So far this can only create notes in the top-level Notes folder
  # Does cope with emojis in titles.

  uriEncoded = "noteplan://x-callback-url/addNote?noteTitle=#{URI.escape(title)}&openNote=no"
  response = `open "#{uriEncoded}"`
  if response != ''
    puts "  Error #{response} trying to add note with #{uriEncoded}. Exiting.".colorize(WarningColour)
    exit
  end

  # Now read this new file into the $allNotes array
  Dir.chdir(NP_NOTES_DIR)
  sleep(2) # wait for the file to become available. TODO: probably a smarter way to do this. What about marking as changed, and adding to a separate array of new notes to write out?
  filename = "#{title}.#{ext}"
  new_note = NPFile.new(filename)
  new_note_id = new_note.id
  $allNotes[new_note_id] = new_note # now the following
  puts "Added new note id #{new_note_id} with title '#{title}' and filename '#{filename}'. New $allNotes count = #{$allNotes.count}" if $verbose > 1
  return new_note_id
end

def find_or_create_daily_note(yyyymmdd)
  # Read in a note that we want to update. If it doesn't exist, create it.
  puts "    - starting find_or_create_daily_note for #{yyyymmdd}" if $verbose > 1
  filename = "#{yyyymmdd}.#{NOTE_EXT}"
  noteToAddTo = nil  # for an integer, but starting as nil

  # First check if it exists in existing notes read in
  $allNotes.each do |nn|
    next if nn.filename != filename

    noteToAddTo = nn.id
    puts "      - found match via filename (id #{noteToAddTo}) " if $verbose > 1
  end

  if noteToAddTo.nil?
    # now try reading in an existing daily note
    Dir.chdir(NP_CALENDAR_DIR)
    puts "    - Looking for daily note filename #{filename}:" if $verbose > 0
    if File.exist?(filename)
      $allNotes << NPFile.new(filename)
      # now find the id of this most-recently-added NPFile instance
      noteToAddTo = $npfile_count
      puts "      - read in match via filename (-> id #{noteToAddTo}) " if $verbose > 1
    else
      # finally, we need create the note
      puts "        - warning: can't find matching note filename '#{filename}' -- so will create it".colorize(InfoColour)
      begin
        f = File.new(filename, 'a+')
        f.close
      rescue StandardError => e
        puts "ERROR: #{e.exception.message} when creating daily note file #{filename}".colorize(WarningColour)
      end
      $allNotes << NPFile.new(filename)
      # now find the id of this newly-created NPFile instance
      noteToAddTo = $npfile_count
      puts "    -> file '#{$allNotes[noteToAddTo - 1].filename}' id #{noteToAddTo}" if $verbose > 0
    end
  end
  return noteToAddTo
end

def find_or_create_note(title)
  # Read in a note that we want to update.
  # If it doesn't exist, create it.

  # NOTE: In NP v2.4+ there's a slight issue that there can be duplicate
  # note titles over different sub-folders. This will likely be improved in
  # the future, but for now I'll try to select the most recently-changed if
  # there are matching names.

  puts "    - starting find_or_create_note for '#{title}'" if $verbose > 1
  new_note_id = nil  # for an integer, but starting as nil

  # First check if it exists in existing notes read in
  mtime = Time.new(1970, 1, 1) # i.e. the earlist possible time
  $allNotes.each do |nn|
    next if nn.title != title

    next unless nn.modified_time > mtime

    new_note_id = nn.id
    mtime = nn.modified_time
    puts "      - found existing match via title (id #{new_note_id}) last modified #{mtime}" if $verbose > 1
  end

  if new_note_id.nil?
    # not found, so now we need create the note
    puts "        - warning: can't find matching note title '#{title}' -- so will create it".colorize(InfoColour)
    new_note_id = create_new_note_file(title, NOTE_EXT)
    # begin
    #   f = File.new(filename, 'a+') # assume it goes in top level folder
    #   f.close
    # rescue StandardError => e
    #   puts "ERROR: #{e.exception.message} when creating note file #{filename}".colorize(WarningColour)
    # end
    # now find the id of this newly-created NPFile instance
    puts "    -> file '#{$allNotes[new_note_id].filename}' id #{new_note_id}" if $verbose > 0
  end
  return new_note_id
end

def osascript(script)
  # Run applescript
  # from gist https://gist.github.com/dinge/6983008
  puts "About to execute this AppleScript:\n#{script}\n" if $verbose > 1
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

#-------------------------------------------------------------------------
# Class definition: NPFile
# NB: in this script this class covers Note *and* Daily files
#-------------------------------------------------------------------------
class NPFile
  # Define the attributes that need to be visible outside the class instances
  attr_reader :id
  attr_reader :title
  attr_reader :cancelled_header
  attr_reader :done_header
  attr_reader :filename
  attr_reader :is_today
  attr_reader :is_calendar
  attr_reader :is_updated
  attr_reader :line_count
  attr_reader :modified_time

  def initialize(this_file)
    # Create NPFile object from reading 'this_file' file

    # Set variables that are visible outside the class instance
    $npfile_count += 1
    @id = $npfile_count
    @filename = this_file
    @modified_time = File.exist?(filename) ? File.mtime(this_file) : 0
    @title = ''
    @lines = []
    @line_count = 0
    @cancelled_header = 0
    @done_header = 0
    @is_today = false
    @is_calendar = false
    @is_updated = false

    # initialise other variables (that don't need to persist with the class)
    n = 0

    # Open file and read in all lines (finding any Done and Cancelled headers)
    # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
    f = File.open(@filename, 'r', encoding: 'utf-8')
    f.each_line do |line|
      @lines[n] = line
      @done_header = n  if line =~ /^## Done$/
      @cancelled_header = n if line =~ /^## Cancelled$/
      n += 1
    end
    f.close
    @line_count = @lines.size
    # Now make a title for this file:
    if @filename =~ /\d{8}\.(txt|md)/
      # for Calendar file, use the date from filename
      @title = @filename[0..7]
      @is_calendar = true
      @is_today = @title == $date_today
    else
      # otherwise use first line (but take off heading characters at the start and starting and ending whitespace)
      tempTitle = @lines[0].gsub(/^#+\s*/, '').gsub(/\s+$/, '')
      @title = !tempTitle.empty? ? tempTitle : 'temp_header' # but check it doesn't get to be blank
      @is_calendar = false
      @is_today = false
    end

    modified = (@modified_time.to_s)[0..15]
    puts "      Init NPFile #{@id}: #{@line_count} lines from #{this_file}, updated #{modified}".colorize(InfoColour) if $verbose > 1
  end

  # def self.new2(*args)
  #   # TODO: Use NotePlan's addNote via x-callback-url instead?
  #   # This is a second initializer, to create a new empty file, so have to use a different syntax.
  #   # Create empty NPFile object, and then pass to detailed initializer
  #   object = allocate
  #   object.create_new_note_file(*args)
  #   object # implicit return
  # end

  # def append_new_line(new_line)
  #   # Append 'new_line' into position
  #   # TODO: should ideally split on '\n' and add each potential line separately
  #   puts '  append_new_line ...' if $verbose > 1
  #   @lines << new_line
  #   @line_count = @lines.size
  # end

  def create_events_from_timeblocks
    # Create calendar event in default calendar from an NP timeblock given in
    # a daily note, where #create_event is specified.
    # (As of NP 3.0 time blocking only works in headers and tasks, but Eduard has
    # said he will add to bullets as well, so I'm doing that already.)
    # Examples:
    #   '* Write proposal at 12-14 #create_event' --> caledar event 12-2pm
    #   '### Write proposal >2020-12-20 at 2pm #create_event' --> caledar event 2pm for 1 hour on that date
    #   '- clear before meeting 2:00-2:30pm #create_event' --> caledar event 2-2:30pm
    puts '  create_events_from_timeblocks ...' if $verbose > 1
    n = 0
    while n < (@done_header.positive? ? @done_header : @line_count)
      this_line = @lines[n]
      unless this_line =~ /#{CREATE_EVENT_TAG_TO_USE}/
        n += 1
        next
      end
      # we have a line with one or more events to create
      # get date: if there's a >YYYY-MM-DD mentioned in the line, use that,
      # otherwise use date of calendar note. Format: YYYYMMDD, or else use today's date.
      event_date_s = ''
      if this_line =~ /#{RE_DUE_DATE}/
        this_line.scan(/#{RE_DUE_DATE_CAPTURE}/) { |m| event_date_s = m.join.tr('-', '') }
        puts "    - found event creation date spec: #{event_date_s}" if $verbose > 1
      elsif @is_calendar
        event_date_s = @filename[0..7]
        puts "    - defaulting to create event on day: #{event_date_s}" if $verbose > 1
      else
        event_date_s = $date_today
        puts "    - defaulting to create event today: #{event_date_s}" if $verbose > 1
      end
      # make title: strip off #create_event, time strings, header/task/bullet punctuation, and any location info
      event_title = this_line.chomp
      event_title.gsub!(/ #{CREATE_EVENT_TAG_TO_USE}/, '')
      event_title.gsub!(/^\s*[*->](\s\[.\])?\s*/, '')
      event_title.gsub!(/^#+\s*/, '')
      event_title.gsub!(/\s\d\d?(-\d\d?)?(am|pm|AM|PM)/, '') # 3PM, 9-11am etc.
      event_title.gsub!(/\s\d\d?:\d\d(-\d\d?:\d\d)?(am|pm|AM|PM)?/, '') # 3:00PM, 9:00-9:45am etc.
      event_title.gsub!(/#{RE_DUE_DATE}/, '')
      event_title.gsub!(/\sat\s.*$/, '')

      # Get times for event.
      # If no end time given, default to a 1-hour duration event.
      # NB: See https://github.com/jgclark/NotePlan-tools/issues/37 for details of an oddity with AppleScript,
      # which means we have to use time format of "HH:MM[ ]am|AM|pm|PM" not "HH:MM:SS" or "HH:MM"
      start_mins = end_mins = start_hour = end_hour = 0
      time_parts = []
      if this_line =~ /[^\d-]\d\d?[:.]\d\d-\d\d?[:.]\d\d(am|pm)?[\s$]/i
        # times of form '3:00-4:00am', '3.00-3.45PM' etc.
        time_parts_da = this_line.scan(/[^\d-](\d\d?)[:.](\d\d)-(\d\d?)[:.](\d\d)(am|pm)?[\s$]/i)
        time_parts = time_parts_da[0]
        puts "    - time_spec type 1: #{time_parts}" if $verbose > 1
        start_hour = time_parts[4] =~ /pm/i ? time_parts[0].to_i + 12 : time_parts[0].to_i
        start_mins = time_parts[1].to_i
        end_hour = time_parts[4] =~ /pm/i ? time_parts[2].to_i + 12 : time_parts[2].to_i
        end_mins = time_parts[3].to_i
      elsif this_line =~ /[^\d-]\d\d?[:.]\d\d(am|pm|AM|PM)?[\s$]/i
        # times of form '3:15[am|pm]'
        time_parts_da = this_line.scan(/[^\d-](\d\d?)[:.](\d\d)(am|pm)?[\s$]/i)
        time_parts = time_parts_da[0]
        puts "    - time_spec type 2: #{time_parts}"
        start_hour = time_parts[2] =~ /pm/i ? time_parts[0].to_i + 12 : time_parts[0].to_i
        start_mins = time_parts[1].to_i
        end_hour = (start_hour + 1).modulo(24) # cope with event crossing midnight
        end_mins = start_mins
      elsif this_line =~ /[^\d-]\d\d?(am|pm)[\s$]/i
        # times of form '3am|PM'
        time_parts_da = this_line.scan(/[^\d-](\d\d?)(am|pm)[\s$]/i)
        time_parts = time_parts_da[0]
        puts "    - time_spec type 3: #{time_parts}" if $verbose > 1
        start_hour = time_parts[1] =~ /pm/i ? time_parts[0].to_i + 12 : time_parts[0].to_i
        start_mins = 0
        end_hour = (start_hour + 1).modulo(24) # cope with event crossing midnight
        end_mins = 0
      elsif this_line =~ /[^\d-]\d\d?-\d\d?(am|pm)[\s$]/i
        # times of form '3-5am|pm'
        time_parts_da = this_line.scan(/[^\d-](\d\d?)-(\d\d?)(am|pm)[\s$]/i)
        time_parts = time_parts_da[0]
        puts "    - time_spec type 4: #{time_parts}" if $verbose > 1
        start_hour = time_parts[2] =~ /pm/i ? time_parts[0].to_i + 12 : time_parts[0].to_i
        start_mins = 0
        end_hour = time_parts[2] =~ /pm/i ? time_parts[1].to_i + 12 : time_parts[1].to_i
        end_mins = 0
      elsif this_line =~ /[^\d-]\d\d?-\d\d?[\s$]/i
        # times of form '3-5', implied 24-hour clock
        time_parts_da = this_line.scan(/[^\d-](\d\d?)-(\d\d?)[\s$]/i)
        time_parts = time_parts_da[0]
        puts "    - time_spec type 5: #{time_parts}" if $verbose > 1
        start_hour = time_parts[0].to_i
        start_mins = 0
        end_hour = time_parts[1].to_i
        end_mins = 0
      else
        # warn as can't find suitable time String
        puts "  - want to create '#{event_title}' event through #create_event, but cannot find suitable time spec".colorize(WarningColour)
        n += 1
        next
      end
      # create start and end datetime formats to use in applescript
      start_dt = DateTime.new(event_date_s[0..3].to_i, event_date_s[4..5].to_i, event_date_s[6..7].to_i, start_hour, start_mins, 0)
      end_dt   = DateTime.new(event_date_s[0..3].to_i, event_date_s[4..5].to_i, event_date_s[6..7].to_i, end_hour, end_mins, 0)
      # deal with special case of event crossing midnight, where we need to add 1 day to end_dt
      if end_dt < start_dt
        puts "  - found special case of crossing midnight:"
        print "    #{start_dt} - #{end_dt} "
        end_dt += 1
        puts " --> #{end_dt}"
      end
      start_dt_s = start_dt.strftime(DATE_TIME_APPLESCRIPT_FORMAT)
      end_dt_s   = end_dt.strftime(DATE_TIME_APPLESCRIPT_FORMAT)
      puts "  - will create event '#{event_title}' from #{start_dt_s} to #{end_dt_s}"

      # use ' at X...' to set the_location (rather than that type of timeblocking)
      the_location = this_line =~ /\sat\s.*/ ? this_line.scan(/\sat\s(.*)/).join : ''

      # Copy any indented comments/notes into the_description field
      the_description = ''
      # Incrementally add lines until we find ones at the same or lower level of indent.
      # (similar to code from move_daily_ref_to_notes)
      line_indent = ''
      this_line.scan(/^(\s*)\*/) { |m| line_indent = m.join }
      puts "    - building event description with starting indent of #{line_indent.length}" if $verbose > 1
      nn = n + 1
      while nn < @line_count
        line_to_check = @lines[nn]
        # What's the indent of this line?
        line_to_check_indent = ''
        line_to_check.scan(/^(\s*)\S/) { |m| line_to_check_indent = m.join }
        break if line_indent.length >= line_to_check_indent.length

        the_description += line_to_check.lstrip # add this line to the description, with leading whitespace removed
        nn += 1
      end

      # Now write the AppleScript and run it
      begin
        osascript <<-APPLESCRIPT
          set calendarName to "#{CALENDAR_NAME_TO_USE}"
          set theSummary to "#{event_title}"
          set theDescrption to "#{the_description}"
          set theLocation to "#{the_location}"
          set startDate to "#{start_dt_s}"
          set endDate to "#{end_dt_s}"
          set startDate to date startDate
          set endDate to date endDate
          if application "#{CALENDAR_APP_TO_USE}" is not running then
            launch application "#{CALENDAR_APP_TO_USE}" # hoped this would start it without a window, but not so
            delay 3 # pause for 3 seconds while app launches
          end if
          tell application "Calendar"
            tell (first calendar whose name is calendarName)
              make new event at end of events with properties {summary:theSummary, start date:startDate, end date:endDate, description:theDescrption, location:theLocation}
            end tell
          end tell
        APPLESCRIPT
        # Now update the line to show #event_created not #create_event
        @lines[n].gsub!(CREATE_EVENT_TAG_TO_USE, '#event_created')
        @is_updated = true
        n += 1
      rescue StandardError => e
        puts "ERROR: #{e.exception.message} when calling AppleScript to create an event".colorize(WarningColour)
      end
    end
  end

  def clear_empty_tasks_or_headers
    # Clean up lines with just * or - or #s in them
    puts '  remove_empty_tasks_or_headers ...' if $verbose > 1
    n = cleaned = 0
    while n < @line_count
      # blank any lines which just have a * or -
      if @lines[n] =~ /^\s*[*\-]\s*$/
        @lines[n] = ''
        cleaned += 1
      end
      # blank any lines which just have #s at the start (and optional following whitespace)
      if @lines[n] =~ /^#+\s?$/
        @lines[n] = ''
        cleaned += 1
      end
      n += 1
    end
    return unless cleaned.positive?

    @is_updated = true
    @line_count = @lines.size
    puts "  - removed #{cleaned} empty lines" if $verbose > 0
  end

  def insert_new_line_at_line(new_line, line_number)
    # Insert 'new_line' into position 'line_number'
    # don't go beyond current size of @lines
    n = line_number >= @lines.size ? @lines.size : line_number
    puts "    insert_new_line_at_line #{n}..." if $verbose > 1
    # break line up into separate lines (on "\n")
    line_a = new_line.split("\n")
    line_a.each do |line|
      @lines.insert(n, line)
      n += 1
    end
    @line_count = @lines.size
  end

  def insert_new_line_at_start_of_section(new_line, section_heading)
    # Insert 'new_line' at start of a section headed 'section_heading'
    # If this is blank, then insert after start-of-note metadata
    puts "  insert_new_line_at_start_of_section '#{section_heading}' ..." if $verbose > 1
    max = @lines.size
    line_number = max # as a fallback treat this as an append
    n = 0 # start iterating from the start of line of he file
    if section_heading.empty?
      # There's no section_heading to find, so insert after frontmatter
      in_frontmatter = false
      while n <= max
        this_line = @lines[n].chomp
        # if we have a blank line or the end of a YAML frontmatter section
        if this_line.empty? || in_frontmatter && (this_line =~ /^\.\.\./ || this_line =~ /^---/)
          line_number = n + 1 # point to next line
          break # stop looking
        end
        in_frontmatter = true if this_line =~ /^---/
        # if we have a section heading or end of a YAML frontmatter section
        if this_line =~ /^##+\s+/
          line_number = n # point to this line (inserts before it)
          break # stop looking
        end
        n += 1
      end
    else # we want to find the section heading
      while n <= max
        if @lines[n] =~ /^#{section_heading}/
          line_number = n + 1 # point to line after title
          break # stop looking
        end
        n += 1
      end
    end
    insert_new_line_at_line(new_line, line_number)
  end

  # TODO: split into two cases; not sure one is really needed
  def append_line_to_section(new_line, section_heading)
    # Append new_line after 'section_heading' line.
    # If not found, then add 'section_heading' to the end first
    # If 'section_heading' is blank, then append in first section after frontmatter, informally defined (i.e. doesn't have to start with ---)
    puts "  append_line_to_section for '#{section_heading}' ..." if $verbose > 1
    n = 0
    max = @lines.size
    line_number = max # as a fallback treat this as an append
    found_section = false
    if section_heading.empty?
      # There's no section_heading to find, so find end of frontmatter instead
      while n < max
        this_line = @lines[n].chomp
        # if we have a blank line or the end of a YAML frontmatter section
        if this_line.empty? && (this_line =~ /^\.\.\./ || this_line =~ /^---/)
          line_number = n # point to next line
          break # stop looking
        end
        # if we have a section heading
        if this_line =~ /^##+\s+/
          line_number = n # point to this line (inserts before it)
          break # stop looking
        end
        n += 1
      end
      found_section = true # we have found the equivalent of the section heading
      n = line_number
      # log_message_screen("    empty heading: insertion point at line #{n}")
    end
    # find the section heading
    added = false
    while !added && (n < max)
      line = @lines[n].chomp
      # if an empty line or a new header section starting, insert line here
      if found_section && (line.empty? || line =~ /^#+\s/)
        insert_new_line(new_line, n)
        added = true
      end
      # if this is the section header of interest, save its details. (Needs to come after previous test.)
      found_section = true if line =~ /^#{section_heading}/
      n += 1
    end
    puts "    final part with found_section #{found_section}, added #{added}" if $verbose > 1
    insert_new_line_at_line(new_line, n) unless added # if not added so far, then now append
    insert_new_line_at_line(section_heading, n) unless found_section # if section not yet found then add it before this line
  end

  def remove_unwanted_tags_dates
    # removes specific tags and >dates from complete or cancelled tasks
    puts '  remove_unwanted_tags_dates ...' if $verbose > 1
    n = cleaned = 0
    while n < @line_count
      # only do something if this is a completed or cancelled task
      if @lines[n] =~ /\[(x|-)\]/
        # remove any <YYYY-MM-DD on completed or cancelled tasks
        if $remove_rescheduled == 1
          if @lines[n] =~ /\s#{RE_RESCHED_FROM_DATE}/
            @lines[n].gsub!(/\s#{RE_RESCHED_FROM_DATE}/, '')
            cleaned += 1
          end
        end

        # Remove any tags from the TagsToRemove list. Iterate over that array:
        TAGS_TO_REMOVE.each do |tag|
          if @lines[n] =~ /#{tag}/
            @lines[n].gsub!(/ #{tag}/, '')
            cleaned += 1
          end
        end
      end
      n += 1
    end
    return unless cleaned.positive?

    @is_updated = true
    puts "  - removed #{cleaned} tags" if $verbose > 0
  end

  def remove_rescheduled
    # FIXME: all this needs checking
    # remove [>] tasks from calendar notes, as there will be a duplicate
    # (whether or not the 'Append links when scheduling' option is set or not)
    puts '  remove_rescheduled ...' if $verbose > 1
    n = cleaned = 0
    while n < @line_count
      # Empty any [>] todo lines
      if @lines[n] =~ /\[>\]/
        @lines.delete_at(n)
        @line_count -= 1
        n -= 1
        cleaned += 1
      end
      n += 1
    end
    return unless cleaned.positive?

    @is_updated = true
    puts "  - removed #{cleaned} scheduled" if $verbose > 0
  end

  def move_daily_ref_to_daily
    # Moves items in daily notes with a >date to that corresponding date.
    # Checks whether the note exists and if not, creates one first at top level.
    puts '  move_daily_ref_to_daily ...' if $verbose > 1
    # noteToAddTo = nil
    n = -1
    moved = 0
    while n < @line_count
      n += 1
      line = @lines[n]
      # only continue with this line if has a >date mention
      next unless line =~ /#{RE_DUE_DATE}/

      # the following regex matches returns an array with one item, so make a string (by join)
      # NOTE: the '+?' gets minimum number of chars, to avoid grabbing contents of several [[notes]] in the same line
      yyyy_mm_dd = ''
      line.scan(/>(\d{4}-\d{2}-\d{2})/) { |m| yyyy_mm_dd = m.join }
      puts "  - found calendar link >#{yyyy_mm_dd} in notes on line #{n + 1} of #{@line_count}" if $verbose > 0
      yyyymmdd = "#{yyyy_mm_dd[0..3]}#{yyyy_mm_dd[5..6]}#{yyyy_mm_dd[8..9]}"

      # Find the existing daily note to add to, or read in, or create
      noteToAddTo = find_or_create_daily_note(yyyymmdd)
      lines_to_output = ''

      # Remove the >date text by finding string points
      label_start = line.index('>') - 1 # remove space before it as well. TODO: could be several > so find the right one
      label_end = label_start + 12
      # also chomp off last character of line (newline)
      line = "#{line[0..label_start]}#{line[label_end..-2]}"

      is_header = line =~ /^#+\s+.*/ ? true : false

      if !is_header
        # If no due date is specified in rest of the line, add date from the title of the calendar file it came from
        if line !~ /#{RE_DUE_DATE}/
          cal_date = "#{@title[0..3]}-#{@title[4..5]}-#{@title[6..7]}"
          puts "    - '>#{cal_date}' to add from #{@title}" if $verbose > 1
          lines_to_output = line + " <#{cal_date}\n"
        else
          lines_to_output = line
        end
        # Work out indent level of current line
        line_indent = ''
        line.scan(/^(\s*)\*/) { |m| line_indent = m.join }
        puts "    - starting line analysis at line #{n + 1} of #{@line_count} (indent #{line_indent.length})" if $verbose > 1

        # Remove this line from the calendar note
        @lines.delete_at(n)
        @line_count -= 1
        moved += 1

        # We also want to take any following indented lines
        # So incrementally add lines until we find ones at the same or lower level of indent
        while n < @line_count
          line_to_check = @lines[n]
          # What's the indent of this line?
          line_to_check_indent = ''
          line_to_check.scan(/^(\s*)\S/) { |m| line_to_check_indent = m.join }
          puts "      - for '#{line_to_check.chomp}' (indent #{line_to_check_indent.length})" if $verbose > 1
          break if line_indent.length >= line_to_check_indent.length

          lines_to_output += line_to_check
          # Remove this line from the calendar note
          @lines.delete_at(n)
          @line_count -= 1
          moved += 1
        end
      else
        # This is a header line ...
        # We want to take any following lines up to the next blank line or same-level header.
        # So incrementally add lines until we find that break.
        header_marker = ''
        line.scan(/^(#+)\s/) { |m| header_marker = m.join }
        lines_to_output = line + "\n"
        @lines.delete_at(n)
        @line_count -= 1
        moved += 1
        puts "  - starting header analysis at line #{n + 1}" if $verbose > 1

        while n < @line_count
          line_to_check = @lines[n]
          puts "    - l_t_o checking '#{line_to_check}'" if $verbose > 1
          break if (line_to_check =~ /^\s*$/) || (line_to_check =~ /^#{header_marker}\s/)

          lines_to_output += line_to_check
          # Remove this line from the calendar note
          puts "    - @line_count now #{@line_count}" if $verbose > 1
          @lines.delete_at(n)
          @line_count -= 1
          moved += 1
        end
      end

      # insert updated line(s) in the daily note file in section DAILY_TASKS_SECTION_NAME (or after header if blank)
      $allNotes[noteToAddTo].append_line_to_section(lines_to_output, DAILY_TASKS_SECTION_NAME)

      # write the note file out
      $allNotes[noteToAddTo].rewrite_file
    end
    return unless moved.positive?

    @is_updated = true
    puts "  - moved #{moved} lines to daily notes" if $verbose > 0
  end

  def move_daily_ref_to_notes
    # Move items in daily note with a [[note link]] to that note (inserting after header).
    # Checks whether the note exists and if not, creates one first at top level.

    puts '  move_daily_ref_to_notes ...' if $verbose > 1
    note_name = nil
    n = 0
    moved = 0
    while n < @line_count
      line = @lines[n]
      # find lines with [[note title]] mentions
      if line !~ /#{RE_NOTE_LINK}/
        # this line doesn't match, so break out of loop and go to look at next line
        n += 1
        next
      end

      is_header = line =~ /^#+\s+.*/ ? true : false

      # the following regex matches returns an array with one item, so make a string (by join)
      # NOTE: this '+?' gets minimum number of chars, to avoid grabbing contents of several [[notes]] in the same line
      if line =~ /#{RE_NOTE_LINK}/
        line.scan(/#{RE_NOTE_LINK_CAPTURE}/) { |m| note_name = m.join }
        puts "  - found note link [[#{note_name}]] in header on line #{n + 1} of #{@line_count}" if is_header && ($verbose > 0)
        puts "  - found note link [[#{note_name}]] in notes on line #{n + 1} of #{@line_count}" if !is_header && ($verbose > 0)
      end

      noteToAddTo = find_or_create_note(note_name)
      lines_to_output = ''

      # Remove the [[name]] text by finding string points
      label_start = line.index('[[') - 2 # remove space before it as well
      label_end = line.index(']]') + 2
      # also chomp off last character of line (newline)
      line = "#{line[0..label_start]}#{line[label_end..-2]}"

      if is_header
        # This is a header line.
        # We want to take any following lines up to the next blank line or same-level header.
        # So incrementally add lines until we find that break.
        header_marker = ''
        line.scan(/^(#+)\s/) { |m| header_marker = m.join }
        lines_to_output = "#{line}\n"
        @lines.delete_at(n)
        @line_count -= 1
        moved += 1
        puts "  - starting header analysis at line #{n + 1}" if $verbose > 1

        while n < @line_count
          line_to_check = @lines[n]
          puts "    - l_t_o checking '#{line_to_check}'" if $verbose > 1
          break if (line_to_check =~ /^\s*$/) || (line_to_check =~ /^#{header_marker}\s/)

          lines_to_output += line_to_check
          # Remove this line from the calendar note
          puts "    - @line_count now #{@line_count}" if $verbose > 1
          @lines.delete_at(n)
          @line_count -= 1
          moved += 1
        end
      else
        # This is not a header line.
        # If no due date is specified in rest of the line, add date from the title of the calendar file it came from
        if line !~ /#{RE_DUE_DATE}/
          cal_date = "#{@title[0..3]}-#{@title[4..5]}-#{@title[6..7]}"
          puts "    - '#{cal_date}' to add from #{@title}" if $verbose > 1
          lines_to_output = line + " >#{cal_date}\n"
        else
          lines_to_output = line
        end
        # Work out indent level of current line
        line_indent = ''
        line.scan(/^(\s*)\*/) { |m| line_indent = m.join }
        puts "  - starting line analysis at line #{n + 1} of #{@line_count} with indent '#{line_indent}' (#{line_indent.length})" if $verbose > 1
        # Remove this line from the calendar note
        @lines.delete_at(n)
        @line_count -= 1
        moved += 1

        # We also want to take any following indented lines
        # So incrementally add lines until we find ones at the same or lower level of indent
        while n < @line_count
          line_to_check = @lines[n]
          # What's the indent of this line?
          line_to_check_indent = ''
          line_to_check.scan(/^(\s*)\S/) { |m| line_to_check_indent = m.join }
          puts "    - for '#{line_to_check.chomp}' indent='#{line_to_check_indent}' (#{line_to_check_indent.length})" if $verbose > 1
          break if line_indent.length >= line_to_check_indent.length

          lines_to_output += line_to_check
          # Remove this line from the calendar note
          @lines.delete_at(n)
          @line_count -= 1
          moved += 1
        end
      end

      # insert updated line(s) after header lines in the note file
      $allNotes[noteToAddTo].append_line_to_section(lines_to_output, '')

      # write the note file out
      $allNotes[noteToAddTo].rewrite_file
    end
    return unless moved.positive?

    @is_updated = true
    puts "  - moved #{moved} lines to notes" if $verbose > 0
  end

  def archive_lines
    # Shuffle @done and cancelled lines to relevant sections at end of the file
    # TODO: doesn't yet deal with notes with subheads in them
    puts '  archive_lines ...' if $verbose > 1
    doneToMove = [] # NB: zero-based
    doneToMoveLength = [] # NB: zero-based
    cancToMove = [] # NB: zero-based
    cancToMoveLength = [] # NB: zero-based
    c = 0

    # Go through all lines between metadata and ## Done section
    # start, noting completed tasks
    n = 1
    searchLineLimit = @done_header.positive? ? @done_header : @line_count
    while n < searchLineLimit
      n += 1
      line = @lines[n]
      next unless line =~ /\*\s+\[x\]/ # TODO: change for different task markers

      # save this line number
      doneToMove.push(n)
      # and look ahead to see how many lines to move -- all until blank or starting # or *
      linesToMove = 0
      while n < @line_count
        break if (@lines[n + 1] =~ /^(#+\s+|\*\s+)/) || (@lines[n + 1] =~ /^\s*$/) # TODO: change for different task markers

        linesToMove += 1
        n += 1
      end
      # save this length
      doneToMoveLength.push(linesToMove)
    end
    puts "    doneToMove:  #{doneToMove} / #{doneToMoveLength}" if $verbose > 1

    # Do some done line shuffling, is there's anything to do
    unless doneToMove.empty?
      # If we haven't already got a Done section, make one
      if @done_header.zero?
        @lines.push('')
        @lines.push('## Done')
        @line_count += 2
        @done_header = @line_count
      end

      # Copy the relevant lines
      doneInsertionLine = @cancelled_header != 0 ? @cancelled_header : @line_count
      c = 0
      doneToMove.each do |nn|
        linesToMove = doneToMoveLength[c]
        puts "      Copying lines #{nn}-#{nn + linesToMove} to insert at #{doneInsertionLine}" if $verbose > 1
        (nn..(nn + linesToMove)).each do |i|
          @lines.insert(doneInsertionLine, @lines[i])
          @line_count += 1
          doneInsertionLine += 1
        end
        c += 1
      end

      # Now delete the original items (in reverse order to preserve numbering)
      c = doneToMoveLength.size - 1
      doneToMove.reverse.each do |nn|
        linesToMove = doneToMoveLength[c]
        puts "      Deleting lines #{nn}-#{nn + linesToMove}" if $verbose > 1
        (nn + linesToMove).downto(n) do |i|
          @lines.delete_at(i)
          @line_count -= 1
          doneInsertionLine -= 1
          @done_header -= 1
        end
        c -= 1
      end
    end

    # Go through all lines between metadata and ## Done section
    # start, noting cancelled line numbers
    n = 0
    searchLineLimit = @done_header.positive? ? @done_header : @line_count
    while n < searchLineLimit
      n += 1
      line = @lines[n]
      next unless line =~ /\*\s*\[-\]/ # TODO: change for different task markers

      # save this line number
      cancToMove.push(n)
      # and look ahead to see how many lines to move -- all until blank or starting # or *
      linesToMove = 0
      while n < @line_count
        linesToMove += 1
        break if (@lines[n + 1] =~ /^(#+\s+|\*\s+)/) || (@lines[n + 1] =~ /^\s*$/) # TODO: change for different task markers

        n += 1
      end
      # save this length
      cancToMoveLength.push(linesToMove)
    end
    puts "    cancToMove: #{cancToMove} / #{cancToMoveLength}" if $verbose > 1

    # Do some cancelled line shuffling, is there's anything to do
    return if cancToMove.empty?

    # If we haven't already got a Cancelled section, make one
    if @cancHeader.zero?
      @lines.push('')
      @lines.push('## Cancelled')
      @line_count += 2
      @cancHeader = @line_count
    end

    # Copy the relevant lines
    cancelledInsertionLine = @line_count
    c = 0
    cancToMove.each do |nn|
      linesToMove = cancToMoveLength[c]
      puts "      Copying lines #{nn}-#{nn + linesToMove} to insert at #{cancelledInsertionLine}" if $verbose > 1
      (nn..(nn + linesToMove)).each do |i|
        @lines.insert(cancelledInsertionLine, @lines[i])
        @line_count += 1
        cancelledInsertionLine += 1
      end
      c += 1
    end

    # Now delete the original items (in reverse order to preserve numbering)
    c = doneToMoveLength.size - 1
    cancToMove.reverse.each do |nn|
      linesToMove = doneToMoveLength[c]
      puts "      Deleting lines #{nn}-#{nn + linesToMove}" if $verbose > 1
      (nn + linesToMove).downto(n) do |i|
        puts "        Deleting line #{i} ..." if $verbose > 1
        @lines.delete_at(i)
        @line_count -= 1
        @done_header -= 1
      end
    end

    # Finally mark note as updated
    @is_updated = true
  end

  def use_template_dates
    # Take template dates and turn into real dates

    puts '  use_template_dates ...' if $verbose > 1
    date_string = ''
    current_target_date = ''
    calc_date = ''
    last_was_template = false
    n = 0
    # Go through each line in the active part of the file
    while n < (@done_header.positive? ? @done_header : @line_count)
      line = @lines[n]
      date_string = ''
      # look for base date, of form YYYY-MM-DD and variations and whatever RE_DATE_FORMAT_CUSTOM gives
      if line =~ /^#+\s/
        # clear previous settings when we get to a new heading
        current_target_date = ''
        last_was_template = false
      end

      # Try matching for the standard YYYY-MM-DD date pattern
      # (though check it's not got various characters before it, to defeat common usage in middle of things like URLs)
      line.scan(/[^\d(<>\/-](#{RE_DATE})/) { |m| date_string = m.join }
      if date_string != ''
        # We have a date string to use for any offsets in the following section
        current_target_date = date_string
        puts "    - Found CTD #{current_target_date}" if $verbose > 1
      else
        # Try matching for the custom date pattern, configured at the top
        # (though check it's not got various characters before it, to defeat common usage in middle of things like URLs)
        line.scan(/[^\d(<>\/-](#{RE_DATE_FORMAT_CUSTOM})/) { |m| date_string = m.join }
        if date_string != ''
          # We have a date string to use for any offsets in the following section
          current_target_date = date_string
          puts "    - Found CTD #{current_target_date}" if $verbose > 1
        end
      end
      if line =~ /#template/
        # We have a #template tag so ignore any offsets in the following section
        last_was_template = true
        puts "    . Found #template in '#{line.chomp}'" if $verbose > 1
      end

      # ignore line if we're in a template section (last_was_template is true)
      unless last_was_template
        # find lines with {+3d} or {-4w} etc. plus {0d} special case
        # NB: this only deals with the first on any line; it doesn't make sense to have more than one.
        date_offset_string = ''
        if line =~ /\{#{RE_DATE_INTERVAL}\}/
          puts "    - Found line '#{line.chomp}'" if $verbose > 1
          line.scan(/\{(#{RE_DATE_INTERVAL_CAPTURE})\}/) { |m| date_offset_string = m.join }
          if date_offset_string != ''
            puts "      - Found DOS #{date_offset_string}' and last_was_template=#{last_was_template}" if $verbose > 1
            if current_target_date != ''
              begin
                calc_date = calc_offset_date(Date.parse(current_target_date), date_offset_string)
              rescue StandardError => e
                puts "      Error #{e.exception.message} while parsing date '#{current_target_date}' for #{date_offset_string}".colorize(WarningColour)
              end
              # Remove the offset text (e.g. {-3d}) by finding string points
              label_start = line.index('{')
              label_end = line.index('}')
              # Create new version with inserted date
              line = "#{line[0..label_start - 1]}>#{calc_date}#{line[label_end + 1..-2]}" # also chomp off last character (newline)
              # then add the new date
              # line += ">#{calc_date}"
              @lines[n] = line
              puts "      - In line labels runs #{label_start}-#{label_end} --> '#{line.chomp}'" if $verbose > 1
              @is_updated = true
            elsif $verbose > 0
              puts "    Warning: have an offset date, but no current_target_date before line '#{line.chomp}'".colorize(WarningColour)
            end
          end
        end
      end
      n += 1
    end
  end

  def process_repeats_and_done
    # Process any completed (or cancelled) tasks with my extended @repeat(..) tags,
    # and also remove the HH:MM portion of any @done(...) tasks.
    #
    # When interval is of the form +2w it will duplicate the task for 2 weeks
    # after the date is was completed.
    # When interval is of the form 2w it will duplicate the task for 2 weeks
    # after the date the task was last due. If this can't be determined,
    # then default to the first option.
    # Valid intervals are [0-9][bdwmqy].
    # To work it relies on finding @done(YYYY-MM-DD HH:MM) tags that haven't yet been
    # shortened to @done(YYYY-MM-DD).
    # It includes cancelled tasks as well; to remove a repeat entirely, remoce
    # the @repeat tag from the task in NotePlan.
    puts '  process_repeats_and_done ...' if $verbose > 1
    n = cleaned = 0
    # Go through each line in the active part of the file
    while n < (@done_header != 0 ? @done_header : @line_count)
      line = @lines[n]
      updated_line = ''
      completed_date = ''
      # find lines with date-time to shorten, and capture date part of it
      # i.e. @done(YYYY-MM-DD HH:MM[AM|PM])
      if line =~ /@done\(#{RE_DATE_TIME}\)/
        # get completed date
        line.scan(/\((\d{4}-\d{2}-\d{2}) \d{2}:\d{2}(?:.(?:AM|PM))?\)/) { |m| completed_date = m.join }
        updated_line = line.gsub(/\(#{RE_DATE_TIME}\)/, "(#{completed_date})")
        @lines[n] = updated_line
        cleaned += 1
        @is_updated = true
        # Test if this is one of my special extended repeats (i.e. no / in it)
        if updated_line =~ /@repeat\([^\/]*\)/
          # get repeat to apply
          date_interval_string = ''
          updated_line.scan(/@repeat\((.*?)\)/) { |mm| date_interval_string = mm.join }
          if date_interval_string[0] == '+'
            # New repeat date = completed date + interval
            date_interval_string = date_interval_string[1..date_interval_string.length]
            new_repeat_date = calc_offset_date(Date.parse(completed_date), date_interval_string)
            puts "      Adding from completed date --> #{new_repeat_date}" if $verbose > 1
          else
            # New repeat date = due date + interval
            # look for the due date (>YYYY-MM-DD)
            due_date = ''
            if updated_line =~ /#{RE_DUE_DATE}/
              updated_line.scan(/#{RE_DUE_DATE_CAPTURE}/) { |m| due_date = m.join }
              # need to remove the old due date (and preceding whitespace)
              updated_line = updated_line.gsub(/\s*#{RE_DUE_DATE}/, '')
            else
              # but if there is no due date then treat that as today
              due_date = completed_date
            end
            new_repeat_date = calc_offset_date(Date.parse(due_date), date_interval_string)
            puts "      Adding from due date --> #{new_repeat_date}" if $verbose > 1
          end

          # Create new repeat line:
          updated_line_without_done = updated_line.chomp
          # Remove the @done text
          updated_line_without_done = updated_line_without_done.gsub(/@done\(.*\)/, '')
          # Replace the * [x] text with * [>]
          updated_line_without_done = updated_line_without_done.gsub(/\[x\]/, '[>]')
          # also remove multiple >dates that stack up on repeats
          updated_line_without_done = updated_line_without_done.gsub(/\s+#{RE_DUE_DATE}/, '')
          # finally remove any extra trailling whitespace
          updated_line_without_done.rstrip!
          outline = "#{updated_line_without_done} >#{new_repeat_date}"

          # Insert this new line after current line
          n += 1
          insert_new_line_at_line(outline, n)
        end
      end
      n += 1
    end
  end

  def remove_empty_header_sections
    # go backwards through the active part of the note, deleting any sections without content
    puts '  remove_empty_header_sections ...' if $verbose > 1
    cleaned = 0
    n = @done_header != 0 ? @done_header - 1 : @line_count - 1

    # Go through each line in the file
    later_header_level = this_header_level = 0
    at_eof = 1
    while n.positive? || n.zero?
      line = @lines[n]
      if line =~ /^#+\s\w/
        # this is a markdown header line; work out what level it is
        line.scan(/^(#+)\s/) { |m| this_header_level = m[0].length }
        # puts "    - #{later_header_level} / #{this_header_level}" if $verbose > 1
        # if later header is same or higher level (fewer #s) as this,
        # then we can delete this line
        if later_header_level == this_header_level || at_eof == 1
          puts "    - Removing empty header line #{n} '#{line.chomp}'" if $verbose > 1
          @lines.delete_at(n)
          cleaned += 1
          @line_count -= 1
          @is_updated = true
        end
        later_header_level = this_header_level
      elsif line !~ /^\s*$/
        # this has content but is not a header line
        later_header_level = 0
        at_eof = 0
      end
      n -= 1
    end
    return unless cleaned.positive?

    @is_updated = true
    # @line_count = @lines.size
    puts "  - removed #{cleaned} lines of empty section(s)" if $verbose > 1
  end

  def remove_multiple_empty_lines
    # go backwards through the active parts of the note, deleting any blanks at the end
    puts '  remove_multiple_empty_lines ...' if $verbose > 1
    cleaned = 0
    n = (@done_header != 0 ? @done_header - 1 : @line_count - 1)
    last_was_empty = false
    while n.positive?
      line_to_test = @lines[n]
      if line_to_test =~ /^\s*$/ && last_was_empty
        @lines.delete_at(n)
        cleaned += 1
      end
      last_was_empty = line_to_test =~ /^\s*$/ ? true : false
      n -= 1
    end
    return unless cleaned.positive?

    @is_updated = true
    @line_count = @lines.size
    puts "  - removed #{cleaned} empty lines" if $verbose > 1
  end

  def rewrite_file
    # write out this update file
    puts '  > writing updated version of ' + @filename.to_s.bold unless $quiet
    # open file and write all the lines out
    filepath = if @is_calendar
                 "#{NP_CALENDAR_DIR}/#{@filename}"
               else
                 "#{NP_NOTES_DIR}/#{@filename}"
               end
    begin
      File.open(filepath, 'w') do |f|
        @lines.each do |line|
          f.puts line
        end
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when re-writing note file #{filepath}".colorize(WarningColour)
    end
  end
end

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "NotePlan tools v#{VERSION}\nDetails at https://github.com/jgclark/NotePlan-tools/\nUsage: npTools.rb [options] [file-pattern]"
  opts.separator ''
  options[:archive] = 0 # default off at the moment as feature isn't complete
  options[:move_daily_to_note] = 1
  options[:move_on_dailies] = 0
  options[:remove_rescheduled] = 1
  options[:skipfile] = ''
  options[:skiptoday] = false
  options[:quiet] = false
  options[:verbose] = 0
  opts.on('-a', '--noarchive', "Don't archive completed tasks into the ## Done section. Turned on by default at the moment.") do
    options[:archive] = 0
  end
  opts.on('-c', '--changes HOURS', Integer, "How many hours to look back to find note changes to process") do |n|
    hours_to_process = n
  end
  opts.on('-f', '--skipfile=TITLE[,TITLE2,etc]', Array, "Don't process specific file(s)") do |skipfile|
    options[:skipfile] = skipfile
  end
  opts.on('-h', '--help', 'Show this help summary') do
    puts opts
    exit
  end
  opts.on('-i', '--skiptoday', "Don't touch today's daily note file") do
    options[:skiptoday] = true
  end
  opts.on('-m', '--moveon', "Move Daily items with >date to that Daily note") do
    options[:move_on_dailies] = 1
  end
  opts.on('-n', '--nomove', "Don't move Daily items with [[Note]] reference to that Note") do
    options[:move_daily_to_note] = 0
  end
  opts.on('-q', '--quiet', 'Suppress all output, apart from error messages. Overrides -v or -w.') do
    options[:quiet] = true
  end
  opts.on('-s', '--keepscheduled', 'Keep the re-scheduled (>) dates of completed tasks') do
    options[:remove_rescheduled] = 0
  end
  opts.on('-v', '--verbose', 'Show information as I work') do
    options[:verbose] = 1
  end
  opts.on('-w', '--moreverbose', 'Show more information as I work') do
    options[:verbose] = 2
  end
end
opt_parser.parse! # parse out options, leaving file patterns to process
$quiet = options[:quiet]
$verbose = $quiet ? 0 : options[:verbose] # if quiet, then verbose has to  be 0
$archive = options[:archive]
$remove_rescheduled = options[:remove_rescheduled]

#------------------------------
# Test for append_line_to_section
# Dir.chdir(NP_CALENDAR_DIR)
# this_note = NPFile.new("20210225.md")
# # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
# this_note.append_line_to_section("> test line to add 1\n- test line to add 2", "")
# this_note.append_line_to_section("> test line to add 3\n- test line to add 4", "### Tasks")
# this_note.append_line_to_section("> test line to add 5\n- test line to add 6", "### Tasks")
# this_note.rewrite_file
# exit

#--------------------------------------------------------------------------------------
# Start by reading all Notes files in
# (This is needed to have a list of all note titles that we might be moving tasks to.)

# NOTE: Would like to just work this out on the fly, but there's no way at the moment of
# looking up note titles from filenames, without reading them all in :-(

begin
  Dir.chdir(NP_NOTES_DIR)
  Dir.glob(['{[!@]**/*,*}.txt', '{[!@]**/*,*}.md']).each do |this_file|
    next if File.zero?(this_file) # ignore if this file is empty

    $allNotes << NPFile.new(this_file)
  end
rescue StandardError => e
  puts "ERROR: #{e.exception.message} when reading in all notes files".colorize(WarningColour)
end
puts "Read in all Note files: #{$npfile_count} found\n" if $verbose > 0

if ARGV.count.positive?
  # We have a file pattern given, so find that (starting in the notes directory), and use it
  puts "Starting npTools at #{time_now_fmttd} for files matching pattern(s) #{ARGV}." unless $quiet
  begin
    ARGV.each do |pattern|
      # if pattern has a '.' in it assume it is a full filename ...
      # ... otherwise treat as close to a regex term as possible with Dir.glob
      glob_pattern = pattern =~ /\./ ? pattern : '[!@]**/*' + pattern + '*.{md,txt}'
      puts "  Looking for note filenames matching glob_pattern #{glob_pattern}:" if $verbose > 0
      Dir.glob(glob_pattern).each do |this_file|
        puts "  - #{this_file}" if $verbose > 0
        # Note has already been read in; so now just find which one to point to, by matching filename
        $allNotes.each do |this_note|
          # copy the $allNotes item into $notes array
          $notes << this_note if this_note.filename == this_file
        end
        next if File.zero?(this_file) # ignore if this file is empty

        $notes << NPFile.new(this_file)
      end
    end

    # Now look for matches in Daily/Calendar files
    Dir.chdir(NP_CALENDAR_DIR)
    ARGV.each do |pattern|
      # if pattern has a '.' in it assume it is a full filename ...
      # ... otherwise treat as close to a regex term as possible with Dir.glob
      glob_pattern = pattern =~ /\./ ? pattern : '*' + pattern + '*.{md,txt}'
      puts "  Looking for daily note filenames matching glob_pattern #{glob_pattern}:" if $verbose > 0
      Dir.glob(glob_pattern).each do |this_file|
        puts "  - #{this_file}" if $verbose > 0
        # read in file unless this file is empty
        next if File.zero?(this_file)

        this_note = NPFile.new(this_file)
        $allNotes << this_note
        # copy the $allNotes item into $notes array
        $notes << this_note
      end
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when reading in files matching pattern #{pattern}".colorize(WarningColour)
  end

else
  # Read metadata for all Note files, and find those altered in the last 24 hours
  puts "Starting npTools at #{time_now_fmttd} for all NP files altered in last #{hours_to_process} hours." unless $quiet
  begin
    $allNotes.each do |this_note|
      next unless this_note.modified_time > (time_now - hours_to_process * 60 * 60)

      # copy this relevant $allNotes item into $notes array to process
      $notes << this_note
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when finding recently changed files".colorize(WarningColour)
  end

  # Also read metadata for all Daily files, and find those altered in the last 24 hours
  begin
    Dir.chdir(NP_CALENDAR_DIR)
    Dir.glob(['{[!@]**/*,*}.{txt,md}']).each do |this_file|
      puts "    Checking daily file #{this_file}, updated #{File.mtime(this_file)}, size #{File.size(this_file)}" if $verbose > 1
      next if File.zero?(this_file) # ignore if this file is empty
      # if modified time (mtime) in the last 24 hours
      next unless File.mtime(this_file) > (time_now - hours_to_process * 60 * 60)

      this_note = NPFile.new(this_file)
      $allNotes << this_note
      # copy the $allNotes item into $notes array
      $notes << this_note
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when finding recently changed files".colorize(WarningColour)
  end
end

#--------------------------------------------------------------------------------------
if $notes.count.positive? # if we have some files to work on ...
  puts "\nProcessing #{$notes.count} files:" if $verbose > 0
  # For each NP file to process, do the following:
  $notes.sort! { |a, b| a.title <=> b.title }
  $notes.each do |note|
    if note.is_today && options[:skiptoday]
      puts '(Skipping ' + note.title.to_s.bold + ' due to --skiptoday option)' if $verbose > 0
      next
    end
    if options[:skipfile].include? note.title
      puts '(Skipping ' + note.title.to_s.bold + ' due to --skipfile option)' if $verbose > 0
      next
    end
    puts " Processing file id #{note.id}: " + note.title.to_s.bold if $verbose > 0
    note.clear_empty_tasks_or_headers
    note.remove_empty_header_sections
    note.remove_unwanted_tags_dates
    note.remove_rescheduled if note.is_calendar
    note.process_repeats_and_done
    note.remove_multiple_empty_lines
    note.move_daily_ref_to_daily if note.is_calendar && options[:move_on_dailies] == 1
    note.move_daily_ref_to_notes if note.is_calendar && options[:move_daily_to_note] == 1
    note.use_template_dates # unless note.is_calendar
    note.create_events_from_timeblocks
    note.archive_lines if $archive == 1 # not ready yet
    # If there have been changes, write out the file
    note.rewrite_file if note.is_updated
  end
else
  puts "  Warning: No matching files found.\n".colorize(WarningColour)
end
