#!/usr/bin/env ruby
#-------------------------------------------------------------------------------
# Script to tidy and clean up HTML text clipped into markdown files
# by Jonathan Clark, v1.2.0, 11.4.2022
#-------------------------------------------------------------------------------
VERSION = "1.2.0"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html
require 'ostruct'

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
NOTE_EXT = "md" # or "txt"
# FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Clips" # or ...
FILEPATH = "/Users/jonathan/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
# ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive" # or ...
ARCHIVE_FILEPATH = "/Users/jonathan/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Archive"
DATE_TIME_HUMAN_FORMAT = '%e %b %Y %H:%M'.freeze
DATE_TIME_LOG_FORMAT = '%Y%m%d%H%M'.freeze # only used in logging

#-------------------------------------------------------------------------------
# To use test data instead of live data, uncomment relevant definitions:
#-------------------------------------------------------------------------------
# twitter_test_data = <<-END_T_DATA
# January 24, 2021 at 03:56PM | A useful thread which highlights the problems of asking the wrong question. https://t.co/xEKimf9cLK | jgctweets | http://twitter.com/jgctweets/status/1353371090609909760
# END_T_DATA

#-------------------------------------------------------------------------------
# Other Constants
#-------------------------------------------------------------------------------
USERNAME = ENV['LOGNAME'] # pull username from environment
USER_DIR = ENV['HOME'] # pull home directory from environment
NP_DROPBOX_DIR = "#{USER_DIR}/Dropbox/Apps/NotePlan/Documents".freeze
NP_ICLOUDDRIVE_DIR = "#{USER_DIR}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents".freeze
NP_CLOUDKIT_DIR = "#{USER_DIR}/Library/Containers/co.noteplan.NotePlan3/Data/Library/Application Support/co.noteplan.NotePlan3".freeze
# TodaysDate = Date.today # can't work out why this needs to be a 'constant' to work -- something about visibility, I suppose
NP_BASE_DIR = NP_CLOUDKIT_DIR if Dir.exist?(NP_CLOUDKIT_DIR) && Dir[File.join(NP_CLOUDKIT_DIR, '**', '*')].count { |file| File.file?(file) } > 1
NP_CALENDAR_DIR = "#{NP_BASE_DIR}/Calendar".freeze

# Colours to use with the colorization gem
# to show some possible combinations, run  String.color_samples
# to show list of possible modes, run   puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
InfoColour = :yellow
ErrorColour = :light_red
# Test to see if we're running interactively or in a batch mode:
# if batch mode then disable colorisation which doesn't work in logs
tty_code = `tty`.chomp
String.disable_colorization true if tty_code == 'not a tty'

# Variables that need to be globally available
time_now = Time.now
$date_time_now_human_fmttd = time_now.strftime(DATE_TIME_HUMAN_FORMAT)
$date_time_now_log_fmttd = time_now.strftime(DATE_TIME_LOG_FORMAT)
$verbose = false
$npfile_count = 0

#-------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------
def main_message_screen(message)
  puts message.colorize(CompletedColour)
end

def info_message_screen(message)
  puts message.colorize(InfoColour)
end

def error_message_screen(message)
  puts message.colorize(ErrorColour)
end

def log_message_screen(message)
  puts message if $verbose
end

