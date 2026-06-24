# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: release/setup docs must not name the retired `ipnode` git
# remote. The private Gitea upstream was rebranded to powernode (host
# git.powernode.net) and is the `origin` remote on the live checkout; the public
# GitHub mirror is the `github` remote. Reproduces IMP-1cbab660381e.
#
# The regex matches `ipnode` only as a remote NAME: word-bounded, and excluding
# the legitimate ipnode.us / ipnode.net / ipnode.org host-taxonomy domains that
# appear in other docs (e.g. dev.ipnode.us in single-node-bootstrap.md). A
# sentence-final "...push to ipnode." is still caught (the `.` is not a TLD).
RSpec.describe 'release/setup docs do not reference the retired ipnode remote' do
  repo_root = File.expand_path('../../..', __dir__)
  docs = %w[
    docs/contributing/release-process.md
    docs/contributing/github-workflow.md
    docs/getting-started/03-extensions.md
    docs/operations/reverse-proxy.md
  ].map { |rel| File.join(repo_root, rel) }

  it 'names no `ipnode` git remote (renamed to origin; GitHub mirror is `github`)' do
    offenders = docs.flat_map do |path|
      File.foreach(path).with_index(1).filter_map do |line, num|
        "#{File.basename(path)}:#{num}: #{line.strip}" if line.match?(/\bipnode(?!\.(?:us|net|org))\b/i)
      end
    end

    expect(offenders).to(
      be_empty,
      "Stale `ipnode` remote references (the Gitea upstream is now `origin`):\n#{offenders.join("\n")}"
    )
  end
end
