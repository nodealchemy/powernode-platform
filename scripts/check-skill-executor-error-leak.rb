#!/usr/bin/env ruby
# frozen_string_literal: true

# Analysis pass for check-skill-executor-error-leak.sh (IMP-8552945f2672).
# See that script's header for the full rationale and scope. Structurally
# mirrors check-tool-not-found-leak.rb (same clause-boundary/indent logic,
# same reason it's Ruby and not awk — this repo's default awk is mawk, which
# silently drops \s/\w/\b support), generalized from "RecordNotFound only" to
# "any exception class this class hierarchy does not explicitly whitelist".
#
# STATEMENT-LEVEL, not line-level (review round 2, IMP-8552945f2672): the
# leak-shape check operates on the rescue clause's text with comments, logger
# lines and array-PUSH STATEMENTS stripped out — not on individual lines —
# so it catches:
#   - a `failure(...)` call, or an `error:`/`"error" =>` hash value, that
#     spans MULTIPLE lines (a long interpolated string, a multi-line hash);
#   - a local re-assigned from the caught variable's message
#     (`msg = e.message` ... `failure(msg)`), tracked as a tainted alias;
#   - `errors << {...}; return failure(e.message)` in the SAME clause — only
#     the push STATEMENT is excluded, not the whole clause, so a direct
#     return sitting next to an (out-of-scope) push is still flagged.
#
# Usage: ruby check-skill-executor-error-leak.rb <file.rb> [<file.rb> ...]

RESCUE_START = /\A[ \t]*rescue\b/.freeze
CAPTURED_VAR = /=>\s*(\w+)/.freeze
CLAUSE_BOUNDARY = /\A[ \t]*(rescue|ensure|end)\b/.freeze
LOGGER_LINE = /logger/i.freeze
MAX_HEADER_LINES = 10

