#!/usr/bin/env ruby
# frozen_string_literal: true

# core-extension-route-literals.rb — core frontend must not name an extension's
# route.
#
# Extensions depend on core; core never depends on an extension. A string
# literal in core frontend code whose value is an extension-served route (e.g.
# '/system/platform/volumes', '/plans', '/billing') is that dependency in a form
# the name-based core-purity checks cannot see: it 404s, or links nowhere,
# whenever the extension is absent. Core reaches extension behaviour through
# featureRegistry seams instead (component slots, public route roles, mention
# sources, provider-category handlers).
#
# Scans non-test .ts/.tsx under frontend/src with comments stripped and flags a
# string or template literal whose value starts with an optional '/api/v1' and
# then one of the guarded route prefixes, ending at a '/', '?', '#' or the
# closing quote. The prefixes are route segments, fixed here; the scan reads
# nothing under extensions/, so it behaves the same with none checked out.
#
# The allowlist (core-extension-route-literals-allowlist.yml, next to this file)
# holds EXACT per-file counts, each with a reason and a ruling or task ref.
# A file with hits and no entry, a count above its entry, and a stale entry (a
# lower count, or a file with none left) are all violations.
#
# Usage:
#   core-extension-route-literals.rb             prints the violation count
#   core-extension-route-literals.rb --list      prints one line per violation
#   core-extension-route-literals.rb --self-test runs the fixtures; exit 0/1
#
# STILL NOT CAUGHT: a route assembled at runtime (string concatenation, a
# prefix held in a separate constant or read from config), including a template
# literal with an interpolated base such as `${API}/system/x` -- the literal
# must START with the route. This is a literal scan, not a dataflow analysis.
#
# Every allowlist entry must carry a positive integer count, a reason and a ref;
# an entry missing any of them is itself a violation.

require "yaml"