def standardise_line(line)
  # simplify HTML and Markdown in the line we receive
  # replace lines with '***' or '* * *' or similar with '---'
  line = '---' if line =~ /\*\s*\*\s*\*/

  # replace HTML entity elements with ASCII equivalents
  line.gsub!(/&amp;/, '&')
  line.gsub!(/&nbsp;/, ' ')
  line.gsub!(/&nbsp_place_holder;/, ' ')
  line.gsub!(/&mdash;/, '--')
  line.gsub!(/&lsquot;/, "\'")
  line.gsub!(/&ldquot;/, "\"")
  line.gsub!(/&rsquot;/, "\'")
  line.gsub!(/&rdquot;/, "\"")
  line.gsub!(/&quot;/, "\"")
  line.gsub!(/&lt;/, "<")
  line.gsub!(/&gt;/, ">")
  line.gsub!(/&hellip;/, "...")
  line.gsub!(/&nbsp;/, " ")

  # replace smart quotes with dumb ones
  line.gsub!(/“/, '"')
  line.gsub!(/”/, '"')
  line.gsub!(/‘/, '\'')
  line.gsub!(/’/, '\'')
  line.gsub!(/&#039;/, '\'')
  line.gsub!(/&#8217;/, '\'')
  # replace en dash with markdwon equivalent
  line.gsub!(/—/, '--')

  # replace '\.' with '.'
  line.gsub!(/\\\./, '.')

  # replace odd things in Stocki '**_ ... _**' with simpler '_..._'
  line.gsub!(/\*\*_/, '_')
  line.gsub!(/_\*\*/, '_')

  # replace a line just surrounded by **...** with an H4 instead
  line.gsub!(/^\s*\*\*(.*)\*\*\s*$/, '#### \1')
  # replace asterisk lists with dash lists (to stop NP thinking they are tasks)
  line.gsub!(/^(\s*)\*\s/, '\1- ')
  # trim the end of the line
  line.rstrip!
  return line
end

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = OpenStruct.new
opt_parser = OptionParser.new do |opts|
  opts.banner = "Tidy web clippings v#{VERSION}\nUsage: tidyClippings.rb [options] [file-pattern]"
  opts.separator ''
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
  options[:verbose] = false
  opts.on('-v', '--verbose', 'Show information as I work') do
    options[:verbose] = true
  end
end
opt_parser.parse!(ARGV) # parse out options, leaving file patterns to process
$verbose = options.verbose


#-------------------------------------------------------------------------
# Read .txt files in the directory
#-------------------------------------------------------------------------
begin
  Dir.chdir(FILEPATH)
  glob_pattern = ARGV.count.positive? ? '*' + ARGV[0] + '*.txt' : '*.txt'
  info_message_screen("Starting to tidy web clippings for #{glob_pattern} at #{$date_time_now_human_fmttd}.")
  Dir.glob(glob_pattern).each do |this_file|
    log_message_screen("- #{this_file}")

    # initialise other variables (that don't need to persist with the class)
    n = 0
    ignore_before = 0
    ignore_after = 99999 # very long file!
    lines = []
    author = ""
    date = ""
    tags = ""
    title = ""
    # Open file and read in all lines
    # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
    f = File.open(this_file, 'r', encoding: 'utf-8')
    f.each_line do |line|
      line_in = line.clone.rstrip  # needs a proper clone, not just a reference
      # log_message_screen(" #{n}: #{line_in}")
      lines[n] = line

      # Fix all sorts of things in the line
      line = standardise_line(line)

      # Delete #clipped or #popclipped references at start of a line
      if line =~ /^#popclipped$/i || line =~ /^#clipped$/i
        lines.delete_at(n)
        line = ''
      end

      if line != line_in
        # log_message_screen(" #{n}: #{line_in}\n   -> #{line}")
        lines[n] = line
      end

      n += 1
    end
    f.close
    main_message_screen("After first pass, #{n} lines left")

    # TODO: Go through lines again
    last_line = ""
    n = 0
    ignore_this_section = true
    lines.each do |line|
      # TODO: Ignore sections starting
      ignore_section_titles = ['New Resources', 'Menu', 'Archive', 'Meta', 'Past navigation', 'Shared', 'Share this', 'Share this post', 'How we use cookies', 'Skip to content', 'Like this', 'Leave a Reply', '_?Related_?', 'More by this author', 'John Piper']
      if ignore_this_section 
        if line !~ /^#+\s+/ # TODO: same heading level
          log_message_screen("  #{n} found new section '#{line}' after ignore")
          ignore_this_section = false
        else
          n += 1
          next
        end
      end
      re = "#\s+#{ignore_section_titles[0]}"
      if line =~ /#{re}/
        log_message_screen("  #{n} found section '#{line}' to ignore")
        ignore_this_section = true
        n += 1
        next
      end

      # insert blank lines before headings
      if !last_line.empty? && line =~ /^#+\s+/
        lines[n] = ""
        last_line = ""
        log_message_screen("  #{n} inserted: empty line before heading")
        n += 1
      end
      # remove blank lines after headings
      if last_line =~ /^#+\s+/ && line.empty?
        lines.delete_at(n)
        log_message_screen("  #{n} removed: empty line after heading")
        line = last_line
        next
      end

      # make a note if this is the first H1
      ignore_before = n if line =~ /^#\s/ && ignore_before.zero?

      # make a note if this is the Comments section
      ignore_after = n if line =~ /^\s*\d*\s*Comments/

      # save out some fields if we spot them
      if line =~ /^\s*title:\s+/i # TODO: finish me
        line.scan(/^\s*title:\s+(.*)/i) { |m| title = m.join }
        info_message_screen("  found title: #{title}")
      end
      if line =~ /^#\s+/ && line !~ /^# Menu/i && line !~ /^# Archive/i && line !~ /^# Meta/i && line !~ /^# Post navigation/i
        line.scan(/^#\s+(.*)/) { |m| title = m.join }
        info_message_screen("  found title: #{title}")
      end

      if line =~ /^\s*author[:\s]+/ # TODO: test me
        line.scan(/^\s*author[:\s]+(.*)/) { |m| author = m.join }
        log_message_screen("  found author: #{author}")
      end
      if line =~ /^\s*by[:\s]+/ # TODO: test me
        line.scan(/^\s*by[:\s]+(.*)/) { |m| author = m.join }
        log_message_screen("  found author: #{author}")
      end

      if line =~ /^\s*[Tt]ags?[:\s]+/ # TODO: test me
        line.scan(/^\s*[Tt]ags?[:\s]+(.*)/) { |m| tags = m.join }
        log_message_screen("  found tags: #{tags}")
      end
      if line =~ /^\s*(category|categories)[:\s]+/ # TODO: test me
        line.scan(/^\s*(category|categories)[:\s]+(.*)/) { |m| tags = m.join }
        log_message_screen("  found tags: #{tags}")
      end
      # TODO: cope with this! Tags: [BBC Radio 4](https://nickbaines.wordpress.com/tag/bbc-radio-4/), [hope](https://nickbaines.wordpress.com/tag/hope/), [Jeremiah](https://nickbaines.wordpress.com/tag/jeremiah/), [Leonard Cohen](https://nickbaines.wordpress.com/tag/leonard-cohen/), [Today](https://nickbaines.wordpress.com/tag/today/), [Ukraine](https://nickbaines.wordpress.com/tag/ukraine/)

      last_line = line
      n += 1
    end
    main_message_screen("After second pass, #{lines.size} lines left")

    log_message_screen("  Read file '#{this_file}' and ignore before/after = #{ignore_before} / #{ignore_after}")

    #-------------------------------------------------------------------------
    # Form the frontmatter section
    #-------------------------------------------------------------------------
    fm_author = author || ""
    fm_clip_date = $date_time_now_log_fmttd # TODO: better to pick up file date, but this is close
    fm_doc_date = ""
    fm_tags = tags || ""
    fm_title = title || ""
    frontmatter = "---\ntitle: #{fm_title}\nauthor: #{fm_author}\ndate: #{fm_doc_date}\nclipped: #{fm_clip_date}\ntags: [#{fm_tags}]\nsource: \n---\n\n"

    main_message_screen(frontmatter)

    #-------------------------------------------------------------------------
    # write out this updated file, as a markdown file, with frontmatter prepended
    #-------------------------------------------------------------------------
    # first simplify filename itself
    new_filename = "#{standardise_line(this_file[0..-5]).lstrip}.#{NOTE_EXT}" # take off .txt and put on .md
    # break # TODO: remove me

    # open file and write all the lines out,
    # though ignoring any before the first H1 line, and from Comments onwards
    File.open(new_filename, 'w') do |f|
      f.puts frontmatter
      n = 0
      lines.each do |line|
        f.puts line if n >= ignore_before && n < ignore_after
        n += 1
      end
    end
    main_message_screen("  -> written updated version to '#{new_filename}'")

    # Now rename file to same as above but _YYYYMMDDHHMM on the end
    archive_filename = "#{ARCHIVE_FILEPATH}/#{this_file}"
    # File.rename(this_file, archive_filename)

    break # TODO: remove me
  end
rescue StandardError => e
  error_message_screen("ERROR: #{e.exception.full_message}")
end
