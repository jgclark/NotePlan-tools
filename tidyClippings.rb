#!/usr/bin/env ruby
#-------------------------------------------------------------------------------
# Script to tidy and clean up HTML text clipped into markdown files
# by Jonathan Clark, v1.3.1, 23.6.2022
# Tested with a number of files from
# - desiringgod.org
# - wordpress.com/mbarrettdavie
#-------------------------------------------------------------------------------
VERSION = "1.3.1"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html
require 'ostruct'

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
LIVE = true

NOTE_EXT = "md" # or "txt"
# FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Clips" # or ...
INPUT_FILEPATH = "/Users/jonathan/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
# ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive" # or ...
ARCHIVE_FILEPATH = "#{INPUT_FILEPATH}/tidyClippingsOriginals"
DATE_TIME_HUMAN_FORMAT = '%e %b %Y %H:%M'.freeze
DATE_TIME_LOG_FORMAT = '%Y%m%d%H%M'.freeze # only used in logging
IGNORE_SECTION_TITLES = ['New Resources', 'Menu', 'Archive', 'Meta', 'Past navigation', 'Shared', 'Share this', 'Share this post', 'How we use cookies', 'Skip to content', 'Like this', 'Leave a Reply', '_Related', 'Related Posts', 'More by this author', 'Ways to Follow', 'My recent publications', 'Other Publications']

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

def truncate_text(text, max_length = 100000, use_elipsis = false)
  raise ArgumentError, "max_length must be positive" unless max_length.positive?

  return text if text.size <= max_length

  return text[0, max_length] + (use_elipsis ? '...' : '')
end

