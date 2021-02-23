#!/usr/bin/ruby
#-------------------------------------------------------------------------------
# Script to tidy and clean up HTML text clipped into markdown files
# by Jonathan Clark, v1.1.0, 6.2.2021
#-------------------------------------------------------------------------------
VERSION = "1.1.0"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
NOTE_EXT = "md" # or "txt"
IFTTT_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Clips"
IFTTT_ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive"
DATE_TIME_LOG_FORMAT = '%e %b %Y %H:%M'.freeze # only used in logging

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
DROPBOX_DIR = "#{USER_DIR}/Dropbox/Apps/NotePlan/Documents".freeze
ICLOUDDRIVE_DIR = "#{USER_DIR}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents".freeze
CLOUDKIT_DIR = "#{USER_DIR}/Library/Containers/co.noteplan.NotePlan3/Data/Library/Application Support/co.noteplan.NotePlan3".freeze
# TodaysDate = Date.today # can't work out why this needs to be a 'constant' to work -- something about visibility, I suppose
np_base_dir = CLOUDKIT_DIR if Dir.exist?(CLOUDKIT_DIR) && Dir[File.join(CLOUDKIT_DIR, '**', '*')].count { |file| File.file?(file) } > 1
NP_CALENDAR_DIR = "#{np_base_dir}/Calendar".freeze

# Colours to use with the colorization gem
# to show some possible combinations, run  String.color_samples
# to show list of possible modes, run   puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
InfoColour = :yellow
WarningColour = :light_red

# Variables that need to be globally available
time_now = Time.now
$date_time_now_log_fmttd = time_now.strftime(DATE_TIME_LOG_FORMAT)
$verbose = false
$npfile_count = 0

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
opt_parser.parse! # parse out options, leaving file patterns to process
$verbose = options[:verbose]

puts "Starting to tidy web clippings at #{$date_time_now_log_fmttd}."

#-------------------------------------------------------------------------
# Read .txt files in the directory
#-------------------------------------------------------------------------
begin
  Dir.chdir(IFTTT_FILEPATH)
  Dir.glob("*.txt").each do |this_file|
    puts "- #{this_file}".colorize(InfoColour) if $verbose

    # initialise other variables (that don't need to persist with the class)
    n = 0
    ignore_before = 0
    ignore_after = 99999 # very long file!
    lines = []
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

      # replace a line just surrounded by **...** with an H4 instead
      line.gsub!(/^\s*\*\*(.*)\*\*\s*$/, '#### \1')
      # replace asterisk lists with dash lists (to stop NP thinking they are tasks)
      line.gsub!(/^(\s*)\*\s/, '\1- ')

      if line_in != line
        puts "  #{n}: #{line_in.chomp}\n   -> #{line}" if $verbose
        lines[n] = line
      end

      n += 1
    end
    f.close

<<<<<<< Updated upstream
    # line_count = lines.size # e.g. for lines 0-2 size => 3
    puts "  Read file '#{this_file}' and ignore before/after = #{ignore_before} / #{ignore_after}"
=======
    #TODO: Go through lines again, this time removing blank lines after headings
    # and inserting blank lines before headings (if needed)



    line_count = lines.size # e.g. for lines 0-2 size => 3
    puts "  Read file '#{this_file}'"
>>>>>>> Stashed changes

    #-------------------------------------------------------------------------
    # write out this updated file, as a markdown file
    #-------------------------------------------------------------------------
    # open file and write all the lines out,
    # though ignoring any before the first H1 line, and from Comments onwards
    new_filename = "#{this_file[0..-5]}.#{NOTE_EXT}" # take off .txt and put on .md
    File.open(new_filename, 'w') do |f|
      n = 0
      lines.each do |line|
        f.puts line if n >= ignore_before && n < ignore_after
        n += 1
      end
    end
    puts "  -> written updated version to #{new_filename}".to_s.colorize(CompletedColour)

    # Now rename file to same as above but _YYYYMMDDHHMM on the end
    archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}/#{this_file}"
    File.rename(this_file, archive_filename)
  end
rescue StandardError => e
  puts "ERROR: #{e.exception.message}".colorize(WarningColour)
end
