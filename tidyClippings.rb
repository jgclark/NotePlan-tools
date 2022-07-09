#!/usr/bin/env ruby
#-------------------------------------------------------------------------------
# Script to tidy and clean up HTML text clipped into markdown files
# by Jonathan Clark, v1.3.x, 9.7.2022
#-------------------------------------------------------------------------------
# TODO: sort out what to do with no H1.
#-------------------------------------------------------------------------------
VERSION = "1.3.8"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html
require 'ostruct'

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
LIVE = false

NOTE_EXT = "md" # or "txt"
# FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Clips" # or ...
INPUT_FILEPATH = "/Users/jonathan/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
# ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive" # or ...
ARCHIVE_FILEPATH = "#{INPUT_FILEPATH}/tidyClippingsOriginals"
DATE_ISO_FORMAT = '%Y-%m-%d'.freeze
DATE_TIME_HUMAN_FORMAT = '%e %b %Y %H:%M'.freeze
DATE_TIME_LOG_FORMAT = '%Y%m%d%H%M'.freeze # only used in logging
IGNORE_SECTION_TITLES = ['IgnoreMe', 'New Resources', 'Menu', 'Archive', 'Meta', 'Subscribe', 'Past navigation', 'Shared', 'Share this', 'Share this post', 'How we use cookies', 'Skip to content', 'Like this', 'Leave a Reply', '_Related', 'Related Posts', 'Related Articles', 'More by this author', 'Ways to Follow', 'My recent publications', 'Other Publications', 'Publications', 'Follwers', 'Site Map', 'Solid Joys', 'Look at the Book', 'Join The Conversation', 'About Us', 'Follow Us', 'Events', 'Ministries', 'Blog Archive', 'Blogroll']

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
$date_now = time_now.strftime(DATE_ISO_FORMAT)
$verbose = false
$npfile_count = 0

#-------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------
def main_message(message)
  puts message.colorize(CompletedColour)
end

def info_message(message)
  puts message.colorize(InfoColour)
end

def error_message(message)
  puts message.colorize(ErrorColour)
end

def log_message(message)
  puts message if $verbose
end

def truncate_text(text, max_length = 100000, use_elipsis = false)
  raise ArgumentError, "max_length must be positive" unless max_length.positive?
  return '' if text.nil?

  return text if text.size <= max_length

  return text[0, max_length] + (use_elipsis ? '...' : '')
end

