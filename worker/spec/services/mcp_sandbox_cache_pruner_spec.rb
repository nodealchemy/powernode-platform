# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require 'find'

# IMP-f074ef554781 — every account that ever ran a sandboxed stdio MCP server
# leaves /var/cache/private/mcp-stdio-<21 hex> behind (npm + uv caches), plus
# the /var/cache/mcp-stdio-<21 hex> symlink systemd makes to it. Nothing
# removed them. The pruner removes the ones that belong to no current account
# or have sat idle past the operator-set age, and nothing else.
RSpec.describe McpSandboxCachePruner do
  let(:root) { Dir.mktmpdir('mcp-cache-root') }
  let(:now) { Time.utc(2026, 10, 2, 12, 0, 0) }
  let(:max_idle) { 30 * 86_400 }
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }
  let(:running) { ->(_identity) { false } }
  let(:nss_ready) { -> { true } }

  let(:live_account) { SecureRandom.uuid }
  let(:gone_account) { SecureRandom.uuid }
  let(:live_identity) { McpSecurityService.sandbox_identity(live_account) }
  let(:gone_identity) { McpSecurityService.sandbox_identity(gone_account) }

  after { FileUtils.remove_entry(root, true) }

  def make_cache(identity, age:, file: 'npm/_cacache/index', link: true)
    dir = File.join(root, 'private', identity)
    FileUtils.mkdir_p(File.dirname(File.join(dir, file)))
    File.write(File.join(dir, file), 'x')
    File.symlink("private/#{identity}", File.join(root, identity)) if link
    stamp = now - age
    Find.find(dir) { |path| File.utime(stamp, stamp, path) }
    dir
  end

  def prune(account_ids: [live_account], **overrides)
    described_class.call(
      account_ids: account_ids, max_idle_seconds: max_idle, cache_root: root, now: now,
      running: running, nss_ready: nss_ready, logger: logger, **overrides
    )
  end

  it 'removes the cache of an account that no longer exists, and the symlink systemd made to it' do
    dir = make_cache(gone_identity, age: 2 * 3600)

    result = prune

    expect(File.exist?(dir)).to be(false)
    expect(File.symlink?(File.join(root, gone_identity))).to be(false)
    expect(result[:pruned]).to eq(1)
  end

  it 'keeps a cache for an account that does still exist while it is within the idle age' do
    dir = make_cache(live_identity, age: 29 * 86_400)

    expect(prune[:pruned]).to eq(0)
    expect(File.directory?(dir)).to be(true)
  end

  it 'removes the cache of a live account once it has sat idle past the age' do
    dir = make_cache(live_identity, age: 31 * 86_400)

    expect(prune[:pruned]).to eq(1)
    expect(File.exist?(dir)).to be(false)
  end

  it 'gives a cache for an unknown account a short grace, so a just-created account is not caught mid-spawn' do
    dir = make_cache(gone_identity, age: 60)

    expect(prune[:pruned]).to eq(0)
    expect(File.directory?(dir)).to be(true)
  end

  it 'never removes a cache whose identity has a running unit, however old' do
    dir = make_cache(gone_identity, age: 90 * 86_400)

    result = prune(running: ->(identity) { identity == gone_identity })

    expect(File.directory?(dir)).to be(true)
    expect(result).to include(pruned: 0, kept_running: 1)
  end

  it 'treats a deep recent write as use: the age is the newest mtime in the tree, not the directory' do
    dir = make_cache(gone_identity, age: 90 * 86_400)
    recent = File.join(dir, 'npm', '_cacache', 'fresh')
    File.write(recent, 'x')
    File.utime(now - 60, now - 60, recent)

    expect(prune[:pruned]).to eq(0)
    expect(File.directory?(dir)).to be(true)
  end

  it 'touches only names of the exact identity shape under the cache root' do
    lookalikes = [
      'mcp-stdio-xyz', "mcp-stdio-#{'a' * 20}", "mcp-stdio-#{'a' * 22}", "mcp-stdio-#{'A' * 21}",
      "other-#{'a' * 21}", "mcp-stdio-#{'a' * 21}.bak"
    ]
    kept = lookalikes.map do |name|
      path = File.join(root, 'private', name)
      FileUtils.mkdir_p(path)
      File.utime(now - 90 * 86_400, now - 90 * 86_400, path)
      path
    end
    # A look-alike directly under the root rather than under private/ is not a cache either.
    stray = File.join(root, "mcp-stdio-#{'b' * 21}")
    FileUtils.mkdir_p(stray)
    File.utime(now - 90 * 86_400, now - 90 * 86_400, stray)

    result = prune

    expect(result[:pruned]).to eq(0)
    expect((kept + [stray]).all? { |path| File.directory?(path) }).to be(true)
  end

  it 'never follows a symlink out of a cache it removes' do
    outside = Dir.mktmpdir('mcp-outside')
    File.write(File.join(outside, 'precious'), 'keep me')
    dir = make_cache(gone_identity, age: 2 * 3600)
    File.symlink(outside, File.join(dir, 'escape'))
    stamp = now - 2 * 3600
    File.lutime(stamp, stamp, File.join(dir, 'escape'))
    File.utime(stamp, stamp, dir)

    prune

    expect(File.exist?(dir)).to be(false)
    expect(File.read(File.join(outside, 'precious'))).to eq('keep me')
  ensure
    FileUtils.remove_entry(outside, true)
  end

  it 'refuses to prune on an empty account list: no list is not "no accounts"' do
    dir = make_cache(gone_identity, age: 90 * 86_400)

    result = prune(account_ids: [])

    expect(result).to include(pruned: 0, skipped: 'no current accounts were supplied')
    expect(File.directory?(dir)).to be(true)
  end

  it 'does nothing, quietly, when the host has no private cache root' do
    result = described_class.call(
      account_ids: [live_account], max_idle_seconds: max_idle, cache_root: File.join(root, 'absent'),
      now: now, running: running, nss_ready: nss_ready, logger: logger
    )

    expect(result).to include(pruned: 0)
  end

  it 'logs how many it removed' do
    make_cache(gone_identity, age: 2 * 3600)

    prune

    expect(logger).to have_received(:info).with(/pruned 1 /)
  end

  it 'prunes nothing when no idle age was supplied, rather than assuming a short one' do
    dir = make_cache(live_identity, age: 2 * 86_400)

    expect(prune(max_idle_seconds: nil)).to include(pruned: 0, skipped: 'no idle age was supplied')
    expect(File.directory?(dir)).to be(true)
  end

  it 'prunes nothing on a host that cannot resolve systemd dynamic users: every unit would look stopped' do
    dir = make_cache(gone_identity, age: 90 * 86_400)

    result = prune(nss_ready: -> { false })

    expect(result[:skipped]).to match(/dynamic users/)
    expect(File.directory?(dir)).to be(true)
  end

  it 'keeps a cache whose newest write is in the future' do
    dir = make_cache(gone_identity, age: -3600)

    expect(prune[:pruned]).to eq(0)
    expect(File.directory?(dir)).to be(true)
  end

  it 'does not treat a symlink named like an identity as a cache, nor follow it' do
    outside = Dir.mktmpdir('mcp-outside')
    File.write(File.join(outside, 'precious'), 'keep me')
    FileUtils.mkdir_p(File.join(root, 'private'))
    File.symlink(outside, File.join(root, 'private', gone_identity))
    File.lutime(now - 90 * 86_400, now - 90 * 86_400, File.join(root, 'private', gone_identity))

    expect(prune[:pruned]).to eq(0)
    expect(File.read(File.join(outside, 'precious'))).to eq('keep me')
  ensure
    FileUtils.remove_entry(outside, true)
  end

  it 'removes the root entry only when it is the symlink systemd made to this cache' do
    make_cache(gone_identity, age: 2 * 3600, link: false)
    elsewhere = Dir.mktmpdir('mcp-elsewhere')
    File.symlink(elsewhere, File.join(root, gone_identity))

    prune

    expect(File.symlink?(File.join(root, gone_identity))).to be(true)
    expect(File.directory?(elsewhere)).to be(true)
  ensure
    FileUtils.remove_entry(elsewhere, true)
  end

  it 'leaves a real directory at the root entry alone' do
    make_cache(gone_identity, age: 2 * 3600, link: false)
    real = File.join(root, gone_identity)
    FileUtils.mkdir_p(real)

    prune

    expect(File.directory?(real)).to be(true)
  end

  it 'rechecks for a running unit just before removing, and keeps the cache if one appeared' do
    dir = make_cache(gone_identity, age: 90 * 86_400)
    calls = 0
    flips = lambda do |_identity|
      calls += 1
      calls > 1
    end

    result = prune(running: flips)

    expect(File.directory?(dir)).to be(true)
    expect(result).to include(pruned: 0, kept_running: 1)
  end

  it 'clamps an idle age below a day up to a day' do
    dir = make_cache(live_identity, age: 3 * 3600)

    expect(prune(max_idle_seconds: 60)[:pruned]).to eq(0)
    expect(File.directory?(dir)).to be(true)
  end
end
