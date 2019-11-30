#!/usr/bin/ruby
#----------------------------------------------------------------------------------
# NotePlan note cleanser
# (c) JGC, v0.6,1, 30.11.2019
#----------------------------------------------------------------------------------
# Script to clean up items in NP note or calendar files.
#
# Two ways of running this:
# 1. with passed filename pattern, when it does this just for that file (if it exists)
#    NB: it's a pattern so can pass 'a*.txt' for example
# 2. with no arguments, it checks all files updated in the last 24 hours
#    NB: this is what it will do if run automatically by launchctl.
#
# When cleaning, it
# - removes the time component of any @done() mentions that NP automatically adds
# - removes a set of user-specified tags from @done tasks
# - [TURNED OFF] moves @done items to the ## Done section at the end of files, along with 
#   any sub-tasks or info lines following. (If main task is complete or cancelled, we assume
#   this should affect all subtasks too.)
# - remove any lines with just * or -
# - moves any calendar entries with [[Note link]] in it to that note, after
#   the header section
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
#----------------------------------------------------------------------------------

require 'date'
require 'time'
require 'etc'	# for login lookup

# Setting variables to tweak
Username = 'jonathan' # change me
NumHeaderLines = 2 # suits my use, but probably wants to be 1 for most people
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

timeNow = Time.now
timeNowFmttd = timeNow.strftime(DateTimeFormat)

# Main arrays that sadly need to be global
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
		@cancelledHeader = @doneHeader = 0
		@isCalendar = 0
		@isUpdated = 0

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
			@isCalendar = 1
		else
			# otherwise use first line (but take off heading characters at the start and starting and ending whitespace)
			tempTitle = @lines[0].gsub(/^#+\s*/, "")
			@title = tempTitle.gsub(/\s+$/,"")
			@isCalendar = 0
		end
	end
	

	def clean_dates
		# remove HH:MM part of @done(...) date-time stamps
		# puts "  clean_dates ..."
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
			@isUpdated = 1
			puts "  - cleaned #{cleaned} dates"
		end
	end
	
	
	def remove_empty_tasks
		# Clean up lines with just * or - in them
		# puts "  remove_empty_tasks ..."
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
			@isUpdated = 1
			puts "  - removed #{cleaned} emtpy lines"
		end
	end
	
	
	def clean_tags_dates
		# remove unneeded tags or >dates from complete or cancelled tasks
		# puts "  clean_tags_dates ..."
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
			@isUpdated = 1
			puts "  - removed #{cleaned} tags/dates"
		end
	end


	def insert_new_task( newLine )
		# Insert 'line' into position after header (defined by NumHeaderLines)
		# puts "  insert_new_task ..."
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
		# puts "  move_calendar_to_notes ..."
		noteName = noteToAddTo = nil
		cal = nil
		n = moved = 0
		while (n < @lineCount)
			line = @lines[n]
			# find open todo lines with [[note title]] mentions
			if ( line =~ /^\s*\*[^\]]+\[\[.*\]\]/ )
				# the following regex matches returns an array with one item, so make a string (by join)
				# NB the '+?' gets minimum number of chars, to avoid grabbing contents of several [[notes]] in the same line
				line.scan( /^\s*\*[^\]]+\[\[(.+?)\]\]/ )	{ |m| noteName = m.join() }
				puts "  - found note link [[#{noteName}]]"
				
				# find appropriate note file to add to
				$allNotes.each do | nn | 
					if ( nn.title == noteName )
						noteToAddTo = nn.id
					end
				end

				if ( noteToAddTo )	# if note is found
					# remove this line from the calendar note + write file out
					@lines[n] = nil
					
					# Also remove [[name]] by finding string points
					labelL = line.index('[[')-1
					labelR = line.index(']]')+2
					line = "#{line[0..labelL]}#{line[labelR..-2]}" # also chomp off last character (newline)
					## add the calendar date to the line
					#line = "#{line} >#{@title[0..3]}-#{@title[4..5]}-#{@title[6..7]}" # requires YYYY-MM-DD format
					# insert it after header lines in the note file
					$allNotes[noteToAddTo].insert_new_task(line)	# @@@
					# write the note file out
					$allNotes[noteToAddTo].rewrite_file()
					moved += 1
				else	# if note not found
					puts "Warning: can't find matching note for [[#{noteName}]]. Ignoring"
					exit
				end
			end
			n += 1
		end
		if (moved>0)
			@isUpdated = 1
			puts "  - moved #{moved} lines to notes"
		end
	end


	def reorder_lines
		# Shuffle @done and cancelled lines to relevant sections at end of the file
		# TODO: doesn't yet deal with notes with subheads in them
		# puts "  reorder_lines ..."
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
		puts "    doneToMove:  #{doneToMove} / #{doneToMoveLength}"

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
				puts "      Copying lines #{n}-#{n+linesToMove} to insert at #{doneInsertionLine}"
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
				puts "      Deleting lines #{n}-#{n+linesToMove}"
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
		puts "    cancToMove: #{cancToMove} / #{cancToMoveLength}"
		
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
				puts "      Copying lines #{n}-#{n+linesToMove} to insert at #{cancelledInsertionLine}"
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
				puts "      Deleting lines #{n}-#{n+linesToMove}"
				(n+linesToMove).downto(n) do | i |
					puts "        Deleting line #{i} ..."
					@lines.delete_at(i)
					@lineCount -= 1
					@doneHeader -= 1
				end
			end	
			
			# Finally mark note as updated
			@isUpdated = 1
		end
	end

	
	def rewrite_file
		# write out this update file
		# puts "  > writing updated version of '#{@filename}'..."
		filepath = nil
		# open file and write all the lines out
		if ( @isCalendar == 1 )
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
mtime = 0

# Read in all notes files
puts "Starting npClean at #{timeNowFmttd}"
i = 0
Dir::chdir(NPNotesDir)
Dir.glob("*.txt").each do | this_file |
	$allNotes[i] = NPNote.new(this_file,i)
	i += 1
end
puts "Read in all #{i} notes files"

n = 0 # number of notes/calendar entries to work on

if ( ARGV[0] )
	# We have a file pattern given, so find that (starting in the notes directory), and use it
	# @@@ could use error handling here
	puts "Procesing files matching #{ARGV[0]}"
	Dir::chdir(NPNotesDir)
	Dir.glob(ARGV[0]).each do | this_file |
		# Note has already been read in; so now just find which one to point to
		$allNotes.each do | an |
			if ( an.filename == this_file ) 
				$notes[n] = an
				n += 1
			end
		end
	end
	if (i == 0)
		# continue by looking in the calendar directory
		Dir::chdir(NPCalendarDir)
		Dir.glob(ARGV[0]).each do | this_file |
			$notes[n] = NPNote.new(this_file,n)
			n += 1
		end
	end
else
	# Read metadata for all note files in the NotePlan directory, and 
	# find those altered in the last 24hrs
	puts "Starting npClean at #{timeNowFmttd} for files altered in last 24 hours"
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
	puts "Found #{n} notes to attempt to clean"
	# For each NP file to clean, do the cleaning:
	i=0
	$notes.each do | note | 
		puts
		puts "  Cleaning file id #{note.id}:'#{note.title}' ..."
		note.remove_empty_tasks
		note.clean_tags_dates
		note.clean_dates
		note.move_calendar_to_notes	if ( note.isCalendar == 1 )
		# note.reorder_lines
		# If there have been changes, write out the file
		note.rewrite_file	if ( note.isUpdated == 1 )
		i += 1
	end
else
	puts "No matching files found.\n"
end
