# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'open3'
require_relative '../../../app/services/devops/increment_merge_service'

# The worker half of dev_merge_increment, run against REAL git on local bare
# repositories in a temp dir: the "remotes" are paths on disk, so nothing is
# ever pushed anywhere real. The provider API is a double.
RSpec.describe Devops::IncrementMergeService do
  def git_env
    { 'GIT_AUTHOR_NAME' => 'Spec', 'GIT_AUTHOR_EMAIL' => 'spec@example.invalid',
      'GIT_COMMITTER_NAME' => 'Spec', 'GIT_COMMITTER_EMAIL' => 'spec@example.invalid',
      'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL }
  end

  let(:root) { Dir.mktmpdir('dev-merge-spec') }
  after { FileUtils.remove_entry(root) }

  def sh!(*argv, dir: root, stdin: nil)
    out, err, status = Open3.capture3(git_env, *argv, chdir: dir, stdin_data: stdin.to_s)
    raise "#{argv.join(' ')} failed: #{err}" unless status.success?

    out.strip
  end

  def bare(name)
    path = File.join(root, "#{name}.git")
    sh!('git', 'init', '--bare', '--quiet', '--initial-branch=develop', path)
    path
  end

  def tip(repo, branch = 'develop')
    sh!('git', '--git-dir', repo, 'rev-parse', "refs/heads/#{branch}")
  end

  # A scratch clone to author commits in; pushes to every listed bare repo.
  def author(name, pushes_to:)
    work = File.join(root, "work-#{name}")
    sh!('git', 'init', '--quiet', '--initial-branch=develop', work)
    yield work
    pushes_to.each { |repo, refspec| sh!('git', 'push', '--quiet', repo, refspec, dir: work) }
    work
  end

  def commit!(work, file, subject)
    File.write(File.join(work, file), "#{subject}\n")
    sh!('git', 'add', file, dir: work)
    sh!('git', 'commit', '--quiet', '-m', subject, dir: work)
    sh!('git', 'rev-parse', 'HEAD', dir: work)
  end

  let!(:sub_primary) { bare('sub-primary') }
  let!(:sub_mirror) { bare('sub-mirror') }
  let!(:parent_primary) { bare('parent-primary') }
  let!(:parent_mirror) { bare('parent-mirror') }

  let!(:base_sha) do
    sha = nil
    @sub_work = author('sub', pushes_to: [ [ sub_primary, 'develop' ], [ sub_mirror, 'develop' ] ]) do |work|
      sha = commit!(work, 'a.txt', 'base')
    end
    sha
  end

  let!(:increment_sha) do
    sh!('git', 'checkout', '--quiet', '-b', 'feature/increment', dir: @sub_work)
    sha = commit!(@sub_work, 'b.txt', 'governed in-place peer key rotation')
    sh!('git', 'push', '--quiet', sub_primary, 'feature/increment', dir: @sub_work)
    sha
  end

  # A parent whose develop records the submodule at base_sha.
  let!(:parent_base) do
    author('parent', pushes_to: [ [ parent_primary, 'develop' ], [ parent_mirror, 'develop' ] ]) do |work|
      commit!(work, 'README', 'parent root')
      sh!('git', 'update-index', '--add', '--cacheinfo', "160000,#{base_sha},extensions/demo", dir: work)
      sh!('git', 'commit', '--quiet', '-m', 'add the submodule pointer', dir: work)
    end
    tip(parent_primary)
  end

  let(:paths) do
    { 'sub-primary' => sub_primary, 'sub-mirror' => sub_mirror,
      'parent-primary' => parent_primary, 'parent-mirror' => parent_mirror }
  end
  let(:api_sha) { increment_sha }
  let(:git_ops) { double('GitOperationsService') }
  let(:forbidden_names) { %w[zzhidden] }
  let(:pointer_bump) do
    { 'submodule_path' => 'extensions/demo',
      'remotes' => [ { 'repository_id' => 'parent-primary' }, { 'repository_id' => 'parent-mirror' } ] }
  end
  let(:payload) do
    { 'deferred_operation_id' => 'op-1', 'source_ref' => 'feature/increment', 'target_branch' => 'develop',
      'expected_source_sha' => increment_sha,
      'remotes' => [ { 'repository_id' => 'sub-primary' }, { 'repository_id' => 'sub-mirror' } ],
      'committer' => { 'name' => 'Operator', 'email' => 'operator@example.invalid' },
      'forbidden_names' => forbidden_names, 'pointer_bump' => pointer_bump }
  end

  let(:service) do
    described_class.new(
      payload: payload,
      remote_resolver: ->(id) { { url: paths.fetch(id), full_name: id, auth_header: nil, secrets: [], api_config: {} } },
      git_ops_factory: ->(_config) { git_ops },
      logger: Logger.new(File::NULL)
    )
  end

  before do
    allow(git_ops).to receive(:get_branch).and_return({ name: 'feature/increment', commit: { sha: api_sha } })
  end

  def message_of(repo, ref = 'develop')
    sh!('git', '--git-dir', repo, 'log', '-1', '--format=%B', ref)
  end

  def gitlink(repo)
    sh!('git', '--git-dir', repo, 'ls-tree', 'develop', '--', 'extensions/demo').split(/\s+/)[2]
  end

  describe 'a clean merge' do
    it 'fast-forwards every remote, bumps ONLY the gitlink, and pushes that everywhere' do
      report = service.call

      expect(report['status']).to eq('succeeded'), report['error'].to_s
      expect(tip(sub_primary)).to eq(increment_sha)
      expect(tip(sub_mirror)).to eq(increment_sha)
      expect(report['remotes'].map { |r| r['status'] }).to eq(%w[pushed pushed])

      commit = report['pointer_commit_sha']
      expect(tip(parent_primary)).to eq(commit)
      expect(tip(parent_mirror)).to eq(commit)
      expect(gitlink(parent_primary)).to eq(increment_sha)
      expect(sh!('git', '--git-dir', parent_primary, 'rev-parse', "#{commit}^")).to eq(parent_base)
      expect(sh!('git', '--git-dir', parent_primary, 'diff-tree', '-r', '--name-only', '--no-commit-id',
                 parent_base, commit).split("\n")).to eq([ 'extensions/demo' ])
      expect(message_of(parent_primary))
        .to eq("chore(demo): bump extension pointer to #{increment_sha[0, 8]} (governed in-place peer key rotation)")
      expect(sh!('git', '--git-dir', parent_primary, 'log', '-1', '--format=%an <%ae>|%cn <%ce>', 'develop'))
        .to eq('Operator <operator@example.invalid>|Operator <operator@example.invalid>')
    end

    it 'never runs git submodule' do
      service.call

      expect(service.git.commands.flatten).not_to include('submodule')
      expect(service.git.commands.map(&:first)).to include('update-index', 'commit-tree', 'push')
    end

    it 'reports a remote that is already at the SHA as up_to_date and does not push it' do
      sh!('git', 'push', '--quiet', sub_mirror, 'feature/increment:develop', dir: @sub_work)

      report = service.call

      expect(report['remotes'].map { |r| r['status'] }).to eq(%w[pushed up_to_date])
    end
  end

  describe 'refusals' do
    it 'refuses when source_ref no longer resolves to expected_source_sha, and changes nothing' do
      allow(git_ops).to receive(:get_branch).and_return({ commit: { sha: base_sha } })

      report = service.call

      expect(report).to include('status' => 'failed', 'stage' => 'verify_source')
      expect(report['error']).to match(/moved/)
      expect(tip(sub_primary)).to eq(base_sha)
      expect(tip(sub_mirror)).to eq(base_sha)
      expect(tip(parent_primary)).to eq(parent_base)
    end

    it 'refuses a non-fast-forward on ANY remote before pushing to any' do
      author('diverge', pushes_to: []) do |work|
        sh!('git', 'fetch', '--quiet', sub_mirror, 'develop', dir: work)
        sh!('git', 'checkout', '--quiet', '-B', 'develop', 'FETCH_HEAD', dir: work)
        commit!(work, 'c.txt', 'someone else landed first')
        sh!('git', 'push', '--quiet', sub_mirror, 'develop', dir: work)
      end
      diverged = tip(sub_mirror)

      report = service.call

      expect(report).to include('status' => 'failed', 'stage' => 'fast_forward')
      expect(report['error']).to match(/non-fast-forward/)
      expect(tip(sub_primary)).to eq(base_sha)
      expect(tip(sub_mirror)).to eq(diverged)
    end

    it 'reports a push that reached only some remotes as FAILED, per remote, and bumps no pointer' do
      hook = File.join(sub_mirror, 'hooks', 'pre-receive')
      File.write(hook, "#!/bin/sh\necho 'mirror says no' >&2\nexit 1\n")
      File.chmod(0o755, hook)

      report = service.call

      expect(report).to include('status' => 'failed', 'stage' => 'push')
      expect(report['remotes'].map { |r| [ r['repository_id'], r['status'] ] })
        .to eq([ %w[sub-primary pushed], %w[sub-mirror failed] ])
      expect(report['remotes'].last['error']).to match(/mirror says no/)
      expect(tip(parent_primary)).to eq(parent_base)
      expect(report).not_to have_key('pointer_commit_sha')
    end

    it 'refuses a generated message that names a private extension, without writing the pointer' do
      payload['pointer_bump'] = pointer_bump.merge('summary' => 'wire the ZZhidden seam')

      report = service.call

      expect(report).to include('status' => 'failed', 'stage' => 'pointer_bump')
      expect(report['error']).to match(/private extension/)
      expect(report['error']).not_to match(/zzhidden/i)
      expect(tip(parent_primary)).to eq(parent_base)
      expect(tip(parent_mirror)).to eq(parent_base)
    end

    it 'refuses a submodule path that is not a gitlink' do
      payload['pointer_bump'] = pointer_bump.merge('submodule_path' => 'README')

      report = service.call

      expect(report).to include('status' => 'failed', 'stage' => 'pointer_bump')
      expect(report['error']).to match(/not a submodule gitlink/)
      expect(tip(parent_primary)).to eq(parent_base)
    end
  end

  it 'strips an AI attribution line out of the generated message' do
    payload['pointer_bump'] = pointer_bump.merge('summary' => 'Co-Authored-By: Some Model <x@example.invalid>')

    report = service.call

    expect(report['status']).to eq('succeeded'), report['error'].to_s
    expect(message_of(parent_primary)).to eq("chore(demo): bump extension pointer to #{increment_sha[0, 8]}")
  end
end

RSpec.describe Devops::GitCli do
  it 'refuses git submodule outright, before anything runs' do
    cli = described_class.new(git_dir: File::NULL)

    expect { cli.run('submodule', 'sync') }.to raise_error(described_class::Refused, /submodule/)
    expect(cli.commands).to be_empty
  end

  it 'scrubs the credential out of what git prints' do
    Dir.mktmpdir do |dir|
      repo = File.join(dir, 'scratch.git')
      Open3.capture3('git', 'init', '--bare', '--quiet', repo)
      cli = described_class.new(git_dir: repo)
      result = cli.run('fetch', 'https://127.0.0.1:9/never/secret-token-123', secrets: [ 'secret-token-123' ])

      expect(result.success?).to be(false)
      # The failure names the URL, so the scrub is what keeps the token out.
      expect(result.stderr).to include('127.0.0.1:9/never/[REDACTED]')
      expect(result.stderr).not_to include('secret-token-123')
    end
  end
end

RSpec.describe Devops::CommitMessageHygiene do
  it 'drops the parenthetical when the summary was only an attribution line' do
    expect(described_class.pointer_bump_message(scope: 'demo', short_sha: 'abcd1234',
                                                summary: 'Generated with a tool', forbidden_names: []))
      .to eq('chore(demo): bump extension pointer to abcd1234')
  end

  it 'refuses a private name in the scope itself' do
    expect do
      described_class.pointer_bump_message(scope: 'zz-hidden', short_sha: 'abcd1234', summary: 'x',
                                           forbidden_names: %w[zz-hidden])
    end.to raise_error(described_class::Refused)
  end

  it 'refuses the PascalCase namespace of a kebab slug' do
    expect do
      described_class.pointer_bump_message(scope: 'demo', short_sha: 'abcd1234', summary: 'call ZzHidden::X',
                                           forbidden_names: %w[zz-hidden])
    end.to raise_error(described_class::Refused)
  end
end