# A DIRECT caller-facing return: `failure(...)` (BaseSkillExecutor's own
# builder) or any `failure_*(...)` sibling a subclass authors on top of it
# (sdwan_ipfix_collector_compose_executor.rb's `failure_with_partial` puts its
# message into data.failures[].error of a success:true result — review round
# 3), or a bare `{ ..., success: ..., ... }` / `{ ..., error: ..., ... }` hash
# literal returned straight from a rescue clause. `\b` keeps `safe_failure(`
# out: `_` is a word character, so no boundary precedes its `failure`.
FAILURE_CALL = /\bfailure\w*\(/.freeze
DIRECT_RETURN_SHAPE = /\bfailure\w*\(|\berror:|"error"\s*=>/.freeze
# A top-level array-push STATEMENT (`errors << {...}` / `failures << {...}`,
# any local array name) — the documented, separate, larger rollback-
# bookkeeping gap this guard does not attempt (see this script's .sh header).
# Only THIS statement's own line(s) are excluded from the scan below, never
# the rest of the clause — a direct return sitting in the same clause as an
# out-of-scope push must still be caught.
PUSH_STATEMENT_START = /\A[ \t]*\w+(?:\.\w+|\[[^\]]*\])*\s*<</.freeze
# The safe helpers are NEUTRALIZED, not used to skip the line (review round
# 3): skipping any line that merely mentioned safe_error_text let
# `failure("#{safe_error_text(e)} (#{e.message})")` through whole. Only the
# helper call itself is replaced — see #neutralize_safe_calls.
SAFE_ERROR_TEXT_CALL = /\bsafe_error_text\(/.freeze
SAFE_FAILURE_CALL = /\bsafe_failure\(/.freeze
SAFE_PLACEHOLDER = "SAFE_TEXT"
# Inline opt-out for a SPECIFIC, individually-reviewed raise site — mirrors
# check-account-scoping.sh's `# scoping-ok: <reason>`. Use only when the
# EXACT raise(s) reaching this rescue were read and confirmed hand-authored,
# caller-owned text; never to silence an unaudited exception class.
SUPPRESSION_ANNOTATION = /#\s*skill-error-ok:/.freeze

# Member-access / interpolation shapes that pull an exception's OWN text off
# a given identifier (the rescued variable, or one of its ".record" chains —
# `e.record.errors.full_messages` is exactly as leaky as `e.message`, and a
# cross-tenant existence oracle besides wherever a uniqueness validator is
# unscoped; see base_skill_executor.rb's own safe_error_text comment).
def member_leak_source(name)
  re = Regexp.escape(name)
  "\\b#{re}\\.(?:record\\.errors\\.full_messages(?:_for)?\\b(?:\\([^)]*\\))?|" \
    "errors\\.full_messages(?:_for)?\\b(?:\\([^)]*\\))?|message|to_s|full_message|" \
    "full_messages|inspect|detailed_message)\\b|\\#\\{\\s*#{re}\\s*\\}"
end

# Index just past the paren that closes the one opened right before `start`,
# or text.length when it never closes on this line.
def balanced_close(text, start)
  depth = 1
  k = start
  while k < text.length && depth.positive?
    depth += 1 if text[k] == "("
    depth -= 1 if text[k] == ")"
    k += 1
  end
  k
end

# `safe_error_text(<args>)` becomes SAFE_PLACEHOLDER, and `safe_failure(<first
# arg>` becomes `failure(SAFE_PLACEHOLDER` — the caught exception handed to
# the helper is safe, but anything ELSE on the line (an extra interpolation,
# a keyword the helper merges into the result) is still scanned as usual.
def neutralize_safe_calls(line)
  out = line.dup
  while (m = SAFE_ERROR_TEXT_CALL.match(out))
    out = out[0...m.begin(0)] + SAFE_PLACEHOLDER + out[balanced_close(out, m.end(0))..].to_s
  end
  while (m = SAFE_FAILURE_CALL.match(out))
    k = m.end(0)
    depth = 0
    while k < out.length
      c = out[k]
      break if depth.zero? && (c == "," || c == ")")

      depth += 1 if "([{".include?(c)
      depth -= 1 if ")]}".include?(c)
      k += 1
    end
    out = out[0...m.begin(0)] + "failure(" + SAFE_PLACEHOLDER + out[k..].to_s
  end
  out
end

# Rows: [line_index_within_clause, text_with_trailing_comment_stripped].
# Excludes whole-line comments, logger lines, suppressed lines, and every line of a push STATEMENT (see PUSH_STATEMENT_START above,
# with brace-depth tracking so a push spanning several lines is excluded in
# full, not just its first line).
def scannable_rows(clause)
  rows = []
  i = 0
  while i < clause.length
    line = clause[i]
    if line =~ PUSH_STATEMENT_START
      depth = line.count("{") - line.count("}")
      j = i + 1
      while depth.positive? && j < clause.length
        depth += clause[j].count("{") - clause[j].count("}")
        j += 1
      end
      i = j
      next
    end
    unless line =~ /\A[ \t]*#/ || line =~ LOGGER_LINE || line =~ SUPPRESSION_ANNOTATION
      # Strip a trailing `# comment`, NOT a `#{...}` / `#@ivar` / `#$global`
      # string interpolation — a bare `/#.*/` (this guard's first pass) chops
      # the leak text off of `failure("...#{e.message}")` entirely, which is
      # the single most common real shape in this codebase.
      rows << [ i, neutralize_safe_calls(line).sub(/#(?!\{|@|\$).*/, "") ]
    end
    i += 1
  end
  rows
end

# Joins the scannable rows into one blob (so a multi-line call/hash reads as
# one statement) plus a same-length array mapping each character offset back
# to its originating clause line index, for accurate reporting.
def blob_and_offsets(rows)
  blob = +""
  offsets = []
  rows.each do |line_idx, text|
    text.length.times { offsets << line_idx }
    blob << text << " "
    offsets << line_idx # the joining space
  end
  [ blob, offsets ]
end

# All balanced-paren spans of a call matching `re` (whose match ends at the
# opening paren) in text, as the substrings between the matching parens
# (handles nested parens, e.g. `.join("; ")` inside a `failure(...)` call,
# which a single non-nested regex would truncate on).
def call_arg_spans(text, re)
  spans = []
  pos = 0
  while (m = re.match(text, pos))
    start = m.end(0)
    k = balanced_close(text, start)
    spans << text[start...(k - 1)]
    pos = k
  end
  spans
end

# Every `error:` / `"error" =>` hash-value expression in text, up to the next
# top-level comma or closing brace — good enough for this codebase's error
# values, which are never themselves multi-key hash literals.
def error_value_spans(text)
  text.scan(/(?:\berror:|"error"\s*=>)\s*([^,}]+)/).flatten
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

    header_lines = [line]
    if line.sub(/#.*/, "").rstrip.end_with?(",")
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

    var = header_text[CAPTURED_VAR, 1]

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
      rows = scannable_rows(clause)
      blob, offsets = blob_and_offsets(rows)

      # Tainted names: the rescued variable itself, plus any local reassigned
      # from one of its leak-shaped expressions (`msg = e.message`), to a
      # fixed point (an alias of an alias still counts).
      tainted = [ var ]
      loop do
        found_new = false
        tainted.each do |name|
          blob.scan(/\b(\w+)\s*=\s*(?:#{member_leak_source(name)})/) do |alias_name,|
            next if tainted.include?(alias_name)
            tainted << alias_name
            found_new = true
          end
        end
        break unless found_new
      end

      hit_offset = nil
      tainted.each do |name|
        # The rescued var (or an alias) referenced bare — `failure(msg)`,
        # `"...#{e.message}..."` already covered via member_leak_source, or a
        # bare alias interpolated/passed straight through.
        usage_re = name == var ? /#{member_leak_source(name)}/ : /\b#{Regexp.escape(name)}\b/

        call_arg_spans(blob, FAILURE_CALL).each do |span|
          m = usage_re.match(span)
          next unless m

          idx = blob.index(span)
          hit_offset = idx + (idx ? m.begin(0) : 0)
          break
        end
        break if hit_offset

        error_value_spans(blob).each do |val|
          m = usage_re.match(val)
          next unless m

          idx = blob.index(val)
          hit_offset = idx + (idx ? m.begin(0) : 0)
          break
        end
        break if hit_offset
      end

      # HEREDOC fallback: `failure(<<~MSG)` puts the heredoc's opening marker
      # inside the call's parens, but the body that actually carries the
      # leak lives on the FOLLOWING lines, outside any paren depth the
      # call_arg_spans walk can see — heredocs are a different lexical unit
      # entirely. Scanned directly against the clause's raw lines (not the
      # comment-stripped blob, so a heredoc body's own `#` text is left
      # alone — a heredoc's contents are not Ruby source to strip comments
      # from).
      heredoc_line_idx = nil
      if hit_offset.nil?
        clause.each_with_index do |cl, idx|
          next unless cl =~ /<<[-~]?(['"`]?)(\w+)\1/
          next unless cl =~ DIRECT_RETURN_SHAPE

          terminator = Regexp.last_match(2)
          k = idx + 1
          body = []
          while k < clause.length && clause[k].strip != terminator
            body << clause[k]
            k += 1
          end
          body_text = body.join(" ")
          tainted.each do |name|
            usage_re = name == var ? /#{member_leak_source(name)}/ : /\b#{Regexp.escape(name)}\b/
            next unless body_text =~ usage_re

            heredoc_line_idx = idx
            break
          end
          break if heredoc_line_idx
        end
      end

      if hit_offset
        line_idx = offsets[hit_offset] || rows.first&.first || 0
        hits << "#{file}:#{i + 1 + line_idx}"
      elsif heredoc_line_idx
        hits << "#{file}:#{i + 1 + heredoc_line_idx}"
      end
    end

    i += 1
  end
end

hits.uniq!

if hits.any?
  hits.each do |h|
    puts "LEAK: #{h} — a rescue clause forwards the exception's own message " \
         "in a direct caller-facing return (route it through #safe_error_text / #safe_failure)"
  end
  puts ""
  puts "Found #{hits.size} hit(s)."
  exit 1
end

exit 0
