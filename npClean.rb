#!/usr/bin/ruby
#-------------------------------------------------------------------------------
# NotePlan note and calendar file cleanser
# by Jonathan Clark, v1.2.7, 9.6.2020
#-------------------------------------------------------------------------------
# See README.md file for details, how to run and configuration.
#-------------------------------------------------------------------------------
# FIXME:
# * [x] (issue #3) template mechanism failing for {0d}
# * [x] (issue #4) include date when moving from calendar to note (move_calendar_to_notes)
# * [x] fix extra space left after removing [[note name]]
# * [x] fix empty line being left when moving a calendar to note
# TODO:
# * [x] (issue #2) add processing of repeating tasks (my method, not the NP one)
# * [ ] (issue #5) also move sub-tasks and comments when moving items to a [[Note]],
#       like Archiving does (from v2.4.4).
# * [x] (issue #6) also move headings with a [[Note]] marker and all its child tasks, notes and comments
# * [ ] (issue #9) cope with moving subheads to archive as well - or is the better
#       archiving now introduced in v2.4.4 enough?
# * [x] issue 1: add ability to find and clean notes in folders (from NP v2.5), excluding @Archive and @Trash folders
# * [x] add command-line parameters, particularly for verbose level
# * [x] update {-2d} etc. dates according to previous due date
# * [x] add colouration of output (https://github.com/fazibear/colorize)
# * [x] change to move closed and open tasks with [[Note]] mentions
#-------------------------------------------------------------------------------

require 'date'
require 'time'
require 'etc' # for login lookup
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

# Setting variables to tweak
USERNAME = 'jonathan'.freeze # change me
NUM_HEADER_LINES = 3 # suits my use, but probably wants to be 1 for most people
STORAGE_TYPE = 'iCloud'.freeze # or Dropbox
TAGS_TO_REMOVE = ['#waiting', '#high'].freeze # simple array of strings
DATE_FORMAT = '%d.%m.%y'.freeze
DATE_TIME_FORMAT = '%e %b %Y %H:%M'.freeze

# Other Constants
TodaysDate = Date.today # can't work out why this needs to be a 'constant' to work -- something about visibility, I suppose
User = Etc.getlogin # for debugging when running by launchctl
NP_BASE_DIR = if STORAGE_TYPE == 'iCloud'
                "/Users/#{USERNAME}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents" # for iCloud storage
              else
                "/Users/#{USERNAME}/Dropbox/Apps/NotePlan/Documents" # for Dropbox storage
              end
NP_NOTES_DIR = "#{NP_BASE_DIR}/Notes".freeze
NP_CALENDAR_DIR = "#{NP_BASE_DIR}/Calendar".freeze

# Other variables
time_now = Time.now
time_now_fmttd = time_now.strftime(DATE_TIME_FORMAT)

# Colours, using the colorization gem
# to show some possible combinations, run  String.color_samples
# to show list of possible modes, run   puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
ActiveColour = :light_yellow
WarningColour = :light_red
InstructionColour = :light_cyan

# Variables that need to be globally available
$verbose = 0
$allNotes = []  # to hold all note objects
$notes    = []  # to hold all relevant note objects

