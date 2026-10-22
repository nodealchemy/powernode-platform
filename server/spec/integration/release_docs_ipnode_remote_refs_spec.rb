# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check for the release/setup docs that describe the dual-remote
# layout (private Gitea upstream = `gitea`, public GitHub mirror = `origin`).
#
# 1. They must not name the retired `ipnode` git remote (IMP-1cbab660381e). The
#    regex matches `ipnode` only as a remote NAME: word-bounded, and excluding a
#    dotted host-taxonomy domain of the same stem.
# 2. They must not name the private Gitea's concrete host. That host is
#    deployment knowledge (docs/contributing/conventions/deployment-knowledge.md)
#    and these docs ship on the public mirror, so they describe it with the
#    `<gitea-host>` placeholder (or prose) instead. The check is generic — any
#    `git.<domain>.<tld>` host other than an example/test domain is a leak — so
#    the spec itself never has to contain the private name.
RSpec.describe 'release/setup docs describe the git remotes without deployment identifiers' do
  repo_root = File.expand_path('../../..', __dir__)
  docs = %w[
    docs/contributing/release-process.md
    docs/contributing/github-workflow.md
    docs/getting-started/03-extensions.md
    docs/operations/reverse-proxy.md
  ].map { |rel| File.join(repo_root, rel) }

  def offending_lines(docs, regex)
    docs.flat_map do |path|
      File.foreach(path).with_index(1).filter_map do |line, num|
        "#{File.basename(path)}:#{num}: #{line.strip}" if line.match?(regex)
      end
    end
  end

  it 'names no `ipnode` git remote (renamed to origin; GitHub mirror is `github`)' do
    offenders = offending_lines(docs, /\bipnode(?!\.(?:us|net|org))\b/i)

    expect(offenders).to(
      be_empty,
      "Stale `ipnode` remote references (the Gitea upstream is now `origin`):\n#{offenders.join("\n")}"
    )
  end

  it 'names no concrete Gitea host (use the <gitea-host> placeholder)' do
    concrete_git_host = /\bgit\.(?!example\b)[a-z0-9-]+\.(?:net|org|com|io|us|dev)\b/i
    offenders = offending_lines(docs, concrete_git_host)

    expect(offenders).to(
      be_empty,
      "Release docs name a concrete Gitea host — replace it with <gitea-host>:\n#{offenders.join("\n")}"
    )
  end

  # The release doc names the remotes release.sh pushes to (`gitea`, then
  # `origin`) and describes the Gitea host in prose, as deployment knowledge,
  # rather than through the <gitea-host> placeholder.
  it 'still documents the dual-remote layout without naming the host' do
    release = File.read(File.join(repo_root, 'docs/contributing/release-process.md'))

    expect(release).to match(/`gitea` \(the private Gitea upstream; host is deployment knowledge\)/)
    expect(release).to match(/`origin` \(the public GitHub mirror\)/)
  end
end
