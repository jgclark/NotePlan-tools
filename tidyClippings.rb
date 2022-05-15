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
# TODO: finish bring over better options and logging from npTools

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
# Other Constants & Settings
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

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "Tidy web clippings v#{VERSION}"
  opts.separator ''
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
  options[:verbose] = false
  opts.on('-v', '--verbose', 'Show information as I work') do
    options[:verbose] = true
    $verbose = true
  end
end
opt_parser.parse![ARGV] # parse out options, leaving file patterns to process
$verbose = options[:verbose]

info_message_screen("Starting to tidy web clippings at #{$date_time_now_human_fmttd}.")

#-------------------------------------------------------------------------
# Read .txt files in the directory
#-------------------------------------------------------------------------
begin
  Dir.chdir(FILEPATH)
  Dir.glob("*.txt").each do |this_file|
    log_message_screen("- #{this_file}".colorize(InfoColour))

    # initialise other variables (that don't need to persist with the class)
    n = 0
    ignore_before = 0
    ignore_after = 99999 # very long file!
    lines = []
    author = ""
    date = ""
    tags = ""
    title = ""
    # Open file and read in all lines (finding any Done and Cancelled headers)
    # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
    f = File.open(this_file, 'r', encoding: 'utf-8')
    f.each_line do |line|
      lines[n] = line
      # puts " #{n}: #{line}" if $verbose
      line_in = line.clone  # needs a proper clone, not just a reference

      # make a note if this is the first H1 in the file
      ignore_before = n if line_in =~ /^#\s/

      # make a note if this is the first H1 in the file
      ignore_after = n if line_in =~ /^\s*\d*\s*Comments/

      # Delete #clipped or #popclipped references at start of a line
      if line =~ /^#popclipped$/i || line =~ /^#clipped$/i
        lines.delete_at(n)
        line = ''
      end

      # replace lines with '***' or '* * *' or similar with '---'
      line = '---' if line =~ /\*\s*\*\s*\*/

      # replace HTML entity elements with ASCII equivalents
      # TODO: Turn this into a function (or import?)
      # TODO: And then apply to filename too
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

      if line_in != line
        log_message_screen("  #{n}: #{line_in.chomp}\n   -> #{line}")
        lines[n] = line
      end

      # save out some fields if we spot them
      if line =~ /^\s*title:\s+/i # TODO: finish me
        line.scan(/^\s*title:\s+(.*)/i) { |m| title = m.join }
        info_message_screen("  found title: #{title}")
      end
      if line =~ /^#\s+/ && line !~ /^# Menu/i && line !~ /^# Archive/i && line !~ /^# Meta/i && line !~ /^# Post navigation/i
        line.scan(/^#\s+(.*)/) { |m| title = m.join }
        info_message_screen("  found title: #{title}")
      end
      author = "" if line =~ /^\s*author[:\s]+/ # TODO: finish me
      author = "" if line =~ /^\s*by[:\s]+/ # TODO: finish me
      # info_message_screen("  found author: #{author}")
      author = "" if line =~ /^\s*[Tt]ags?[:\s]+/ # TODO: finish me
      author = "" if line =~ /^\s*(category|categories)[:\s]+/ # TODO: finish me
      # info_message_screen("  found tags: #{tags}")
# TODO: cope with this! Tags: [BBC Radio 4](https://nickbaines.wordpress.com/tag/bbc-radio-4/), [hope](https://nickbaines.wordpress.com/tag/hope/), [Jeremiah](https://nickbaines.wordpress.com/tag/jeremiah/), [Leonard Cohen](https://nickbaines.wordpress.com/tag/leonard-cohen/), [Today](https://nickbaines.wordpress.com/tag/today/), [Ukraine](https://nickbaines.wordpress.com/tag/ukraine/)

      n += 1
    end
    f.close

    # TODO: Go through lines again, this time removing blank lines after headings
    # and inserting blank lines before headings (if needed)
    # TODO: Ignore sections starting
    # '# Menu'
    # '# Archive'
    # '# Meta'
    # '# Past navigation'
    # '# Shared'
    # '# Share this'
    # '# Like this'
    # '# Leave a Reply'
    # '# _?Related_?'

    # line_count = lines.size # e.g. for lines 0-2 size => 3
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
puts frontmatter
break # TODO: remove me

    #-------------------------------------------------------------------------
    # write out this updated file, as a markdown file, with frontmatter prepended
    #-------------------------------------------------------------------------
    # open file and write all the lines out,
    # though ignoring any before the first H1 line, and from Comments onwards
    new_filename = "#{this_file[0..-5]}.#{NOTE_EXT}" # take off .txt and put on .md
    File.open(new_filename, 'w') do |f|
      f.puts frontmatter
      n = 0
      lines.each do |line|
        f.puts line if n >= ignore_before && n < ignore_after
        n += 1
      end
    end
    main_message_screen("  -> written updated version to #{new_filename}")

    # Now rename file to same as above but _YYYYMMDDHHMM on the end
    archive_filename = "#{ARCHIVE_FILEPATH}/#{this_file}"
    File.rename(this_file, archive_filename)
    break # TODO: remove me
  end
rescue StandardError => e
  error_message_screen("ERROR: #{e.exception.message}")
end