module CoreExtensionRouteLiterals
  PREFIXES = %w[system business plans billing marketplace mcp/hosting].freeze
  LITERAL = %r{[`'"](?:/api/v1)?/(?:#{PREFIXES.map { |p| Regexp.escape(p) }.join("|")})(?=[/?#`'"])}.freeze
  ROOT = File.expand_path("../..", __dir__)
  ALLOWLIST = File.join(__dir__, "core-extension-route-literals-allowlist.yml")
  FIXTURES = File.join(__dir__, "tests", "fixtures", "core-extension-route-literals")

  module_function

  # A '/' after one of these (or at the start) opens a regex literal, not a
  # division. '<' and '>' are left out so a JSX closing tag is not a regex.
  REGEX_PRECEDERS = "(,=:[!&|?{};+-*%~^".chars.freeze

  # Drops // and /* */ comments. String-aware so a '//' inside a literal stays:
  # a ' or " string ends at its closing quote or at the end of the line (an
  # apostrophe in JSX text must not flip quote parity for the rest of the file);
  # only a backtick template spans lines. A regex literal is copied through
  # untouched, and a '//' right after ':' is a URL, not a comment.
  def strip_comments(src)
    out = +""
    i = 0
    quote = nil
    while i < src.length
      c = src[i]
      n = src[i + 1]
      if quote
        out << c
        if c == "\\"
          out << n.to_s
          i += 2
          next
        end
        quote = nil if c == quote || (c == "\n" && quote != "`")
        i += 1
      elsif ["'", '"', "`"].include?(c)
        quote = c
        out << c
        i += 1
      elsif c == "/" && n == "/" && out[-1] != ":"
        i += 1 while i < src.length && src[i] != "\n"
      elsif c == "/" && n == "*"
        i += 2
        i += 1 while i < src.length && !(src[i] == "*" && src[i + 1] == "/")
        i += 2
      elsif c == "/" && n != "/" && regex_start?(out)
        i = copy_regex(src, i, out)
      else
        out << c
        i += 1
      end
    end
    out
  end

  def regex_start?(out)
    prev = out.rstrip[-1]
    prev.nil? || REGEX_PRECEDERS.include?(prev) || out.match?(/\b(?:return|typeof|case)\s*\z/)
  end

  # Copies a regex literal from src[i] (its opening '/') to out; returns the
  # index after it. Stops at an unescaped '/' outside a [...] class, or at the
  # end of the line (not a regex after all; the rest scans normally).
  def copy_regex(src, i, out)
    out << src[i]
    i += 1
    in_class = false
    while i < src.length && src[i] != "\n"
      c = src[i]
      out << c
      if c == "\\"
        out << src[i + 1].to_s if src[i + 1] != "\n"
        i += src[i + 1] == "\n" ? 1 : 2
        next
      end
      i += 1
      if c == "[" then in_class = true
      elsif c == "]" then in_class = false
      elsif c == "/" && !in_class then break
      end
    end
    i
  end

  def source_files(root)
    Dir.glob(File.join(root, "**", "*.{ts,tsx}")).reject do |f|
      f.include?("/node_modules/") || f.include?("/__tests__/") ||
        f.match?(/\.(test|spec)\.tsx?\z/) || f.end_with?(".d.ts")
    end.sort
  end

  # { "relative/path" => hit_count } for every file with at least one hit.
  def counts(root, relative_to)
    source_files(root).each_with_object({}) do |file, acc|
      hits = strip_comments(File.read(file)).scan(LITERAL).length
      acc[file.delete_prefix("#{relative_to}/")] = hits if hits.positive?
    end
  end

  def violations(found, allowed)
    lines = []
    allowed.each do |path, entry|
      missing = %w[reason ref].reject { |k| entry.is_a?(Hash) && !entry[k].to_s.strip.empty? }
      missing.unshift("count") unless valid_count?(entry)
      lines << "#{path}: allowlist entry missing #{missing.join(", ")}" unless missing.empty?
    end
    found.each do |path, hits|
      entry = allowed[path]
      if entry.nil?
        lines << "#{path}: #{hits} extension-route literal(s), not allowlisted"
      elsif !valid_count?(entry)
        next
      elsif hits > entry["count"]
        lines << "#{path}: #{hits} literal(s), allowlist says #{entry["count"]} (a new one landed)"
      elsif hits < entry["count"]
        lines << "#{path}: #{hits} literal(s), allowlist says #{entry["count"]} (lower the entry)"
      end
    end
    (allowed.keys - found.keys).each do |path|
      lines << "#{path}: allowlisted but has no extension-route literal left (remove the entry)"
    end
    lines
  end

  def valid_count?(entry)
    entry.is_a?(Hash) && entry["count"].is_a?(Integer) && entry["count"].positive?
  end

  def allowlist
    data = File.exist?(ALLOWLIST) ? YAML.safe_load_file(ALLOWLIST) : {}
    data || {}
  end

  def scan
    violations(counts(File.join(ROOT, "frontend", "src"), ROOT), allowlist)
  end

  # Fixtures: fixture.ts holds literals that MUST be flagged and ones that must
  # NOT (comments, lookalike segments, /app/... paths). The expected count is
  # asserted exactly, so a matcher that flags too much fails as surely as one
  # that flags too little, and a fixture-free allowlist must flag the file.
  def self_test
    failures = []
    src = File.join(FIXTURES, "src")
    found = counts(src, FIXTURES)
    expected = { "src/fixture.ts" => 11 }
    failures << "fixture counts #{found.inspect}, expected #{expected.inspect}" unless found == expected
    unlisted = violations(found, {})
    failures << "an unlisted fixture file did not produce a violation" unless unlisted.length == 1
    entry = ->(count) { { "count" => count, "reason" => "fixture", "ref" => "self-test" } }
    listed = violations(found, { "src/fixture.ts" => entry.call(11) })
    failures << "an exact allowlist entry still produced #{listed.inspect}" unless listed.empty?
    stale = violations(found, { "src/fixture.ts" => entry.call(12), "src/gone.ts" => entry.call(1) })
    failures << "stale entries produced #{stale.length} violation(s), expected 2" unless stale.length == 2
    %w[reason ref].each do |key|
      bare = violations(found, { "src/fixture.ts" => entry.call(11).except(key) })
      failures << "an entry without #{key} produced #{bare.inspect}" unless bare == ["src/fixture.ts: allowlist entry missing #{key}"]
    end
    failures
  end
end

case ARGV.first
when "--self-test"
  failures = CoreExtensionRouteLiterals.self_test
  failures.each { |f| warn "self-test FAIL: #{f}" }
  puts failures.empty? ? "self-test PASS" : "self-test FAIL"
  exit(failures.empty? ? 0 : 1)
when "--list"
  puts CoreExtensionRouteLiterals.scan
else
  puts CoreExtensionRouteLiterals.scan.length
end
