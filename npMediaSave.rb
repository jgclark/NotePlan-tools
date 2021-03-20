#!/usr/bin/ruby
#-------------------------------------------------------------------------------
# Script to Save some Media notes into NotePlan
# by Jonathan Clark, v0.3.3, 20.3.2021
#
# v0.3 now copes with multi-line tweets
#-------------------------------------------------------------------------------
VERSION = "0.3.2"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
MEDIA_STRING = '### Media' # the title of the section heading to add these notes to
NOTE_EXT = "md" # or "txt"
IFTTT_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/"
IFTTT_ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive/"
INSTAPAPER_FILE = "Instapaper Archived Items.txt"
MEDIUM_FILE = "Medium Articles.txt"
SPOTIFY_FILE = "Spotify Saved Tracks.txt"
TWITTER_FILE = "My Tweets.txt"
YOUTUBE_LIKES_FILE = "YouTube liked videos.txt"
YOUTUBE_UPLOAD_FILE = "YouTube upload.txt"
DATE_TIME_LOG_FORMAT = '%e %b %Y %H:%M'.freeze # only used in logging
DATE_TIME_APPEND_FORMAT = '%Y%m%d%H%M'.freeze

#-------------------------------------------------------------------------------
# To use test data instead of live data, uncomment relevant definitions.
# NB: assumes one per line, apart from Twitter.
#-------------------------------------------------------------------------------
# $spotify_test_data = <<-END_S_DATA
# February 6, 2021 at 11:11PM | Espen Eriksen Trio | In the Mountains | Never Ending January | https://ift.tt/2TRqQiB | https://ift.tt/2LptJng
# February 6, 2021 at 11:56AM | Brian Doerksen | Creation Calls | Today | https://ift.tt/2qQI2Sq | https://ift.tt/3pYs1by
# END_S_DATA

# $instapaper_test_data = <<-END_I_DATA
# February 6, 2021 at 05:49AM \\ Thomas Creedy: Imago Dei \\ https://ift.tt/3rJl1Bh \\
# February 6, 2021 at 06:02AM \\ Is the 'seal of the confessional' Anglican? \\ https://ift.tt/2MpMAPX \\ "Andrew Atherstone writes: The Church of England has at last published the report of the 'Seal of the Confessional' working party , more than a year after it..."
# February 6, 2021 at 04:04PM \\ In what ways can we form useful relationships between notes? \\ https://ift.tt/3aT3LS3 \\ "Nick Milo Aug 8, 2020 * 7 min read Are you into personal knowledge management PKM)? Are you confused about when to use a folder versus a tag versus a link..."
# END_I_DATA

# $twitter_test_data = <<-END_T_DATA
# February 6, 2021 at 03:56PM | A useful thread which highlights the problems of asking the wrong question. https://t.co/xEKimf9cLK | jgctweets | http://twitter.com/jgctweets/status/1353371090609909760
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
CompletedColour = :light_green
InfoColour = :yellow
ErrorColour = :light_red
# Test to see if we're running interactively or in a batch mode:
# if batch mode then disable colorisation which doesn't work in logs
tty_code = `tty`.chomp
String.disable_colorization true if tty_code == 'not a tty'

# Variables that need to be globally available
time_now = Time.now
$date_time_now_log_fmttd = time_now.strftime(DATE_TIME_LOG_FORMAT)
$date_time_now_file_fmttd = time_now.strftime(DATE_TIME_APPEND_FORMAT)
$verbose = false
$npfile_count = 0


#-------------------------------------------------------------------------
# Helper Functions
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

