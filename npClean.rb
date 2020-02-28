#!/usr/bin/ruby
#----------------------------------------------------------------------------------
# NotePlan note cleanser
# (c) JGC, v1.0.0, 28.2.2020
#----------------------------------------------------------------------------------
# Script to clean up items in NP note or calendar files.
#
# When cleaning, it
# - removes the time component of any @done() mentions that NP automatically adds
# - removes a set of user-specified tags from @done tasks
# - [TURNED OFF] moves @done items to the ## Done section at the end of files, along with 
#   any sub-tasks or info lines following. (If main task is complete or cancelled, we assume
#   this should affect all subtasks too.)
# - removes any lines with just * or -
# - moves any calendar entries with [[Note link]] in it to that note, after the header section
# - take template dates and turn into real dates. i.e. change {-12d} or {+3w} to a >date
#    based upon a date (dd.mm.yyyy) in the prededing markdown header line.
#    It ignores those found after a markdown header include the tag #template.
# 
# Two ways of running this:
# 1. with passed filename pattern, when it does this just for that file (if it exists)
#    NB: it's a pattern glob so can pass 'a*.txt' for example
# 2. with no arguments, it checks all files updated in the last 24 hours
#    NB: this is what it will do if run automatically by launchctl.
# Can also specific options: -h for help, -v for verbose and -vv for more verbose mode.
#
# Configuration:
# - StorageType: select iCloud (default) or Drobpox
# - NumHeaderLines: number of lines at the start of a note file to regard as the header
#   Default is 1. Relevant when moving lines around.
# - Username: your username
# - TagsToRemove: array of tag names to remove in completed tasks
#----------------------------------------------------------------------------------
# TODO
# * [ ] cope with moving subheads as well
# * [x] fix empty line being left when moving a calendar to note
# * [x] update {-2d} etc. dates according to previous due date
# * [x] add colouration of output (https://github.com/fazibear/colorize)
# * [x] change to move closed and open tasks with [[Note]] mentions
#----------------------------------------------------------------------------------
# Spec for subheads etc.
# Read all into a more detailed data structure and then write out?
#	- Title line
#	- 1 or 2 metadata lines, starting with #tag or Aim:
#	- open section
#		- (opt) Heading line
#			- (opt) Sub-heading
#				- (opt) Task
#				- indented lines of comment or bullet or just text
#	- done section ('#[#] Done') -- to include cancelled, unlike NP built-in behaviour
#		- as above

require 'date'
require 'time'
require 'etc'	# for login lookup
require 'colorize'
require 'optparse'	# more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

# Setting variables to tweak
Username = 'jonathan' # change me
NumHeaderLines = 3 # suits my use, but probably wants to be 1 for most people
StorageType = "iCloud"	# or Dropbox
TagsToRemove = ["#waiting","#high"] # simple array of strings
DateFormat = "%d.%m.%y"
DateTimeFormat = "%e %b %Y %H:%M"

# Other Constants
TodaysDate = Date.today	# can't work out why this needs to be a 'constant' to work -- something about visibility, I suppose
User = Etc.getlogin		# for debugging when running by launchctl
if ( StorageType == "iCloud" )
	NPBaseDir = "/Users/#{Username}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents" # for iCloud storage
else
	NPBaseDir = "/Users/#{Username}/Dropbox/Apps/NotePlan/Documents" # for Dropbox storage
end
NPNotesDir	= "#{NPBaseDir}/Notes"
NPCalendarDir = "#{NPBaseDir}/Calendar"

# Other variables
timeNow = Time.now
timeNowFmttd = timeNow.strftime(DateTimeFormat)

# Colours, using the colorization gem
# to show some possible combinations, run	String.color_samples
# to show list of possible modes, run 	puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
ActiveColour = :light_yellow
WarningColour = :light_red
InstructionColour = :light_cyan

# Variables that need to be globally available
$verbose = 0
$allNotes = Array.new	# to hold all note objects
$notes    = Array.new	# to hold all relevant note objects

