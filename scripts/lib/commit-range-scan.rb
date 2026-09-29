#!/usr/bin/env ruby
# frozen_string_literal: true

# commit-range-scan.rb <repo-dir> <base>..<head> [--forbidden-from <dir-of-private-extensions>]
#
# The publication rules for every commit in a range, applied BEFORE anything is pushed to a
# mirrored remote: no AI attribution (message or author/committer identity), no private-extension
# name, no control byte. It is the same rule set the dev-merge worker enforces
# (Devops::CommitMessageHygiene — required from the worker tree, not restated here), read from the raw
# commit objects as bytes so a message in any encoding is scanned rather than skipped.
#
# The private-extension names are DERIVED from extensions/private/* (never listed in code). When the
# directory is absent the scan runs with no names and says so.
#
# Output: one JSON object on stdout, never containing scanned text — only commit shas and the rule
# that fired. Exit 0 clean, 1 findings, 2 usage/git error.

require "json"
require "open3"

repo, range, *rest = ARGV
if repo.nil? || range.nil? || !range.include?("..")
  warn "usage: commit-range-scan.rb <repo-dir> <base>..<head> [--forbidden-from <dir>]"
  exit 2
end

forbidden_dir = nil
if rest.first == "--forbidden-from"
  forbidden_dir = rest[1]
  exit 2 if forbidden_dir.nil?
end

hygiene = File.expand_path("../../worker/app/services/devops/commit_message_hygiene.rb", __dir__)
unless File.file?(hygiene)
  warn "commit-range-scan.rb: #{hygiene} not found"
  exit 2
end
require hygiene

def git(repo, *args)
  out, err, status = Open3.capture3("git", "-C", repo, *args, binmode: true)
  raise "git #{args.first} failed: #{err.to_s.strip[0, 200]}" unless status.success?

  out
end

begin
  names = forbidden_dir && Dir.exist?(forbidden_dir) ? Dir.children(forbidden_dir).select { |n| File.directory?(File.join(forbidden_dir, n)) }.sort : []
  commits = git(repo, "rev-list", "--reverse", range).split("\n").map(&:strip).reject(&:empty?)
  problems = []

  commits.each do |sha|
    raw = git(repo, "cat-file", "commit", sha)
    headers, message = raw.split("\n\n", 2)
    identity = headers.to_s.split("\n").grep(/\A(?:author|committer) /n).map { |l| l.sub(/\A(?:author|committer) /n, "") }

    if (byte = Devops::CommitMessageHygiene.control_byte(message.to_s) ||
               identity.filter_map { |i| Devops::CommitMessageHygiene.control_byte(i) }.first)
      problems << { commit: sha, rule: "control_byte", detail: byte }
      next
    end

    text = message.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    who = identity.map { |i| i.dup.force_encoding(Encoding::UTF_8).scrub }
    if text.lines.any? { |l| Devops::CommitMessageHygiene.attribution_line?(l) } ||
       who.any? { |v| v.match?(Devops::CommitMessageHygiene::MODEL_WORDS) }
      problems << { commit: sha, rule: "ai_attribution" }
    end
    problems << { commit: sha, rule: "private_extension_name" } if Devops::CommitMessageHygiene.names_private?([text, *who].join("\n"), names)
  end

  puts JSON.generate(range: range, commits: commits.size, private_names_checked: names.size, clean: problems.empty?, problems: problems)
  exit(problems.empty? ? 0 : 1)
rescue StandardError => e
  warn "commit-range-scan.rb: #{e.message}"
  exit 2
end