def cleanup_line(line)
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

  # replace '## [' with '[' (Desiring God)
  line.gsub!(/## \[/, '[')

  # drop base64 image lines
  line = '' if line =~ /!\[\]\(data:image\/gif;base64/

  # replace odd things in Stocki '**_ ... _**' with simpler '_..._'
  line.gsub!(/\*\*_/, '_')
  line.gsub!(/_\*\*/, '_')

  # drop #clipped or #popclipped tags that are the whole of a line
  line = '' if line =~ /^#popclipped$/i || line =~ /^#clipped$/i

  # replace a line just surrounded by **...** with an H4 instead
  line.gsub!(/^\s*\*\*(.*)\*\*\s*$/, '#### \1')

  # replace asterisk lists with dash lists (to stop NP thinking they are tasks)
  line.gsub!(/^(\s*)\*\s/, '\1- ')

  # trim the end of the line
  line.rstrip!
  return line
end

def help_identify_metadata(line)
  # change '# Menu' to '#Menu' to allow us to read following section for possible metadata
  line = '#Menu' if line =~ /^# Menu/

  # wordpress possible way of detecting source URL
  line.gsub!(/^\[Leave a comment\]\((.*?)\/#respond\)/, 'poss_source: \1')

  # wordpress possible way of detecting author
  line = 'poss_author: ' + line if line =~ /^\[.*\]\(.*\/author\/.+\)/

  # wordpress possible way of detecting publish date
  line = 'poss_date: ' + line if line =~ /\[.*\]\(.*\/\d{4}\/\d{2}\/\d{2}\/\)/

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
  Dir.chdir(INPUT_FILEPATH)
  glob_pattern = ARGV.count.positive? ? '*' + ARGV[0] + '*.txt' : '*.txt'
  main_message_screen("Starting to tidy web clippings for #{glob_pattern} at #{$date_time_now_human_fmttd}.")
  Dir.glob(glob_pattern).each do |this_file|
    main_message_screen("- file '#{this_file}'")

    # initialise other variables (that don't need to persist with the class)
    lines = []
    author = nil
    poss_author = nil
    doc_date = nil
    clip_date = File.birthtime(this_file) # = creation date (when it arrives in my filesystem)
    poss_date = nil
    site = nil
    tags = []
    title = nil
    source = nil
    poss_source = nil

    # Open file and read in all lines -- the first pass
    # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
    n = 0
    f = File.open(this_file, 'r', encoding: 'utf-8')
    f.each_line do |line|
      line_in = line.clone.rstrip  # needs a proper clone, not just a reference
      # log_message_screen(" #{n}: #{line_in}")
      lines[n] = line

      # Fix all sorts of things in the line
      line = cleanup_line(line)

      # See what we can do to help identify metadata, and change accordingly
      line = help_identify_metadata(line)

      if line != line_in
        # log_message_screen(" #{n}: #{line_in}\n   -> #{line}")
        lines[n] = line
      end

      n += 1
    end
    f.close
    info_message_screen("  After first pass, #{n} lines")

    last_line = ""
    ignore_before = 0
    ignore_after = 99999
    ignore_this_section = true
    last_heading_level = 6 # start low
    this_heading_level = 6 # start low
    re_ignore_sections = "^#+\\s+(#{IGNORE_SECTION_TITLES.join('|')})" # lines that start with MD headings then any of those sections
    n = -1 # line number in lines array
    max_lines = lines.size # need to track this; for some reason testing for lines.size in the while loop doesn't work

    # Go through lines again
    while n < max_lines
      n += 1
      line = lines[n]
      # first check for H1 lines (that shouldn't be ignored)
      if line =~ /^#\s/ && line !~ /#{re_ignore_sections}/
        # this is the first H1 so use this as a title and starting line
        if ignore_before.zero?
          ignore_before = n
          line.scan(/^#\s+(.*)/) { |m| title = m.join }
          info_message_screen("   #{n}: found title (from H1): '#{title}'")
        else
          # this is a subsequent H1 then probably ignore after this
          ignore_after = n - 1
          this_heading = '' # needed to access variable set in following loop
          line.scan(/^#\s+(.*)/) { |m| this_heading = m.join }
          info_message_screen("   #{n}: found subsequent H1: ignore after this '#{this_heading}'")
        end
      end

      # if this is the Comments section then ignore after this (unless we already have found an ignore point)
      if line =~ /^\s*\d*\s*Comments/ && ignore_after.zero?
        ignore_after = n - 1
        info_message_screen("   #{n}: found comments: will ignore after line #{n}")
      end

      # If a new section, should we ignore it?
      if line =~ /^#+\s+/
        last_heading_level = this_heading_level
        this_heading_level = line.index(' ')
        if line =~ /#{re_ignore_sections}/
          log_message_screen("   #{n}: will ignore new section '#{line}'")
          ignore_this_section = true
        elsif this_heading_level <= last_heading_level
          log_message_screen("   #{n}: new section '#{line}' #{this_heading_level} (<= #{last_heading_level}) stopping ignore")
          ignore_this_section = false
        else
          log_message_screen("   #{n}: new section '#{line}' #{this_heading_level} (> #{last_heading_level})")
        end
      end

      if ignore_this_section
        # We're in an ignore section, so blank this line
        # log_message_screen("   #{n}/#{lines.size}: ignored")
        last_line = line
        lines[n] = ""
        line = ""

      else
        # log_message_screen("     #{n}: #{truncate_text(line, 60, true)}") if n < 100

        # insert blank line before heading
        if !last_line.empty? && line =~ /^#+\s+/
          # log_message_screen(" #{n}   inserted: empty line before heading '#{line}'")
          lines.insert(n, "")
          last_line = ""
          n -= 1
          redo # i.e. redo this particular line, now that we've added the blank line
        end

        # remove blank line after heading
        if last_line =~ /^#+\s+/ && line.empty?
          # log_message_screen(" #{n}   removed: empty line after heading '#{last_line}'")
          last_line = line
          line = ""
          lines.delete_at(n)
          max_lines -= 1
          n += 1
          next
        end

        # save out some fields if we spot them
        if line =~ /^\s*title[:\s]+.+/i # TODO: finish me
          line.scan(/^\s*title[:\s]+(.*)/i) { |m| title = m.join }
          info_message_screen(" found title: #{title}")
        end
        if line =~ /^\s*date[:\s]+.+/i
          line.scan(/\s*date[:\s]+(.*)/i) { |m| doc_date = m.join }
          info_message_screen(" found date: #{doc_date}")
        end
        if line =~ /^\s*poss_date[:\s]+.+/i
          line.scan(/\s*poss_date[:\s]+(.*)/) { |m| poss_date = m.join }
          info_message_screen(" found poss_date: #{poss_date}")
        end
        if line =~ /^\s*author[:\s]+.+/i # TODO: test me
          line.scan(/^\s*author[:\s]+(.*)/i) { |m| author = m.join }
          info_message_screen(" found author: #{author}")
        end
        if line =~ /^\s*poss_author[:\s]+.+/i
          line.scan(/^\s*poss_author[:\s]+(.*)/i) { |m| poss_author = m.join }
          info_message_screen(" found poss_author: #{poss_author}")
        end
        if line =~ /^\s*by[:\s]+.+/i # TODO: test me
          line.scan(/^\s*by[:\s]+(.*)/i) { |m| author = m.join } # .join turns ['a'] to 'a'
          info_message_screen(" found author: #{author}")
        end
        if line =~ /^\s*tags?[:\s]+.+/i
          line.scan(/^Tags?[:\s]+\[?([^\]]+)/i) { |m| tags << m.join } # add to array, having first turned ['a'] to 'a'
          info_message_screen(" found tags: #{tags}")
        end
        if line =~ /^\s*(category|categories)[:\s]+/i
          line.scan(/^\s*(?:category|categories)[:\s]+\[?([^\]]+)/i) { |m| tags << m.join } # ?: stops first (...) being a capturing group
          info_message_screen(" found tags (from category field): #{tags}")
        end
        if line =~ /\/category\/.*?\//i
          line.scan(/\/category\/([^\/]+)\//i) { |m| tags << m.join }
          info_message_screen(" found tags (from categories): #{tags}")
        end
        if line =~ /^site:\s+.+/i # TODO: test me
          line.scan(/^site:\s+(.*)/i) { |m| site = m.join}
          info_message_screen(" found site: #{site}")
        end
        if line =~ /^poss_source:\s+.+/i
          line.scan(/^poss_source:\s+(.*)/i) { |m| poss_source = m.join }
          info_message_screen(" found poss_source: #{poss_source}")
        end

        # try just parsing line for a valid date string
        begin
          if poss_date.nil?
            poss_date = Date.parse(truncate_text(line, 24))
            info_message_screen(" found poss date: #{poss_date}")
          end
        rescue Date::Error => e
          # log_message_screen("didn't like that: #{e}")
        end
      end
      # TODO: cope with this! Tags: [BBC Radio 4](https://nickbaines.wordpress.com/tag/bbc-radio-4/), [hope](https://nickbaines.wordpress.com/tag/hope/), [Jeremiah](https://nickbaines.wordpress.com/tag/jeremiah/), [Leonard Cohen](https://nickbaines.wordpress.com/tag/leonard-cohen/), [Today](https://nickbaines.wordpress.com/tag/today/), [Ukraine](https://nickbaines.wordpress.com/tag/ukraine/)

      last_line = line
    end
    info_message_screen("  After second pass, #{lines.size} lines left")
    log_message_screen("  Will ignore before/after = #{ignore_before} / #{ignore_after}")

    #-------------------------------------------------------------------------
    # Form the frontmatter section
    #-------------------------------------------------------------------------
    fm_title = title || ""
    fm_author = author || poss_author || ""
    fm_clip_date = clip_date || $date_time_now_log_fmttd # fallback to current date
    fm_doc_date = doc_date || poss_date || "?"
    pp tags
    fm_tags = tags.join(', ') || ""
    fm_source = source || poss_source || site || ""
    fm_generated = "#{$date_time_now_log_fmttd} by tidyClippings v#{VERSION}"
    frontmatter = "---\ntitle: #{fm_title}\nauthor: #{fm_author}\ndate: #{fm_doc_date}\nclipped: #{fm_clip_date}\ntags: [#{fm_tags}]\nsource: #{fm_source}\ngenerated: #{fm_generated}\n---\n\n"

    info_message_screen(frontmatter)

    #-------------------------------------------------------------------------
    # write out this updated file, as a markdown file, with frontmatter prepended
    #-------------------------------------------------------------------------
    Dir.chdir('/tmp') unless LIVE

    # first simplify filename itself
    new_filename = "#{cleanup_line(this_file[0..-5]).lstrip}.#{NOTE_EXT}" # take off .txt and put on .md

    # open file and write all the lines out,
    # though ignoring any before the 'ignore_before' line, and after the 'ignore_after' line
    # also only write out 1 empty line in a row
    # file mode 'w' = write-only, truncates existing file
    last_fl = ""
    File.open(new_filename, 'w') do |ff|
      ff.puts frontmatter
      n = 0
      lines.each do |fl|
        ff.puts fl if n >= ignore_before && n <= ignore_after && !(last_fl.empty? && fl.empty?)
        n += 1
        last_fl = fl
      end
    end
    main_message_screen("  -> written updated version to '#{new_filename}'")

    # Now rename file to same as above but _YYYYMMDDHHMM on the end
    archive_filename = "#{ARCHIVE_FILEPATH}/#{this_file}"
    File.rename(this_file, archive_filename) if LIVE

    break # TODO: remove me
  end
rescue SystemCallError => e
  error_message_screen("ERROR: on rename? #{e.exception.full_message}")
rescue StandardError => e
  error_message_screen("ERROR: #{e.exception.full_message}")
end