#-------------------------------------------------------------------------
# Class definition
#-------------------------------------------------------------------------
class NPNote
	# Define the attributes that need to be visible outside the class instances
	attr_reader :id
	attr_reader :title
	attr_reader :cancelledHeader
	attr_reader :doneHeader
	attr_reader :isCalendar
	attr_reader :isUpdated
	attr_reader :filename

	def initialize(this_file, id)
		# initialise instance variables (that persist with the class instance)
		@filename = this_file
		@id = id
		@title = nil
		@lines = Array.new
		@lineCount = 0
		@cancelledHeader = 0
		@doneHeader = 0
		@isCalendar = false
		@isUpdated = false

		# initialise other variables (that don't need to persist with the class)
		n = 0
		line = 0
		tempTitle = nil

		# puts "initialising #{@filename} from #{Dir.pwd}"
		# Open file and read in all lines (finding any Done and Cancelled headers)
		# NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
		f = File.open(@filename, "r", :encoding => 'utf-8')
		f.each_line { | line |
			@lines[n] = line			
			@doneHeader = n			if ( line =~ /^## Done$/ ) 
			@cancelledHeader = n	if ( line =~ /^## Cancelled$/ ) 
			n -= 1					if ( line =~ /^\s*[\*\-]\s*$/ ) # i.e. remove lines with just a * or -
			n += 1
		}
		f.close
		@lineCount = @lines.size

		# Now make a title for this file: 
		if (@filename =~ /\d{8}\.txt/)
			# for Calendar file, use the date from filename
			@title = @filename[0..7]
			@isCalendar = true
		else
			# otherwise use first line (but take off heading characters at the start and starting and ending whitespace)
			tempTitle = @lines[0].gsub(/^#+\s*/, "")
			@title = tempTitle.gsub(/\s+$/,"")
			@isCalendar = false
		end
	end
	

	def clean_dates
		# remove HH:MM part of @done(...) date-time stamps
		puts "  clean_dates ..."		if ( $verbose > 1 )
		n = cleaned = 0
		line = outline = ''
		while (n < @lineCount)
			line = @lines[n]
			# find lines with date-time to shorten, and capture date part of it
			#   i.e. YYYY-MM-DD HH:MM
			if ( line =~ /\(\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}\)/ )
				line.scan( /\((\d{4}\-\d{2}\-\d{2}) \d{2}:\d{2}\)/ ) { | m |
					if ( m[0] != '' )
						outline = line.gsub(/\(\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}\)/, "(#{m[0]})")
					end
				}
				@lines[n] = outline
				cleaned += 1
			end
			n += 1
		end
		if (cleaned>0)
			@isUpdated = true
			puts "  - cleaned #{cleaned} dates"		if ( $verbose > 1 )
		end
	end
	
	
	def remove_empty_tasks
		# Clean up lines with just * or - in them
		puts "  remove_empty_tasks ..."		if ( $verbose > 1 )
		n = cleaned = 0
		while (n < @lineCount)
			# blank any lines which just have a * or -
			if ( @lines[n] =~ /^\s*[\*\-]\s*$/ )
				@lines[n] = ""
				cleaned += 1
			end
			n += 1
		end
		if (cleaned>0)
			@isUpdated = true
			puts "  - removed #{cleaned} emtpy lines"			if ( $verbose > 0 )
		end
	end
	
	
	def remove_tags_dates
		# remove unneeded tags or >dates from complete or cancelled tasks
		puts "  remove_tags_dates ..."		if ( $verbose > 1 )
		n = cleaned = 0
		while (n < @lineCount)
			# remove any >YYYY-MM-DD on completed or cancelled tasks
			if ( ( @lines[n] =~ /\s>\d{4}\-\d{2}\-\d{2}/ ) && ( @lines[n] =~ /\[(x|-)\]/ ) )
				@lines[n].gsub!(/\s>\d{4}\-\d{2}\-\d{2}/, "")
				cleaned += 1
			end
			
			# Remove any tags from the TagsToRemove list. Iterate over that array:
			TagsToRemove.each do | tag |
				if ( ( @lines[n] =~ /#{tag}/ ) && ( @lines[n] =~ /\[(x|-)\]/ ) )
					@lines[n].gsub!(/ #{tag}/, "")
					cleaned += 1
				end
			end
			n += 1
		end
		if (cleaned>0)
			@isUpdated = true
			puts "  - removed #{cleaned} tags/dates"		if ( $verbose > 0 )
		end
	end


	def insert_new_task( newLine )
		# Insert 'line' into position after header (defined by NumHeaderLines)
		puts "  insert_new_task ..."		if ( $verbose > 1 )
		n = @lineCount  # start iterating from the end of the array
		while (n >= NumHeaderLines)
			@lines[n+1] = @lines[n]
			n -= 1
		end
		@lines[NumHeaderLines] = newLine
		@lineCount += 1
	end


	def move_calendar_to_notes
		# Move tasks with a [[note link]] to that note (inserting after header)
		puts "  move_calendar_to_notes ..."		if ( $verbose > 1 )
		noteName = noteToAddTo = nil
		cal = nil
		n = moved = 0
		while (n < @lineCount)
			line = @lines[n]
			# find todo lines with [[note title]] mentions
			if ( line =~ /^\s*\*.*\[\[.*\]\]/ )
				# the following regex matches returns an array with one item, so make a string (by join)
				# NB the '+?' gets minimum number of chars, to avoid grabbing contents of several [[notes]] in the same line
				line.scan( /^\s*\*.*\[\[(.+?)\]\]/ )	{ |m| noteName = m.join() }
				puts "  - found note link [[#{noteName}]]"		if ( $verbose > 0 )
				
				# find appropriate note file to add to
				$allNotes.each do | nn | 
					if ( nn.title == noteName )
						noteToAddTo = nn.id
					end
				end

				if ( noteToAddTo )	# if note is found
					# remove this line from the calendar note + write file out
					@lines.delete_at(n)
					
					# Also remove the [[name]] text by finding string points
					labelL = line.index('[[')-1
					labelR = line.index(']]')+2
					line = "#{line[0..labelL]}#{line[labelR..-2]}" # also chomp off last character (newline)
					# insert it after header lines in the note file
					$allNotes[noteToAddTo].insert_new_task(line)
					# write the note file out
					$allNotes[noteToAddTo].rewrite_file()
					moved += 1
				else	# if note not found
					puts "   Warning: can't find matching note for [[#{noteName}]]. Ignoring".colorize(WarningColour)
				end
			end
			n += 1
		end
		if (moved > 0)
			@isUpdated = true
			puts "  - moved #{moved} lines to notes"		if ( $verbose > 0 )
		end
	end


	def reorder_lines
		# Shuffle @done and cancelled lines to relevant sections at end of the file
		# TODO: doesn't yet deal with notes with subheads in them
		puts "  reorder_lines ..."	if ( $verbose > 1 )
		line = ''
		doneToMove = Array.new			# NB: zero-based
		doneToMoveLength = Array.new	# NB: zero-based
		cancToMove = Array.new			# NB: zero-based
		cancToMoveLength = Array.new	# NB: zero-based
		n = i = c = 0

		# Go through all lines between metadata and ## Done section
		# start, noting completed tasks
		n = 1
		searchLineLimit = (@doneHeader > 0) ? @doneHeader : @lineCount
		while (n < searchLineLimit)
			n += 1
			line = @lines[n]			
			if ( line =~ /\*\s+\[x\]/ ) 
				# save this line number
				doneToMove.push(n)
				# and look ahead to see how many lines to move -- all until blank or starting # or *
				linesToMove = 0
				while ( n < @lineCount )
					break if ( ( @lines[n+1] =~ /^(#+\s+|\*\s+)/ ) or ( @lines[n+1] =~ /^$/ ) )
					linesToMove += 1
					n += 1
				end
				# save this length
				doneToMoveLength.push(linesToMove)
			end
		end
		puts "    doneToMove:  #{doneToMove} / #{doneToMoveLength}"	if ( $verbose > 1 )

		# Do some done line shuffling, is there's anything to do
		if ( doneToMove.size > 0 )
			# If we haven't already got a Done section, make one
			if ( @doneHeader == 0 )
				@lines.push("")
				@lines.push("## Done")
				@lineCount = @lineCount + 2
				@doneHeader = @lineCount
			end

			# Copy the relevant lines
			doneInsertionLine = (@cancelledHeader != 0) ? @cancelledHeader : @lineCount
			c = 0
			doneToMove.each do | n |
				linesToMove = doneToMoveLength[c]
				puts "      Copying lines #{n}-#{n+linesToMove} to insert at #{doneInsertionLine}"	if ( $verbose > 1 )
				(n..(n+linesToMove)).each do | i |
					@lines.insert(doneInsertionLine, @lines[i])
					@lineCount += 1
					doneInsertionLine += 1
				end
				c += 1
			end

			# Now delete the original items (in reverse order to preserve numbering)
			c = doneToMoveLength.size - 1
			doneToMove.reverse.each do | n |
				linesToMove = doneToMoveLength[c]
				puts "      Deleting lines #{n}-#{n+linesToMove}"	if ( $verbose > 1 )
				(n+linesToMove).downto(n) do | i |
					@lines.delete_at(i)
					@lineCount -= 1
					doneInsertionLine -= 1
					@doneHeader -= 1
				end
				c -= 1
			end
		end
		
		# Go through all lines between metadata and ## Done section
		# start, noting cancelled line numbers
		n = 0
		searchLineLimit = (@doneHeader > 0) ? @doneHeader : @lineCount
		while (n < searchLineLimit)
			n += 1
			line = @lines[n]
			if ( line =~ /\*\s*\[\-\]/ )
				# save this line number
				cancToMove.push(n)		
				# and look ahead to see how many lines to move -- all until blank or starting # or *
				linesToMove = 0
				while ( n < @lineCount )
					linesToMove += 1
					break if ( ( @lines[n+1] =~ /^(#+\s+|\*\s+)/ ) or ( @lines[n+1] =~ /^$/ ) )
					n += 1
				end
				# save this length
				cancToMoveLength.push(linesToMove)
			end
		end
		puts "    cancToMove: #{cancToMove} / #{cancToMoveLength}"	if ( $verbose > 1 )
		
		# Do some cancelled line shuffling, is there's anything to do
		if ( cancToMove.size > 0 )
			# If we haven't already got a Cancelled section, make one
			if ( @cancHeader == 0 )
				@lines.push("")
				@lines.push("## Cancelled")
				@lineCount = @lineCount + 2
				@cancHeader = @lineCount
			end

			# Copy the relevant lines
			cancelledInsertionLine = @lineCount
			c = 0
			cancToMove.each do | n |
				linesToMove = cancToMoveLength[c]
				puts "      Copying lines #{n}-#{n+linesToMove} to insert at #{cancelledInsertionLine}"	if ( $verbose > 1 )
				(n..(n+linesToMove)).each do |i|
					@lines.insert(cancelledInsertionLine, @lines[i])
					@lineCount += 1
					cancelledInsertionLine += 1
				end
				c += 1
			end

			# Now delete the original items (in reverse order to preserve numbering)
			c = doneToMoveLength.size - 1
			cancToMove.reverse.each do | n |
				linesToMove = doneToMoveLength[c]
				puts "      Deleting lines #{n}-#{n+linesToMove}"	if ( $verbose > 1 )
				(n+linesToMove).downto(n) do | i |
					puts "        Deleting line #{i} ..."	if ( $verbose > 1 )
					@lines.delete_at(i)
					@lineCount -= 1
					@doneHeader -= 1
				end
			end	
			
			# Finally mark note as updated
			@isUpdated = true
		end
	end


	def calc_offset_date(oldDate, interval)
		# Calculate next review date, assuming interval is of form nn[dwmq]
		daysToAdd = 0
		unit = interval[-1]
		num = interval.chop.to_i
		case unit
		when 'd'
			daysToAdd = num
		when 'w'
			daysToAdd = num*7
		when 'm'
			daysToAdd = num*30
		when 'q'
			daysToAdd = num*90
		else
			puts "    Error in calc_offset_date from #{oldDate} by #{interval}".colorize(WarningColour)
		end
		# puts "  COD: with #{oldDate} interval #{interval} found #{daysToAdd} daysToAdd"
		newDate = oldDate + daysToAdd
		return newDate
	end

	
	def use_template_dates
		# Take template dates and turn into real dates
		puts "  use_template_dates ..."		if ( $verbose > 1 )
		dateString = ""
		currentTargetDate = ""
		calcDate = ""
		lastWasTemplate = false
		n = 0
		# Go through each line in the file
		@lines.each do | line |
			dateString = ""
			# find date in markdown header lines (of form d.m.yyyy and variations of that form)
			if ( line =~ /^#+\s/ )
				# clear previous settings when we get to a new heading
				currentTargetDate = "" 
				lastWasTemplate = false
				line.scan( /(\d{1,2}[\-\.\/]\d{1,2}[\-\.\/]\d{4})/ )	{ |m| dateString = m.join() }
				if ( dateString != "" )
					# We have a date string to use for any offsets in the following section
					currentTargetDate = dateString
					puts "    UTD: Found CTD #{currentTargetDate} in '#{line.chomp}'"	if ( $verbose > 1 )
				end
				if ( line =~ /#template/ )	
					# We have a #template tag so ignore any offsets in the following section
					lastWasTemplate = true
					puts "    UTD: Found #template in '#{line.chomp}'"	if ( $verbose > 1 )
				end
			end
			
			# find todo lines with {+3d} or {-4w} etc.
			dateOffsetString = ""
			if (( line =~ /\*\s+(\[ \])?/ ) and ( line =~ /\{[\+\-]\d+[dwm]\}/ ))
				puts "    UTD: Found line '#{line.chomp}'"		if ( $verbose > 1 )
				line.scan( /\{([\+\-]\d+[dwm])\}/ )	{ |m| dateOffsetString = m.join() }	
				if ( dateOffsetString != "" )
					puts "    UTD: Found DOS #{dateOffsetString} in '#{line.chomp}'"	if ( $verbose > 1 )
					if ( currentTargetDate != "" and not lastWasTemplate )
						calcDate = calc_offset_date( Date.parse(currentTargetDate) , dateOffsetString )
						# Remove the offset {-3d} text by finding string points
						labelL = line.index('{')-1
						labelR = line.index('}')+2
						line = "#{line[0..labelL]}#{line[labelR..-2]}" # also chomp off last character (newline)
						# then add the new date
						line += " >#{calcDate}"
						@lines[n] = line
						puts "    Used #{dateOffsetString} line to make '#{line.chomp}'"		if ( $verbose > 1 )
						# Now write out calcDate 
						@isUpdated = true
					else
						puts "    Warning: in use_template_dates no currentTargetDate before line '#{line.chomp}'".colorize(WarningColour)	if ( $verbose > 0 )
					end
				end
			end
			n += 1
		end
	end
	

	def rewrite_file
		# write out this update file
		puts "  > writing updated version of " + "#{@filename}".bold
		filepath = nil
		# open file and write all the lines out
		if ( @isCalendar )
			filepath = "#{NPCalendarDir}/#{@filename}"
		else
			filepath = "#{NPNotesDir}/#{@filename}"
		end
 		File.open(filepath, "w") { | f |
			@lines.each do |line| 
				f.puts line	
			end
		}
	end
end


#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: npClean.rb [options] file-pattern"
	opts.separator ""
	options[:verbose] = 0
	opts.on("-v", "--verbose", "Show information as I work") do
		options[:verbose] = 1
	end
	opts.on("-w", "--moreverbose", "Show more information as I work") do
		options[:verbose] = 2
	end
	opts.on("-h", "--help", "Show help") do
		puts opts
		exit
	end
end
opt_parser.parse!	# parse out options, leaving file patterns to process

$verbose = options[:verbose]
# Read in all notes files
i = 0
Dir::chdir(NPNotesDir)
Dir.glob("*.txt").each do | this_file |
	$allNotes[i] = NPNote.new(this_file,i)
	i += 1
end
puts "Read in all #{i} notes files"		if ( $verbose > 0 )

n = 0 # number of notes/calendar entries to work on

if ( ARGV.count > 0 )
	# We have a file pattern given, so find that (starting in the notes directory), and use it
	# @@@ could use error handling here
	Dir::chdir(NPNotesDir)
	puts "Starting npClean at #{timeNowFmttd} for files matching pattern(s) #{ARGV}."
	ARGV.each do | pattern |
		Dir.glob(pattern).each do | this_file |
			# Note has already been read in; so now just find which one to point to
			$allNotes.each do | an |
				if ( an.filename == this_file ) 
					$notes[n] = an
					n += 1
				end
			end
		end
	end
	if (n == 0)
		# continue by looking in the calendar directory
		Dir::chdir(NPCalendarDir)
		ARGV.each do | pattern |
			Dir.glob(pattern).each do | this_file |
				$notes[n] = NPNote.new(this_file,n)
			n += 1
			end
		end
	end
else
	# Read metadata for all note files in the NotePlan directory,
	# and find those altered in the last 24hrs
	mtime = 0
	puts "Starting npClean at #{timeNowFmttd} for all Note and Calendar files altered in last 24 hours."	
	Dir::chdir(NPNotesDir)
	Dir.glob("*.txt").each do | this_file |
		# if modified time (mtime) in the last
		mtime = File.mtime(this_file)
		if ( mtime > (timeNow - 86400) )
			# Note has already been read in; so now just find which one to point to
			$allNotes.each do | an |
				if ( an.filename == this_file ) 
					$notes[n] = an
					n += 1
				end
			end	
		end
	end

	# Also read metadata for all calendar files in the NotePlan directory, 
	# and find those altered in the last 24hrs
	Dir::chdir(NPCalendarDir)
	Dir.glob("*.txt").each do | this_file |
	# if modified time (mtime) in the last
	mtime = File.mtime(this_file)
	if ( mtime > (timeNow - 86400) )
		# read the calendar file in
		$notes[n] = NPNote.new(this_file,n)
		n += 1
		end	
	end
end


if ( n > 0 )	# if we have some notes to work on ...
	# puts "Found #{n} notes to attempt to clean:"
	# For each NP file to clean, do the cleaning:
	i=0
	$notes.each do | note | 
		puts "Cleaning file id #{note.id} " + "#{note.title}".bold	if ( $verbose > 0 )
		note.remove_empty_tasks
		note.remove_tags_dates
		note.clean_dates
		note.move_calendar_to_notes	if ( note.isCalendar )
		note.use_template_dates	if ( not note.isCalendar )
		# note.reorder_lines
		# If there have been changes, write out the file
		note.rewrite_file	if ( note.isUpdated )
		i += 1
	end
else
	puts "  Warning: No matching files found.\n".colorize(WarningColour)
end