#-------------------------------------------------------------------------
# Class definition: NPCalFile
#-------------------------------------------------------------------------
class NPCalFile
  # Define the attributes that need to be visible outside the class instances
  attr_reader :id, :media_header_line, :is_calendar, :is_updated, :filename, :line_count

  def initialize(date)
    # Create NPFile object from reading Calendar file of date YYYMMDD

    # Set the file's id
    $npfile_count += 1
    @id = $npfile_count
    @filename = "#{NP_CALENDAR_DIR}/#{date}.#{NOTE_EXT}"
    @lines = []
    @line_count = 0
    @title = date
    @is_updated = false

    begin
      log_message_screen(" Reading NPCalFile for '#{@title}'")

      # Open file and read in all lines (finding any Done and Cancelled headers)
      # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
      f = File.open(@filename, 'r', encoding: 'utf-8')
      n = 0
      f.each_line do |line|
        @lines[n] = line
        n += 1
      end
      f.close
      @line_count = @lines.size # e.g. for lines 0-2 size => 3
      log_message_screen(" -> Read NPCalFile for '#{@title}' using id #{@id}. #{@line_count} lines")
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} when re-writing note file #{@filename}")
    end
  end

  def insert_new_line(new_line, line_number)
    # Insert 'line' into position 'line_number'
    # NB: this is insertion at the line number, so that current line gets moved to be one later
    n = @line_count # start iterating from the end of the array
    line_number = n if line_number >= n # don't go beyond current size of @lines
    log_message_screen("  insert_new_line at #{line_number} (count=#{n}) ...")
    @lines.insert(line_number, new_line)
    @line_count = @lines.size
  end

  def append_line_to_section(new_line, section_heading)
    # Append new_line after 'section_heading' line.
    # If not found, then add 'section_heading' to the end first
    log_message_screen("  append_line_to_section for '#{section_heading}' ...")
    n = 0
    added = false
    found_section = false
    while !added && (n < @line_count)
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
    # log_message_screen("  section heading not found, so adding at line #{n}, #{@line_count}")
    insert_new_line(section_heading, n) unless found_section # if section not yet found then add it before this line
    insert_new_line(new_line, n + 1) unless added # if not added so far, then now append
  end

  def rewrite_cal_file
    # write out this updated calendar file
    main_message_screen("  > writing updated version of #{@filename}")
    # open file and write all the lines out
    begin
      File.open(@filename, 'w') do |f|
        @lines.each do |line|
          f.puts line
        end
      end
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} when re-writing calendar file #{filepath}")
    end
  end
end

