#!/usr/bin/env ruby
# frozen_string_literal: true

# changed-line-offenses.rb <repo> <base> <head> [--prefix <dir>/]  < rubocop-json
#
# Keeps only the RuboCop offenses that sit on lines the range ADDED or CHANGED, so a gate over a touched
# file is not failed by offenses that were already there. Two exceptions: a file that does not parse
# (Lint/Syntax, or any fatal offense) always counts, because RuboCop reports it where the parser gave up
# (usually EOF, not the broken line) and reports nothing else for that file; and changed lines come from
# one rename-aware diff of the whole range, so a moved file contributes only the lines that changed.
# `rubocop --format json` output arrives on stdin; file paths in it are relative to where rubocop ran,
# and --prefix names that directory relative to the repo root (e.g. `server/`). Prints {"count": N,
# "offenses": [{file, line, cop, message}]} and exits 1 when N > 0, 0 otherwise, 2 on a usage or git error.

require "json"
require "open3"

repo, base, head, *rest = ARGV
if [repo, base, head].any?(&:nil?)
  warn "usage: changed-line-offenses.rb <repo> <base> <head> [--prefix dir/]"
  exit 2
end
prefix = rest.first == "--prefix" ? rest[1].to_s : ""

# { "path/at/head" => [added line numbers] } for the whole range. Without a pathspec, git can pair a
# rename with its source, so a pure move has no hunks at all and an edited move only its edits.
# A `+++ ` line is a header only between `diff --git` and the first hunk: an added line whose text
# begins with "++ " looks the same inside one.
def added_lines_by_path(repo, base, head)
  out, err, st = Open3.capture3("git", "-C", repo, "-c", "core.quotePath=false", "diff", "-U0", "-M", "--no-color",
                                "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "#{base}..#{head}")
  raise "git diff failed: #{err.strip[0, 200]}" unless st.success?

  by_path = Hash.new { |h, k| h[k] = [] }
  current = nil
  in_header = false
  out.each_line do |l|
    if l.start_with?("diff --git ")
      in_header = true
      current = nil
    elsif in_header && l.start_with?("+++ ")
      name = l.chomp.delete_prefix("+++ ").delete_suffix("\t")
      name = name.undump if name.start_with?('"')
      current = name == "/dev/null" ? nil : name.delete_prefix("b/")
    elsif current && (m = l.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
      in_header = false
      start = m[1].to_i
      count = m[2].nil? ? 1 : m[2].to_i
      by_path[current].concat((start...(start + count)).to_a)
    end
  end
  by_path
end

def fatal?(offense)
  offense["cop_name"] == "Lint/Syntax" || offense["severity"] == "fatal"
end

begin
  report = JSON.parse($stdin.read)
  found = []
  changed_by_path = nil
  Array(report["files"]).each do |file|
    next if Array(file["offenses"]).empty?

    path = "#{prefix}#{file['path']}"
    changed_by_path ||= added_lines_by_path(repo, base, head)
    changed = changed_by_path.fetch(path, [])
    file["offenses"].each do |o|
      line = o.dig("location", "line")
      next unless fatal?(o) || changed.include?(line)

      found << { file: path, line: line, cop: o["cop_name"], message: o["message"].to_s[0, 160] }
    end
  end
  puts JSON.generate(count: found.size, offenses: found)
  exit(found.empty? ? 0 : 1)
rescue JSON::ParserError
  warn "changed-line-offenses.rb: stdin was not RuboCop JSON"
  exit 2
rescue StandardError => e
  warn "changed-line-offenses.rb: #{e.message}"
  exit 2
end
