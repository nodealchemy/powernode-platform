#!/usr/bin/env ruby
# frozen_string_literal: true

# changed-line-offenses.rb <repo> <base> <head> [--prefix <dir>/]  < rubocop-json
#
# Keeps only the RuboCop offenses that sit on lines the range ADDED or CHANGED, so a gate over a touched
# file is not failed by offenses that were already there. `rubocop --format json` output arrives on
# stdin; file paths in it are relative to where rubocop ran, and --prefix names that directory relative
# to the repo root (e.g. `server/`). Prints {"count": N, "offenses": [{file, line, cop, message}]} and
# exits 1 when N > 0, 0 otherwise, 2 on a usage or git error.

require "json"
require "open3"

repo, base, head, *rest = ARGV
if [repo, base, head].any?(&:nil?)
  warn "usage: changed-line-offenses.rb <repo> <base> <head> [--prefix dir/]"
  exit 2
end
prefix = rest.first == "--prefix" ? rest[1].to_s : ""

def added_lines(repo, base, head, path)
  out, err, st = Open3.capture3("git", "-C", repo, "diff", "-U0", "--no-color", "#{base}..#{head}", "--", path)
  raise "git diff failed: #{err.strip[0, 200]}" unless st.success?

  lines = []
  out.each_line do |l|
    next unless (m = l.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))

    start = m[1].to_i
    count = m[2].nil? ? 1 : m[2].to_i
    lines.concat((start...(start + count)).to_a)
  end
  lines
end

begin
  report = JSON.parse($stdin.read)
  found = []
  Array(report["files"]).each do |file|
    next if Array(file["offenses"]).empty?

    path = "#{prefix}#{file['path']}"
    changed = added_lines(repo, base, head, path)
    file["offenses"].each do |o|
      line = o.dig("location", "line")
      next unless changed.include?(line)

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
