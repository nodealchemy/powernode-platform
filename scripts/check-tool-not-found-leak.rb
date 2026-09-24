#!/usr/bin/env ruby
# frozen_string_literal: true

# Analysis pass for check-tool-not-found-leak.sh (IMP-f6f80b585b19). See that
# script's header for the full rationale and the by-design misses it does not
# try to catch; this file is the regex/clause-boundary logic, kept in Ruby
# rather than awk because this repo's default `awk` is mawk, which silently
# drops `\s`/`\w`/`\b` support.
#
# Usage: ruby check-tool-not-found-leak.rb <file.rb> [<file.rb> ...]
# Prints one "LEAK: ..." line per hit to stdout, plus a summary if any hits
# were found. Exit status 1 if any hit, 0 otherwise.

# Anchored to the start of the line (after only leading whitespace) so a
# COMMENT or STRING LITERAL that merely mentions "rescue
# ActiveRecord::RecordNotFound" is never mistaken for a real rescue clause —
# review round 2's r2_comment_swallow/r2_string_start fixtures. Deliberately
# does NOT require the class name on this same line: review round 3 found
# five real sites in this codebase (a different exception, same STYLE) using
# a MULTI-LINE class list, so the class name search below joins continuation
# lines first — see MAX_HEADER_LINES.
RESCUE_START = /\A[ \t]*rescue\b/.freeze
RECORD_NOT_FOUND = /\bActiveRecord::RecordNotFound\b/.freeze
CAPTURED_VAR = /=>\s*(\w+)/.freeze
CLAUSE_BOUNDARY = /\A[ \t]*(rescue|ensure|end)\b/.freeze
LOGGER_LINE = /logger/i.freeze
# A line that ALSO produces the tool's return value must still be checked
# even if it mentions "logger" (e.g. `Rails.logger.info(...); return
# error_result(e.message)`, r2_logger_mixed) — only a line that is PURELY
# logging is skipped. Covers both the named result-builder methods and a
# literal error hash (`{ success: false, error: e.message }`, r3_logger_error)
# a tool can return directly instead of going through one of those methods.
OUTPUT_CALL = /\b(?:error_result|rescued_error_result|not_found_result)\b|\berror:|success:\s*false\b/.freeze
# A rescue class list rarely runs more than a handful of lines; this bounds
# the join loop against a malformed/never-closing file.
MAX_HEADER_LINES = 10

# Strips a trailing `# comment` for the "does this line end in a
# continuation comma" check. A heuristic, like the rest of this script — a
# literal `#` inside a string on the SAME line as a real comma could in
# principle confuse it, but no rescue class list in this codebase does that.
def strip_trailing_comment(line)
  # No `\z` anchor: `.` already excludes the trailing newline `readlines`
  # leaves on every line, so anchoring on absolute string-end would require
  # matching THROUGH that newline and never match at all.
  line.sub(/#.*/, "")
end

hits = []

ARGV.each do |file|
  lines = File.readlines(file)
  i = 0
  while i < lines.length
    line = lines[i]

    unless line =~ RESCUE_START
      i += 1
      next
    end

    indent = line[/\A[ \t]*/].length

    # The rescue header: just this line, UNLESS it (ignoring a trailing
    # comment) ends in `,` — a multi-line class list — in which case join
    # every following line up to and including the one containing `=>`
    # (review round 3's r3_multiline_list / r3_hash_before).
    header_lines = [line]
    if strip_trailing_comment(line).rstrip.end_with?(",")
      cursor = i + 1
      joined = 0
      while cursor < lines.length && joined < MAX_HEADER_LINES
        header_lines << lines[cursor]
        joined += 1
        has_arrow = lines[cursor].include?("=>")
        cursor += 1
        break if has_arrow
      end
    end
    header_end = i + header_lines.length - 1
    header_text = header_lines.join

    unless header_text =~ RECORD_NOT_FOUND
      i += 1
      next
    end

    var = header_text[CAPTURED_VAR, 1]

    # Collect the clause body: the header lines themselves (a same-line
    # `then ...` body, or one on the `=>` line of a multi-line list, lives
    # here too), through subsequent lines, stopping only at a
    # rescue/ensure/end line indented at or below the rescue line's own
    # indentation — so an inner if/case/block `end` (indented MORE) can't
    # close the scan early.
    clause = header_lines.dup
    j = header_end + 1
    while j < lines.length
      l = lines[j]
      l_indent = l[/\A[ \t]*/].length
      break if l =~ CLAUSE_BOUNDARY && l_indent <= indent

      clause << l
      j += 1
    end

    if var
      re_var = Regexp.escape(var)
      leak_re = /\b#{re_var}\.(?:message|to_s|full_message|inspect|detailed_message)\b|#\{\s*#{re_var}\s*\}/
      clause.each_with_index do |cl, offset|
        next if cl =~ LOGGER_LINE && cl !~ OUTPUT_CALL
        next unless cl =~ leak_re

        hits << "#{file}:#{i + 1 + offset}"
        break
      end
    end

    # Advance by exactly one line, not to the clause's own closing boundary
    # (`j`): a clause NESTED inside this one's body (review round 2's
    # r2_nested_var — an inner `rescue ActiveRecord::RecordNotFound => err`
    # whose own indent is deeper, so it never closes the OUTER clause) is
    # itself a rescue-start line and must get its own independent scan, or
    # its leak is invisible under the outer clause's different captured
    # variable. Revisiting lines already folded into an outer clause's body
    # can double-report the SAME leak line under two different clause
    # starts, which is why hits are deduped below.
    i += 1
  end
end

hits.uniq!

if hits.any?
  hits.each do |h|
    puts "LEAK: #{h} — rescue ActiveRecord::RecordNotFound forwards the exception's own message " \
         "(use Ai::Tools::BaseTool#not_found_result(e) instead)"
  end
  puts ""
  puts "Found #{hits.size} hit(s)."
  puts "Fix: route the rescue through Ai::Tools::BaseTool#not_found_result(e)."
  exit 1
end

exit 0