#--------------------------------------------------------------------------------------
# SPOTIFY
#--------------------------------------------------------------------------------------
def process_spotify
  spotify_filepath = IFTTT_FILEPATH + SPOTIFY_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($spotify_test_data)
      f = $spotify_test_data
      log_message_screen("Using Spotify test data")
    elsif File.exist?(spotify_filepath)
      if File.empty?(spotify_filepath)
        warning_message_screen("Spotify file empty")
        throw :done
      else
        f = File.open(spotify_filepath, 'r', encoding: 'utf-8')
      end
    else
      warning_message_screen("No Spotify file found")
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split('|')
        log_message_screen(parts)
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        log_message_screen("  Found item to save with date #{date_YYYYMMDD}:")

        # Format line to add
        line_to_add = "- new #spotify fave **#{parts[1].strip}**'s [#{parts[2].strip}](#{parts[4].strip}) from album **#{parts[3].strip}** ![album art](#{parts[5].strip})"
        log_message_screen(line_to_add)

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_line_to_section(line_to_add, MEDIA_STRING)
        this_note.rewrite_cal_file
        main_message_screen("-> Saved new Spotify fave to #{date_YYYYMMDD}")
      end

      unless defined?($spotify_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{SPOTIFY_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(spotify_filepath, archive_filename)
      end
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} for file #{SPOTIFY_FILE}")
    end
  end
end

#--------------------------------------------------------------------------------------
# INSTAPAPER
#--------------------------------------------------------------------------------------
def process_instapaper
  instapaper_filepath = IFTTT_FILEPATH + INSTAPAPER_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($instapaper_test_data)
      f = $instapaper_test_data
      log_message_screen("Using Instapaper test data")
    elsif File.exist?(instapaper_filepath)
      if File.empty?(instapaper_filepath)
        warning_message_screen("Note: Instapaper file empty")
        throw :done
      else
        f = File.open(instapaper_filepath, 'r', encoding: 'utf-8')
      end
    else
      warning_message_screen("No Instapaper file found")
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split(" \\ ")
        # log_message_screen("  #{line} --> #{parts}")
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        log_message_screen("  Found item to save with date #{date_YYYYMMDD}:")

        # Format line to add. Guard against possible empty fields
        parts[2] = '' if parts[2].nil?
        parts[3] = '' if parts[3].nil?
        line_to_add = "- #article **[#{parts[1].strip}](#{parts[2].strip})** #{parts[3].strip}"
        log_message_screen(line_to_add)

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_line_to_section(line_to_add, MEDIA_STRING)
        this_note.rewrite_cal_file
        main_message_screen("-> Saved new Instapaper item to #{date_YYYYMMDD}")
      end

      unless defined?($instapaper_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{INSTAPAPER_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(instapaper_filepath, archive_filename)
      end
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} when processing file #{INSTAPAPER_FILE}")
    end
  end
end

#--------------------------------------------------------------------------------------
# MEDIUM articles
#--------------------------------------------------------------------------------------
def process_medium
  medium_filepath = IFTTT_FILEPATH + MEDIUM_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($medium_test_data)
      f = $medium_test_data
      log_message_screen("Using Medium test data")
    elsif File.exist?(medium_filepath)
      if File.empty?(medium_filepath)
        warning_message_screen("Note: Medium file empty")
        throw :done
      else
        f = File.open(medium_filepath, 'r', encoding: 'utf-8')
      end
    else
      warning_message_screen("No Medium file found")
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split(" \\ ")
        # log_message_screen("  #{line} --> #{parts}")
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        log_message_screen("  Found item to save with date #{date_YYYYMMDD}:")

        # Format line to add. Guard against possible empty fields
        parts[2] = '' if parts[2].nil?
        line_to_add = "- #article **[#{parts[1].strip}](#{parts[2].strip})**"
        log_message_screen(line_to_add)

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_line_to_section(line_to_add, MEDIA_STRING)
        this_note.rewrite_cal_file
        main_message_screen("-> Saved new Medium item to #{date_YYYYMMDD}")
      end

      unless defined?($medium_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{MEDIUM_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(medium_filepath, archive_filename)
      end
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} when processing file #{MEDIUM_FILE}")
    end
  end
end

#--------------------------------------------------------------------------------------
# TWITTER
#--------------------------------------------------------------------------------------
def process_twitter
  twitter_filepath = IFTTT_FILEPATH + TWITTER_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($twitter_test_data)
      f = $twitter_test_data
      log_message_screen("Using Twitter test data")
    elsif File.exist?(twitter_filepath)
      if File.empty?(twitter_filepath)
        warning_message_screen("Note: Twitter file empty")
        throw :done
      else
        f = File.open(twitter_filepath, 'r', encoding: 'utf-8')
      end
    else
      warning_message_screen("No Twitter file found")
      throw :done
    end

    begin
      needs_concatenating = false
      previous_line = ''
      f.each_line do |line|
        # Cope with tweets over several lines: concatenate with next line
        if needs_concatenating
          line = previous_line + line
          log_message_screen("  Concatenated -> '#{line}' with next")
          needs_concatenating = false
        end
        # Parse each line
        parts = line.split(" | ")
        # If we have less than 4 parts we'll need to join this into the next line
        if parts.size < 4
          needs_concatenating = true
          previous_line = line.strip # remove whitespace (including the probable newline on the end)
          log_message_screen("  Need to concatenate '#{line}' with next")
          next
        end
        # log_message_screen("  #{line} --> #{parts}")
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')

        log_message_screen("  Found item to save with date #{date_YYYYMMDD}:")

        # Format line to add
        line_to_add = "- @#{parts[2].strip} tweet: \"#{parts[1].strip}\" ([permalink](#{parts[3].strip}))"
        log_message_screen(line_to_add)

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_line_to_section(line_to_add, MEDIA_STRING)
        this_note.rewrite_cal_file
        main_message_screen("-> Saved new Twitter item to #{date_YYYYMMDD}")
        needs_concatenating = false
        previous_line = ''
      end

      unless defined?($twitter_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{TWITTER_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(twitter_filepath, archive_filename)
      end
    rescue StandardError => e
      error_message_screen("ERROR: #{e.exception.message} when processing file #{TWITTER_FILE}")
    end
  end
end

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "NotePlan media adder v#{VERSION}" # \nDetails at https://github.com/jgclark/NotePlan-tools/\nUsage: npMediaSave.rb [options]"
  opts.separator ''
  options[:instapaper] = false
  options[:medium] = false
  options[:spotify] = false
  options[:twitter] = false
  options[:verbose] = false
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
  opts.on('-i', '--instapaper', 'Add Instapaper records') do
    options[:instapaper] = true
  end
  opts.on('-m', '--medium', 'Add Medium records') do
    options[:medium] = true
  end
  opts.on('-s', '--spotify', 'Add Spotify records') do
    options[:spotify] = true
  end
  opts.on('-t', '--twitter', 'Add Twitter records') do
    options[:twitter] = true
  end
  opts.on('-v', '--verbose', 'Show information as I work') do
    $verbose = true
  end
end
opt_parser.parse! # parse out options, leaving file patterns to process

log_message_screen("Starting npSaveMedia at #{$date_time_now_log_fmttd}")
process_instapaper if options[:instapaper]
process_medium if options[:medium]
process_spotify if options[:spotify]
process_twitter if options[:twitter]