# simplify HTML and Markdown in the line we receive
def cleanup_line(line)
  orig_line = line

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
  line.gsub!(/%20/, " ")

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

  # replace opening '* ' with '- '
  line.gsub!(/^(\s*)\*\s/, '\1- ')

  # replace '## [' with '[' (Desiring God)
  line.gsub!(/## \[/, '[')

  # drop base64 image lines
  line = '' if line =~ /!\[\]\(data:image\/gif;base64/

  # Remove some lines which aren't interesting
  line = '' if line =~ /^Previous article/i || line =~ /^Next article/i
  line = '' if line =~ /^\[Share\]/i
  line = '' if line =~ /^\\-\s*$/
  line = '' if line =~ /^\*\*Comments policy:\*\*/
  line = '' if line == "#popclipped"
  line = '' if line == "#clipped"
  line = '' if line == "[Donate](/donate)"
  line = '' if line == "Submit"
  line = '' if line == "[News & Updates](/posts)"

  # replace a line just surrounded by **...** with an H4 instead
  line.gsub!(/^\s*\*\*(.*)\*\*\s*$/, '#### \1')

  # replace odd things in Stocki '**_ ... _**' with simpler '_..._'
  # (needs to come after **...** test above)
  line.gsub!(/\*\*_/, '_')
  line.gsub!(/_\*\*/, '_')

  # replace asterisk lists with dash lists (to stop NP thinking they are tasks)
  line.gsub!(/^(\s*)\*\s/, '\1- ')

  # replace line starting ' - ####' with just heading markers
  line.gsub!(/^\s*\-\s+####\s+/, '#### ')

  # trim the end of the line
  line.rstrip!

  # write out if changed
  log_message("    cl-> #{line}") if orig_line != line

  return line
end

def help_identify_sections(line)
  orig_line = line
  # Fix headings that are missing heading markers
  line = '#Menu' if line =~ /^# Menu/i
  line = '## Join the Conversation' if line =~ /^Join the Conversation$/i
  line = '## About Us' if line =~ /^# ABOUT US/i
  line = '## Follow Us' if line =~ /^FOLLOW US$/i

  # Change some heading levels
  line = '### Labels' if line =~ /^## Labels$/i

  # Ignore sections without heading text
  line = '## IgnoreMe' if line =~ /^#+\s*$/

  # log if changed
  log_message("    his-> #{line}") if orig_line != line

  return line
end

def help_identify_metadata(line)
  orig_line = line

  # wordpress possible way of detecting source URL
  line.gsub!(/^\[Leave a comment\]\((.*?)\/#respond\)/, 'poss_source: \1')

  # wordpress possible way of detecting author
  line = 'poss_author: ' + line if line =~ /^\[.*\]\(.*\/author\/.+\)/

  # wordpress possible way of detecting publish date
  line = 'poss_date: ' + line if line =~ /\[.*\]\(.*\/\d{4}\/\d{2}\/\d{2}\/\)/

  # DesiringGod.org specifics
  # line = "site: https://www.desiringgod.org/" if line =~ /\/about-us/

  # blogspot.com specifics
  line.gsub!('# ', 'site: ') if line =~ /^#\s.*\(https:\/\/.*\.blogspot\.com\// # first H1 is site title not post title

  # Psephizo specifics
  line = "author: Ian Paul" if line == "scholarship. serving. ministry." # not always correct, but typically not given if there isn't a guest author
  # line = "site: www.psephizo.com" if line == "[ Psephizo ](https://www.psephizo.com/)" # covered by later [Home](...)
  line = '## ' + line if line =~ /^Categories .*https:\/\/www.psephizo.com\//
  # TODO: decide if it's OK to change some comment lines in Psephizo that are [...](https://www.psephizo.com/life-ministry/why-does-embracing-justice-matter/...) -- ie source

  # log if changed
  log_message("    him-> #{line}") if orig_line != line

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
  main_message("Starting to tidy web clippings for #{glob_pattern} at #{$date_time_now_human_fmttd}.")
  Dir.glob(glob_pattern).each do |this_file|
    main_message("- file '#{this_file}'")

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
      # log_message(" #{n}: #{line_in}")
      lines[n] = line

      # Fix all sorts of things in the line
      line = cleanup_line(line)
      # Tweak lines to standardise section headings etc.
      line = help_identify_sections(line)
      # See what we can do to help identify metadata, and change accordingly
      line = help_identify_metadata(line)

      if line != line_in
        # log_message(" #{n}~ #{line}")
        lines[n] = line
      end

      n += 1
    end
    f.close
    info_message("  After first pass, #{n} lines")

    last_line = ""
    ignore_before = 0
    ignore_after = 99999
    ignore_this_section = false
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
      if line =~ /^#\s/ && line !~ /#{re_ignore_sections}/i
        # this is the first H1 so use this as a title and starting line
        if ignore_before.zero?
          ignore_before = n
          line.scan(/^#\s+(.*)/) { |m| title = m.join }
          info_message("   #{n}: found title (from H1): '#{title}'")
        else
          # this is a subsequent H1 then probably ignore after this
          ignore_after = n - 1
          this_heading = '' # needed to access variable set in following loop
          line.scan(/^#\s+(.*)/) { |m| this_heading = m.join }
          info_message("   #{n}: found subsequent H1: ignore after this '#{this_heading}'")
        end
      end

      # If a new section, should we ignore it?
      if line =~ /^#+\s+/
        last_heading_level = this_heading_level
        this_heading_level = line.index(' ') # = how many chars before first space?
        if line =~ /#{re_ignore_sections}/i
          log_message("   #{n}: will ignore new section '#{line}'")
          ignore_this_section = true
        elsif this_heading_level <= last_heading_level
          log_message("   #{n}: new section '#{line}' #{this_heading_level} (<= #{last_heading_level}) stopping ignore")
          ignore_this_section = false
        else
          log_message("   #{n}: new section '#{line}' #{this_heading_level} (> #{last_heading_level}) : ignore_this_section = #{ignore_this_section}")
        end
      end

      # if this is the Comments section then ignore after this (unless we already have found an ignore point)
      if line =~ /^#+\s+(No comments|Comments|\d*\s*Comments on\s|\d*\s*thoughts on\s)/i && ignore_after == 99999
        ignore_after = n - 1
        ignore_this_section = true
        info_message("#{n}: found Comments section: will ignore after line #{n}")
      end

      if ignore_this_section || n > ignore_after # TODO: test me
        # We're in an ignore section, so blank this line
        # log_message("   #{n}/#{lines.size}: ignored") if n < 250
        last_line = line
        lines[n] = ""
        line = ""

      else
        log_message("     #{n}: #{truncate_text(line, 70, true)}") if n < 100

        # insert blank line before heading
        # if !last_line.empty? && line =~ /^#+\s+/
        #   log_message(" #{n}   inserted: empty line before heading '#{line}'")
        #   lines.insert(n, "")
        #   last_line = ""
        #   n -= 1
        #   redo # i.e. redo this particular line, now that we've added the blank line
        # end

        # remove blank line after heading
        # if last_line =~ /^#+\s+/ && line.empty?
        #   log_message(" #{n}   removed: empty line after heading '#{last_line}'")
        #   last_line = line
        #   line = ""
        #   lines.delete_at(n)
        #   max_lines -= 1
        #   n += 1
        #   next
        # end

        #-----------------------------------------------------------
        # save out any other metadata we can spot
        # [...](../authors?/..)
        if line =~ /\[[^\]]*?\]\([^)]*?\/authors?\/.*?\)/i
          line.scan(/\[([^\]]*?)\]\([^)]*?\/authors?\/.*?\)/i) { |m| poss_author = m.join }
          info_message(" #{n}: found poss_author/1: #{poss_author}")
        end
        # 'by|© X Y' but not 2022 (or too long, as a random line starting 'By ...')
        if line =~ /^[\s*-]*(?:by|©):?\s*[^\d]{4}.*/i && line.size < 40
          line.scan(/^[\s*-]*(?:by|©):?\s*([^\d]{4}.*)/i) { |m| author = m.join } # .join turns ['a'] to 'a'
          info_message(" #{n}: found author/1: #{author}")
        end
        # 'by [X Y](...)'
        if line =~ /^\s*by[:\s]+\[.+\]/i
          line.scan(/^\s*by[:\s]+\[(.+)\]/i) { |m| author = m.join } # .join turns ['a'] to 'a'
          info_message(" #{n}: found author/2: #{author}")
        end
        # ... blogger.com/profile ... at ...
        if line =~ /https:\/\/www\.blogger\.com\/profile\/.*\s*at\s*.*?https:\/\/[^\)\s$]+/ 
          line.scan(/\[([^\]]+)\].*\s*at\s*.*?(https:\/\/[^\)\s$]+)/) do |m|
            poss_author = m[0]
            source = m[1]
          end
          info_message(" #{n}: found poss_author/2: #{poss_author}")
          info_message(" #{n}: found source/1: #{source}")
        end
        # Posted by ... at ...
        if line =~ /Posted\sby\s*.*\s*at\s*.*?(https:\/\/[^\)\s$]+)/ # 
          line.scan(/Posted\sby\s*(.*)\s*at\s*.*?(https:\/\/[^\)\s$]+)/) do |m|
            poss_author = m[0]
            source = m[1]
          end
          info_message(" #{n}: found poss_author/3: #{poss_author}")
          info_message(" #{n}: found source/2: #{source}")
        end
        # /category/...)    TODO: align with /label/ and /tag/ below?
        if line =~ /\/category\/.*?\//i
          line.scan(/\/category\/([^\/]+)\//i) { |m| tags << m.join }
          info_message(" #{n}: found tags (from category): #{tags}")
        end
        # /label/...)
        if line =~ /\/label\/[^\)\/]+[\)\/]/i
          line.scan(/\/label\/([^\)\/]+)[\)\/]/i) { |m| tags << m.join }
          info_message(" #{n}: found tags (from label): #{tags}")
        end
        # /tag/...)
        if line =~ /\/tag\/[^\)\/]+[\)\/]/i
          line.scan(/\/tag\/([^\)\/]+)[\)\/]/i) { |m| tags << m.join }
          info_message(" #{n}: found tags: #{tags}")
        end
        if line =~ /https:\/\/[^\/]+\/wp-content\//
          line.scan(/(https:\/\/[^\/]+)\/wp-content\//) { |m| site = m.join }
          info_message(" #{n}: found site/1: #{site}")
        end
        # [Home](...)
        if line =~ /[^!]\[Home\]\(.*\)/i # TODO: test me
          line.scan(/\[Home\]\((.*)\)/i) { |m| site = m.join}
          info_message(" #{n}: found site/2: #{site}")
        end
        # [View web version](...)
        if line =~ /^\[View web version\]\(.+\)/i
          line.scan(/^\[View web version\]\((.+)\)/i) { |m| source = m.join }
          info_message(" #{n}: found source/3: #{source}")
        end
        # https://www.facebook.com/sharer/sharer.php?u=...
        if line =~ /https:\/\/www\.facebook\.com\/sharer\/sharer\.php\?u=.+\)/i
          line.scan(/https:\/\/www\.facebook\.com\/sharer\/sharer\.php\?u=(.+)\)/i) { |m| source = m.join }
          info_message(" #{n}: found source/4: #{source}")
        end
        # [Leave a comment](.../#respond)
        if line =~ /\[Leave a Comment\]\([^)]+?\/#respond\)/i
          line.scan(/\[Leave a Comment\]\(([^)]+)\/#respond\)/i) { |m| source = m.join }
          info_message(" #{n}: found source/5: #{source}")
        end

        #-----------------------------------------------------------
        # save any already fielded metadata
        # (after the previous set to give higher priority to its results)
        if line =~ /^\s*title[:\s]+.+/i # TODO: finish me
          line.scan(/^\s*title[:\s]+(.*)/i) { |m| title = m.join }
          info_message(" #{n}: found title: #{title}")
        end
        if line =~ /^\s*date[:\s]+.+/i
          line.scan(/\s*date[:\s]+(.*)/i) { |m| doc_date = m.join }
          info_message(" #{n}: found date: #{doc_date}")
        end
        if line =~ /^\s*poss_date[:\s]+.+/i
          line.scan(/\s*poss_date[:\s]+(.*)/) { |m| poss_date = m.join }
          info_message(" #{n}: found poss_date: #{poss_date}")
        end
        if line =~ /^\s*(author|by):\s*.+/i
          line.scan(/^\s*(?:author|by):\s*(.+)/i) { |m| author = m.join }
          info_message(" #{n}: found author: #{author}")
        end
        if line =~ /^\s*poss_author[:\s]+.+/i
          line.scan(/^\s*poss_author[:\s]+(.*)/i) { |m| poss_author = m.join }
          info_message(" #{n}: found poss_author: #{poss_author}")
        end
        if line =~ /^\s*tags?[:\s]+.+/i # tag: field etc.
          line.scan(/^Tags?[:\s]+\[?([^\]]+)/i) { |m| tags << m.join } # add to array, having first turned ['a'] to 'a'
          info_message(" #{n}: found tags: #{tags}")
        end
        if line =~ /^\s*(category|categories)[:\s]+/i # category: field etc.
          line.scan(/^\s*(?:category|categories)[:\s]+\[?([^\]]+)/i) { |m| tags << m.join } # ?: stops first (...) being a capturing group
          info_message(" #{n}: found tags (from category field): #{tags}")
        end
        if line =~ /^site:\s+.+/i # TODO: test me
          line.scan(/^site:\s+(.*)/i) { |m| site = m.join}
          info_message(" #{n}: found site: #{site}")
        end
        if line =~ /^poss_source:\s+.+/i
          line.scan(/^poss_source:\s+(.*)/i) { |m| poss_source = m.join }
          info_message(" #{n}: found poss_source: #{poss_source}")
        end

        #-----------------------------------------------------------
        # try just parsing line for a valid date string
        begin
          # look for at least "...4.3.22..." or "4 Mar 22"
          # or one of the month names
          if !line.nil? && (line.count('0-9') >= 3 || line =~ /(^|\s)(Jan(uary)?|Feb(uary)?|Mar(ch)?|Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|Sep(tember)?|Oct(ober)?|Nov(ember)?|Dec(ember)?)\s/)
            trunc_text = truncate_text(line, 125) # function's limit is 128, but it seems to need fewer than that
            line_date = Date.parse(trunc_text).to_s
            # only keep if it's before or equal to today
            if line_date < $date_now
              poss_date = line_date
              info_message(" #{n}: found poss date: #{poss_date} from '#{truncate_text(line, 30)}'")
            end
          end
        rescue Date::Error => e
          # log_message("didn't like that: #{e}")
        end
      end # if in ignore_section

      last_line = line
    end # for each line
    info_message("  After second pass, #{lines.size} lines left")
    log_message("  Will ignore before l.#{ignore_before} & after l.#{ignore_after}")

    #-------------------------------------------------------------------------
    # Form the frontmatter section
    #-------------------------------------------------------------------------
    fm_title = title || ""
    fm_author = author || poss_author || ""
    fm_clip_date = clip_date || $date_time_now_log_fmttd # fallback to current date
    fm_doc_date = doc_date || poss_date || "?"
    fm_tags = tags.join(', ') || ""
    fm_source = source || poss_source || site || ""
    fm_generated = "#{$date_time_now_log_fmttd} by tidyClippings v#{VERSION}"
    frontmatter = "---\ntitle: #{fm_title}\nauthor: #{fm_author}\ndate: #{fm_doc_date}\nclipped: #{fm_clip_date}\ntags: [#{fm_tags}]\nsource: #{fm_source}\ngenerated: #{fm_generated}\n---\n\n"

    info_message(frontmatter)

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
    main_message("  -> written updated version to '#{new_filename}'")

    # Now rename file to same as above but _YYYYMMDDHHMM on the end
    archive_filename = "#{ARCHIVE_FILEPATH}/#{this_file}"
    File.rename(this_file, archive_filename) if LIVE

    break # TODO: remove me
  end # second pass
rescue SystemCallError => e
  error_message("ERROR: on rename? #{e.exception.full_message}")
rescue StandardError => e
  error_message("ERROR: #{e.exception.full_message}")
end