#-------------------------------------------------------------------------
# Class definition: NPNote (here covers Note *and* Calendar files)
#-------------------------------------------------------------------------
class NPNote
  # Define the attributes that need to be visible outside the class instances
  attr_reader :id
  attr_reader :title
  attr_reader :cancelled_header
  attr_reader :done_header
  attr_reader :is_calendar
  attr_reader :is_updated
  attr_reader :filename

  def initialize(this_file, id)
    # initialise instance variables (that persist with the class instance)
    @filename = this_file
    @id = id
    @title = nil
    @lines = []
    @lineCount = 0
    @cancelled_header = 0
    @done_header = 0
    @is_calendar = false
    @is_updated = false

    # initialise other variables (that don't need to persist with the class)
    n = 0

    # puts "initialising #{@filename} from #{Dir.pwd}"
    # Open file and read in all lines (finding any Done and Cancelled headers)
    # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
    f = File.open(@filename, 'r', encoding: 'utf-8')
    f.each_line do |line|
      @lines[n] = line
      @done_header = n  if line =~ /^## Done$/
      @cancelled_header = n if line =~ /^## Cancelled$/
      n -= 1 if line =~ /^\s*[\*\-]\s*$/ # i.e. remove lines with just a * or -
      n += 1
    end
    f.close
    @lineCount = @lines.size

    # Now make a title for this file:
    if @filename =~ /\d{8}\.txt/
      # for Calendar file, use the date from filename
      @title = @filename[0..7]
      @is_calendar = true
    else
      # otherwise use first line (but take off heading characters at the start and starting and ending whitespace)
      tempTitle = @lines[0].gsub(/^#+\s*/, '')
      @title = tempTitle.gsub(/\s+$/, '')
      @is_calendar = false
    end
  end

  def remove_empty_tasks
    # Clean up lines with just * or - in them
    puts '  remove_empty_tasks ...' if $verbose > 1
    n = cleaned = 0
    while n < @lineCount
      # blank any lines which just have a * or -
      if @lines[n] =~ /^\s*[\*\-]\s*$/
        @lines[n] = ''
        cleaned += 1
      end
      n += 1
    end
    return unless cleaned.positive?

    @is_updated = true
    puts "  - removed #{cleaned} emtpy lines" if $verbose > 0
  end

  def remove_tags_dates
    # remove unneeded tags or >dates from complete or cancelled tasks
    puts '  remove_tags_dates ...' if $verbose > 1
    n = cleaned = 0
    while n < @lineCount
      # remove any >YYYY-MM-DD on completed or cancelled tasks
      if (@lines[n] =~ /\s>\d{4}\-\d{2}\-\d{2}/) && (@lines[n] =~ /\[(x|-)\]/)
        @lines[n].gsub!(/\s>\d{4}\-\d{2}\-\d{2}/, '')
        cleaned += 1
      end

      # Remove any tags from the TagsToRemove list. Iterate over that array:
      TAGS_TO_REMOVE.each do |tag|
        if (@lines[n] =~ /#{tag}/) && (@lines[n] =~ /\[(x|-)\]/)
          @lines[n].gsub!(/ #{tag}/, '')
          cleaned += 1
        end
      end
      n += 1
    end
    return unless cleaned.positive?

    @is_updated = true
    puts "  - removed #{cleaned} tags/dates" if $verbose > 0
  end

  def insert_new_line(new_line, line_number)
    # Insert 'line' into position 'line_number'
    puts '  insert_new_line ...' if $verbose > 1
    n = @lineCount # start iterating from the end of the array
    while n >= line_number
      @lines[n + 1] = @lines[n]
      n -= 1
    end
    @lines[line_number] = new_line
    @lineCount += 1
  end

  def move_calendar_to_notes
    # Move tasks with a [[note link]] to that note (inserting after header)
    puts '  move_calendar_to_notes ...' if $verbose > 1
    noteName = noteToAddTo = nil
    n = 0
    moved = 0
    while n < @lineCount
      line = @lines[n]
      is_header = false
      # find todo or header lines with [[note title]] mentions
      if line !~ /^\s*\*.*\[\[.*\]\]/ && line !~ /^#+\s+.*\[\[.*\]\]/
        n += 1 # get ready to look at next line
        next
      end
      is_header = true if line =~ /^#+\s+.*\[\[.*\]\]/

      # the following regex matches returns an array with one item, so make a string (by join)
      # NB the '+?' gets minimum number of chars, to avoid grabbing contents of several [[notes]] in the same line
      # line.scan(/^\s*\*.*\[\[(.+?)\]\]/) { |m| noteName = m.join }  # why so specific?
      line.scan(/\[\[(.+?)\]\]/) { |m| noteName = m.join }
      puts "  - found note link [[#{noteName}]] in header on line #{n + 1} of #{@lineCount}" if is_header && ($verbose > 0)
      puts "  - found note link [[#{noteName}]] in task on line #{n + 1} of #{@lineCount}" if !is_header && ($verbose > 0)

      # find the note file to add to
      $allNotes.each do |nn|
        noteToAddTo = nn.id if nn.title == noteName
      end

      if noteToAddTo # if note is found
        lines_to_output = ''

        # Remove the [[name]] text by finding string points
        label_start = line.index('[[') - 2 # remove space before it as well
        label_end = line.index(']]') + 2
        line = "#{line[0..label_start]}#{line[label_end..-2]}" # also chomp off last character (newline)

        if !is_header
          # A todo line ...
          # If no due date is specified in rest of the todo, add date from the title of the calendar file it came from
          if line !~ />\d{4}\-\d{2}\-\d{2}/
            cal_date = "#{@title[0..3]}-#{@title[4..5]}-#{@title[6..7]}"
            puts "    - '#{cal_date}' to add from #{@title}" if $verbose > 1
            lines_to_output = line + " >#{cal_date}\n"
          else
            lines_to_output = line
          end
          # puts "    - '#{lines_to_output}' and now n=#{n + 1}" if $verbose > 1
          # Work out indent level of current line
          line_indent = ''
          line.scan(/^(\s*)\*/) { |m| line_indent = m.join }
          puts "  - starting task analysis at line #{n + 1} with indent '#{line_indent}' (#{line_indent.length})" if $verbose > 1
          # Remove this line from the calendar note
          @lines.delete_at(n)
          @lineCount -= 1
          moved += 1
          
          # We also want to take any following indented lines
          # So incrementally add lines until we find ones at the same or lower level of indent
          while n < @lineCount
            line_to_check = @lines[n]
            # What's the indent of this line?
            line_to_check_indent = ''
            line_to_check.scan(/^(\s*)\S/) { |m| line_to_check_indent = m.join }
            puts "    - for '#{line_to_check.chomp}' indent='#{line_to_check_indent}' (#{line_to_check_indent.length})" if $verbose > 1
            break if line_indent.length >= line_to_check_indent.length

            lines_to_output += line_to_check
            # Remove this line from the calendar note
            @lines.delete_at(n)
            @lineCount -= 1
            moved += 1
          end
        else
          # A header line ...
          # We want to take any following lines up to the next blank line or same-level header.
          # So incrementally add lines until we find that break.
          header_marker = ''
          line.scan(/^(#+)\s/) { |m| header_marker = m.join }
          lines_to_output = line + "\n"
          @lines.delete_at(n)
          @lineCount -= 1
          moved += 1
          puts "  - starting header analysis at line #{n + 1}" if $verbose > 1
          # n += 1
          while n < @lineCount
            line_to_check = @lines[n]
            break if (line_to_check =~ /^$/) || (line_to_check =~ /^#{header_marker}\s/)

            lines_to_output += line_to_check
            # Remove this line from the calendar note
            @lines.delete_at(n)
            @lineCount -= 1
            moved += 1
          end
        end

        # insert updated line(s) after header lines in the note file
        $allNotes[noteToAddTo].insert_new_line(lines_to_output, NUM_HEADER_LINES)

        # write the note file out
        $allNotes[noteToAddTo].rewrite_file
      else # if note not found
        puts "   Warning: can't find matching note for [[#{noteName}]]. Ignoring".colorize(WarningColour)
        n += 1
      end
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
    searchLineLimit = @done_header.positive? ? @done_header : @lineCount
    while n < searchLineLimit
      n += 1
      line = @lines[n]
      next unless line =~ /\*\s+\[x\]/

      # save this line number
      doneToMove.push(n)
      # and look ahead to see how many lines to move -- all until blank or starting # or *
      linesToMove = 0
      while n < @lineCount
        break if (@lines[n + 1] =~ /^(#+\s+|\*\s+)/) || (@lines[n + 1] =~ /^$/)

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
        @lineCount += 2
        @done_header = @lineCount
      end

      # Copy the relevant lines
      doneInsertionLine = @cancelled_header != 0 ? @cancelled_header : @lineCount
      c = 0
      doneToMove.each do |nn|
        linesToMove = doneToMoveLength[c]
        puts "      Copying lines #{nn}-#{nn + linesToMove} to insert at #{doneInsertionLine}" if $verbose > 1
        (nn..(nn + linesToMove)).each do |i|
          @lines.insert(doneInsertionLine, @lines[i])
          @lineCount += 1
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
          @lineCount -= 1
          doneInsertionLine -= 1
          @done_header -= 1
        end
        c -= 1
      end
    end

    # Go through all lines between metadata and ## Done section
    # start, noting cancelled line numbers
    n = 0
    searchLineLimit = @done_header.positive? ? @done_header : @lineCount
    while n < searchLineLimit
      n += 1
      line = @lines[n]
      next unless line =~ /\*\s*\[\-\]/

      # save this line number
      cancToMove.push(n)
      # and look ahead to see how many lines to move -- all until blank or starting # or *
      linesToMove = 0
      while n < @lineCount
        linesToMove += 1
        break if (@lines[n + 1] =~ /^(#+\s+|\*\s+)/) || (@lines[n + 1] =~ /^$/)

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
      @lineCount += 2
      @cancHeader = @lineCount
    end

    # Copy the relevant lines
    cancelledInsertionLine = @lineCount
    c = 0
    cancToMove.each do |nn|
      linesToMove = cancToMoveLength[c]
      puts "      Copying lines #{nn}-#{nn + linesToMove} to insert at #{cancelledInsertionLine}" if $verbose > 1
      (nn..(nn + linesToMove)).each do |i|
        @lines.insert(cancelledInsertionLine, @lines[i])
        @lineCount += 1
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
        @lineCount -= 1
        @done_header -= 1
      end
    end

    # Finally mark note as updated
    @is_updated = true
  end

  def calc_offset_date(old_date, interval)
    # Calculate next review date, assuming:
    # - old_date is type
    # - interval is string of form nn[dwmq]
    # puts "    c_o_d: old #{old_date} interval #{interval} ..."
    days_to_add = 0
    unit = interval[-1]
    num = interval.chop.to_i
    case unit
    when 'd'
      days_to_add = num
    when 'w'
      days_to_add = num * 7
    when 'm'
      days_to_add = num * 30
    when 'q'
      days_to_add = num * 90
    else
      puts "    Error in calc_offset_date from #{old_date} by #{interval}".colorize(WarningColour)
    end
    puts "    c_o_d: with #{old_date} interval #{interval} found #{days_to_add} days_to_add" if $verbose > 1
    newDate = old_date + days_to_add
    newDate
  end

  def use_template_dates
    # Take template dates and turn into real dates
    puts '  use_template_dates ...' if $verbose > 1
    dateString = ''
    currentTargetDate = ''
    calcDate = ''
    lastWasTemplate = false
    n = 0
    # Go through each line in the file
    @lines.each do |line|
      dateString = ''
      # find date in markdown header lines (of form d.m.yyyy and variations of that form)
      if line =~ /^#+\s/
        # clear previous settings when we get to a new heading
        currentTargetDate = ''
        lastWasTemplate = false
        line.scan(%r{(\d{1,2}[\-\./]\d{1,2}[\-\./]\d{4})}) { |m| dateString = m.join }
        if dateString != ''
          # We have a date string to use for any offsets in the following section
          currentTargetDate = dateString
          puts "    UTD: Found CTD #{currentTargetDate} in '#{line.chomp}'" if $verbose > 1
        end
        if line =~ /#template/
          # We have a #template tag so ignore any offsets in the following section
          lastWasTemplate = true
          puts "    UTD: Found #template in '#{line.chomp}'" if $verbose > 1
        end
      end

      # find todo lines with {+3d} or {-4w} etc. plus {0d} special case
      dateOffsetString = ''
      if (line =~ /\*\s+(\[ \])?/) && (line =~ /\{[\+\-]?\d+[dwm]\}/)
        puts "    UTD: Found line '#{line.chomp}'" if $verbose > 1
        line.scan(/\{([\+\-]?\d+[dwm])\}/) { |m| dateOffsetString = m.join }
        if dateOffsetString != ''
          puts "    UTD: Found DOS #{dateOffsetString} in '#{line.chomp}'" if $verbose > 1
          if (currentTargetDate != '') && !lastWasTemplate
            calcDate = calc_offset_date(Date.parse(currentTargetDate), dateOffsetString)
            # Remove the offset text (e.g. {-3d}) by finding string points
            label_start = line.index('{') - 1
            label_end = line.index('}') + 2
            line = "#{line[0..label_start]}#{line[label_end..-2]}" # also chomp off last character (newline)
            # then add the new date
            line += " >#{calcDate}"
            @lines[n] = line
            puts "    Used #{dateOffsetString} line to make '#{line.chomp}'" if $verbose > 1
            # Now write out calcDate
            @is_updated = true
          elsif $verbose > 0
            puts "    Warning: in use_template_dates no currentTargetDate before line '#{line.chomp}'".colorize(WarningColour)
          end
        end
      end
      n += 1
    end
  end

  def process_repeats
    # process any completed tasks with @repeat(..) tags
    # When interval is of the form +2w it will duplicate the task for 2 weeks
    # after the date is was completed.
    # When interval is of the form 2w it will duplicate the task for 2 weeks
    # after the date the task was last due. If this can't be determined,
    # then default to the first option.
    # Valid intervals are [0-9][dwmqy].
    #
    # To work it relies on finding @done(YYYY-MM-DD HH:MM) tags that haven't yet been
    # shortened to @done(YYYY-MM-DD).
    puts '  process_repeats ...' if $verbose > 1
    n = cleaned = 0
    outline = ''
    # Go through each line in the file
    @lines.each do |line|
      updated_line = ''
      completed_date = ''
      # find lines with date-time to shorten, and capture date part of it
      # i.e. @done(YYYY-MM-DD HH:MM)
      if line =~ /@done\(\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}\)/
        # get completed date
        line.scan(/\((\d{4}\-\d{2}\-\d{2}) \d{2}:\d{2}\)/) { |m| completed_date = m.join }
        updated_line = line.gsub(/\(\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}\)/, "(#{completed_date})")
        @lines[n] = updated_line
        cleaned += 1
        @is_updated = true
        if updated_line =~ /@repeat\(.*\)/
          # get repeat to apply
          date_interval_string = ''
          updated_line.scan(/@repeat\((.*?)\)/) { |mm| date_interval_string = mm.join }
          # puts "    In line <#{updated_line.chomp}> (date #{completed_date}) found repeat interval <#{date_interval_string}>"
          if date_interval_string[0] == '+'
            # New repeat date = completed date + interval
            date_interval_string = date_interval_string[1..date_interval_string.length]
            new_repeat_date = calc_offset_date(Date.parse(completed_date), date_interval_string)
            puts "      Adding from completed date --> #{new_repeat_date}" if $verbose > 1
          else
            # New repeat date = due date + interval
            # look for the due date (<YYYY-MM-DD)
            due_date = ''
            if updated_line =~ /<\d{4}\-\d{2}\-\d{2}/
              updated_line.scan(/<(\d{4}\-\d{2}\-\d{2})/) { |m| due_date = m.join }
              # need to remove the old due date (and preceding whitespace)
              updated_line = updated_line.gsub(/\s*<\d{4}\-\d{2}\-\d{2}/, '')
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
          outline = "#{updated_line_without_done} >#{new_repeat_date}"
          # puts "      --> #{outline}" if $verbose > 1

          # Insert this new line after current line
          n += 1
          insert_new_line(outline, n)
        end
      end
      n += 1
    end
  end

  def remove_empty_trailing_lines
    # go backwards through the note, deleting any blanks at the end
    puts '  remove_empty_trailing_lines ...' if $verbose > 1
    cleaned = 0
    n = @lineCount
    while n.positive?
      if @lines[n] =~ /$^/
        @lines.delete_at(n)
        cleaned += 1
      end
      n -= 1
    end
    return unless cleaned.positive?

    @is_updated = true
    puts "  - removed #{cleaned} empty lines" if $verbose > 1
  end

  def rewrite_file
    # write out this update file
    puts '  > writing updated version of ' + @filename.to_s.bold
    # open file and write all the lines out
    filepath = if @is_calendar
                 "#{NP_CALENDAR_DIR}/#{@filename}"
               else
                 "#{NP_NOTES_DIR}/#{@filename}"
               end
    File.open(filepath, 'w') do |f|
      @lines.each do |line|
        f.puts line
      end
    end
  end
end

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: npClean.rb [options] file-pattern'
  opts.separator ''
  options[:move] = 1
  options[:verbose] = 0
  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit
  end
  opts.on('-n', '--nomove', "Don't move calendar items with [[Note]] to the Note") do
    options[:move] = 0
  end
  opts.on('-v', '--verbose', 'Show information as I work') do
    options[:verbose] = 1
  end
  opts.on('-w', '--moreverbose', 'Show more information as I work') do
    options[:verbose] = 2
  end
end
opt_parser.parse! # parse out options, leaving file patterns to process
$verbose = options[:verbose]

# Read in all notes files (including sub-directories, but excluding /@Archive and /@Trash)
i = 0
begin
  Dir.chdir(NP_NOTES_DIR)
  Dir.glob('**/*.txt').each do |this_file|
    next unless this_file =~ /^[^@]/ # as can't get file glob including [^@] to work

    $allNotes[i] = NPNote.new(this_file, i)
    i += 1
  end
  puts "Read in all #{i} notes files" if $verbose > 0
rescue StandardError => e
  puts "ERROR: #{e.exception.message} when reading in all notes files".colorize(WarningColour)
end
n = 0 # number of notes and calendar entries to work on

if ARGV.count.positive?
  # We have a file pattern given, so find that (starting in the notes directory), and use it
  puts "Starting npClean at #{time_now_fmttd} for files matching pattern(s) #{ARGV}."
  begin
    Dir.chdir(NP_NOTES_DIR)
    ARGV.each do |pattern|
      Dir.glob('**/' + pattern).each do |this_file|
        next unless this_file =~ /^[^@]/ # as can't get file glob including [^@] to work

        # Note has already been read in; so now just find which one to point to
        $allNotes.each do |an|
          if an.filename == this_file
            $notes[n] = an
            n += 1
          end
        end
      end
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when reading in notes matching pattern #{pattern}".colorize(WarningColour)
  end

  # if no matching notes, continue by looking in the calendar directory
  if n.zero?
    begin
      Dir.chdir(NP_CALENDAR_DIR)
      ARGV.each do |pattern|
        Dir.glob(pattern).each do |this_file|
          $notes[n] = NPNote.new(this_file, n)
          n += 1
        end
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when reading in calendar files".colorize(WarningColour)
    end
  end

else
  # Read metadata for all note files in the NotePlan directory,
  # and find those altered in the last 24hrs
  mtime = 0
  puts "Starting npClean at #{time_now_fmttd} for all Note and Calendar files altered in last 24 hours."
  begin
    Dir.chdir(NP_NOTES_DIR)
    Dir.glob('**/*.txt').each do |this_file|
      next unless this_file =~ /^[^@]/ # as can't get file glob including [^@] to work

      # if modified time (mtime) in the last 24 hours
      mtime = File.mtime(this_file)
      next unless mtime > (time_now - 86_400)

      # Note has already been read in; so now just find which one to point to
      $allNotes.each do |an|
        if an.filename == this_file
          $notes[n] = an
          n += 1
        end
      end
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when finding recently changed files".colorize(WarningColour)
  end

  # Also read metadata for all calendar files in the NotePlan directory,
  # and find those altered in the last 24hrs
  begin
    Dir.chdir(NP_CALENDAR_DIR)
    Dir.glob('*.txt').each do |this_file|
      # if modified time (mtime) in the last
      mtime = File.mtime(this_file)
      next unless mtime > (time_now - 86_400)

      # read the calendar file in
      $notes[n] = NPNote.new(this_file, n)
      n += 1
    end
  rescue StandardError => e
    puts "ERROR: #{e.exception.message} when finding recently changed files".colorize(WarningColour)
  end
end

if n.positive? # if we have some notes to work on ...
  # puts "Found #{n} notes to attempt to clean:"
  # For each NP file to clean, do the cleaning:
  i = 0
  $notes.each do |note|
    puts "Cleaning file id #{note.id} " + note.title.to_s.bold if $verbose > 0
    note.remove_empty_tasks
    note.remove_empty_trailing_lines
    note.remove_tags_dates
    note.process_repeats
    note.move_calendar_to_notes if note.is_calendar && options[:move] == 1
    note.use_template_dates unless note.is_calendar
    # note.archive_lines
    # If there have been changes, write out the file
    note.rewrite_file if note.is_updated
    i += 1
  end
else
  puts "  Warning: No matching files found.\n".colorize(WarningColour)
end
