# frozen_string_literal: true

require 'etc'
require 'find'
require 'fileutils'
require 'set'
require_relative 'mcp_security_service'

# IMP-f074ef554781 — garbage collection for the per-account sandbox cache
# directories McpSecurityService gives every sandboxed stdio MCP child
# (IMP-bd260c0b4c00): systemd's `CacheDirectory=mcp-stdio-<21 hex>` is
# created as /var/cache/private/<identity>, with /var/cache/<identity> a
# symlink to it. They hold npm and uv caches and nothing else, are recreated
# on demand, and were never removed, so a host accumulated one per account
# that ever ran a stdio server, including deleted ones.
#
# A cache is removed when
#   - its identity belongs to no current account (after a short grace, so an
#     account created a moment ago and mid-spawn is not caught), or
#   - nothing in it has been written for the operator-set idle age.
# And never when its identity has a running unit.
#
# Everything it may delete is named by the exact identity shape under
# <cache_root>/private; a symlink is never followed, a name that merely looks
# similar is never touched, and an empty account list prunes nothing (no list
# is not "no accounts").
#
# The worker has no database: the account ids and the idle age come from the
# backend (GET /api/v1/internal/mcp/sandbox_cache_policy).
class McpSandboxCachePruner
  DEFAULT_CACHE_ROOT = '/var/cache'
  PRIVATE_DIR = 'private'
  IDENTITY_SHAPE = /\A#{Regexp.escape(McpSecurityService::SANDBOX_IDENTITY_PREFIX)}[0-9a-f]{#{McpSecurityService::SANDBOX_IDENTITY_HEX_LENGTH}}\z/

  # A cache for an unknown account must also have been untouched this long.
  UNKNOWN_ACCOUNT_GRACE_SECONDS = 3600
  # Whatever the setting says, a cache is never judged idle in less than this.
  MIN_IDLE_SECONDS = 86_400
  # A tree with more entries than this is treated as in use rather than walked
  # to the end: a stat storm on a worker host is worse than a cache kept a day.
  # (A cache a tenant pads past it, or whose mtimes are in the future, is kept too:
  # that costs the tenant its own disk, never another's data.)
  MAX_ENTRIES_WALKED = 200_000

  # systemd allocates the dynamic user the unit runs as only while a unit
  # using it is active, and nss-systemd resolves it through getpwnam, so a
  # name that resolves is a name with a running unit. Anything but a clean
  # "no such user" is treated as running.
  #
  # That only holds where nsswitch resolves passwd through systemd; without it
  # every name looks unused, so DEFAULT_NSS_READY gates the whole run.
  DEFAULT_RUNNING = lambda do |identity|
    Etc.getpwnam(identity)
    true
  rescue ArgumentError
    false
  rescue StandardError
    true
  end

  NSSWITCH_CONF = '/etc/nsswitch.conf'
  DEFAULT_NSS_READY = lambda do
    File.foreach(NSSWITCH_CONF).any? { |line| line.match?(/\A\s*passwd:.*\bsystemd\b/) }
  rescue SystemCallError
    false
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(account_ids:, max_idle_seconds:, cache_root: DEFAULT_CACHE_ROOT, now: Time.now,
                 running: DEFAULT_RUNNING, nss_ready: DEFAULT_NSS_READY, logger: Rails.logger)
    @current = Array(account_ids).map { |id| id.to_s.strip }.reject(&:empty?)
                                 .map { |id| McpSecurityService.sandbox_identity(id) }.to_set
    @idle_supplied = max_idle_seconds.to_i.positive?
    @max_idle = [max_idle_seconds.to_i, MIN_IDLE_SECONDS].max
    @nss_ready = nss_ready
    @cache_root = cache_root
    @now = now
    @running = running
    @logger = logger
  end

  # @return [Hash] { pruned:, kept_running:, kept_recent:, skipped: }
  def call
    result = { pruned: 0, kept_running: 0, kept_recent: 0, skipped: nil }
    result[:skipped] = skip_reason
    if result[:skipped]
      @logger.warn("[McpSandboxCachePruner] skipped: #{result[:skipped]}")
      return result
    end

    private_root = File.join(@cache_root, PRIVATE_DIR)
    return result unless File.directory?(private_root) && !File.symlink?(private_root)

    candidates(private_root).each { |identity| consider(private_root, identity, result) }
    @logger.info("[McpSandboxCachePruner] pruned #{result[:pruned]} sandbox cache director" \
                 "#{result[:pruned] == 1 ? 'y' : 'ies'} (kept #{result[:kept_running]} with a running unit, " \
                 "#{result[:kept_recent]} in use or within the idle age)")
    result
  end

  private

  # Anything the decision rests on that is missing means no pruning, never a default.
  def skip_reason
    return 'no current accounts were supplied' if @current.empty?
    return 'no idle age was supplied' unless @idle_supplied
    return 'this host does not resolve systemd dynamic users, so a running unit cannot be detected' unless @nss_ready.call

    nil
  end

  def candidates(private_root)
    Dir.children(private_root).grep(IDENTITY_SHAPE).sort
  rescue SystemCallError => e
    @logger.warn("[McpSandboxCachePruner] cannot list #{private_root}: #{e.message}")
    []
  end

  def consider(private_root, identity, result)
    path = File.join(private_root, identity)
    stat = File.lstat(path)
    return unless stat.directory? # a symlink or file of this name is not a cache we made

    if @running.call(identity)
      result[:kept_running] += 1
      return
    end

    idle = @now - newest_mtime(path, stat)
    threshold = @current.include?(identity) ? @max_idle : UNKNOWN_ACCOUNT_GRACE_SECONDS
    if idle < threshold
      result[:kept_recent] += 1
      return
    end

    # The unit may have started while the tree was being walked.
    if @running.call(identity)
      result[:kept_running] += 1
      return
    end

    if remove(identity, path)
      result[:pruned] += 1
    else
      @logger.warn("[McpSandboxCachePruner] #{identity} was not fully removed")
    end
  rescue SystemCallError => e
    @logger.warn("[McpSandboxCachePruner] left #{identity} in place: #{e.class}: #{e.message}")
  end

  # The newest mtime anywhere in the tree (lstat only, no symlink followed).
  # A tree too large to walk reports "now", i.e. in use.
  def newest_mtime(path, root_stat)
    newest = root_stat.mtime
    walked = 0
    Find.find(path) do |entry|
      walked += 1
      return @now if walked > MAX_ENTRIES_WALKED

      mtime = File.lstat(entry).mtime
      newest = mtime if mtime > newest
    end
    newest
  end

  # The directory first, then the link systemd made to it, so a removal that
  # fails never leaves a link-less directory. True only when the directory is gone.
  def remove(identity, path)
    FileUtils.rm_r(path, secure: true)
    link = File.join(@cache_root, identity)
    # systemd makes the link relative ("private/<identity>"); an absolute one to this very directory is ours too.
    File.delete(link) if File.symlink?(link) && ["#{PRIVATE_DIR}/#{identity}", path].include?(File.readlink(link))
    !File.exist?(path) && !File.symlink?(path)
  end
end
