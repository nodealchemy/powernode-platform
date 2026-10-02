# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Ai
  # IMP-de4ca2d3f7c5 — the outage-safe recall cache for platform memory.
  #
  # Memory lives on the platform as Ai::SharedKnowledge tagged `memory` (key memory:<slug>, tags
  # memory-<type> and memory-<slug>). A session that starts during an MCP blackout still needs
  # it, so a Stop hook (.claude/hooks/platform-memory-digest-refresh.sh) renders this digest into
  # a gitignored local file and SessionStart (session-guidance-inject.sh) prints it.
  #
  # One line per entry: `- <title> — <description first 140 chars> [memory-<slug>]`. Feedback
  # first, then by last_used_at falling back to updated_at, newest first. Capped at 120 lines and
  # 12 KB, with a generated-at + count header; a truncated digest says so.
  class MemoryDigest
    TAG = "memory"
    FEEDBACK_TAG = "memory-feedback"
    MAX_LINES = 120
    MAX_BYTES = 12 * 1024
    DESCRIPTION_CHARS = 140
    TITLE_CHARS = 120
    SLUG_CHARS = 80
    # Control characters (incl. ESC), format characters, and the Unicode line/paragraph
    # separators and NEL: none may reach a session's context from free text.
    UNSAFE = /[[:cntrl:]\p{Cf}\p{Zl}\p{Zp}\u0085]/
    KEY_PREFIX = "memory:"
    # Rows loaded for rendering: far more than the caps can ever show.
    FETCH_LIMIT = MAX_LINES * 2
    EMPTY_NOTE = "(no memory entries on the platform"

    def self.render(account:, now: Time.current)
      new(account: account, now: now).render
    end

    # Renders then replaces the file atomically: a failed render leaves the previous cache.
    # Refuses to run without an account, and never replaces a non-empty cache with an empty
    # digest: a fixture-shell or unreachable store reads as "no memory", and that must not
    # overwrite the one thing that survives an outage.
    def self.write!(path, account: ::Account.first, now: Time.current)
      raise ArgumentError, "no account to read platform memory for" if account.nil?

      body = render(account: account, now: now)
      return path if body.include?(EMPTY_NOTE) && File.size?(path)

      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{SecureRandom.hex(4)}.tmp"
      begin
        File.write(tmp, body, perm: 0o600)
        File.rename(tmp, path)
      ensure
        FileUtils.rm_f(tmp)
      end
      path
    end

    def initialize(account:, now:)
      @account = account
      @now = now
    end

    def render
      scope = ::Ai::SharedKnowledge.where(account_id: @account&.id).with_tag(TAG).not_archived
      total = scope.count
      rows = scope.order(Arel.sql(order_sql)).limit(FETCH_LIMIT).to_a

      lines = []
      bytes = 0
      rows.each do |row|
        line = entry(row)
        # Leave room for the header and the truncation note.
        break if lines.size + 2 >= MAX_LINES || bytes + line.bytesize + reserve_bytes >= MAX_BYTES

        lines << line
        bytes += line.bytesize
      end

      out = [ header(total) ] + lines
      out << "(truncated: showing #{lines.size} of #{total} entries — recall the rest via search_knowledge tags:[\"memory\"])\n" if lines.size < total
      out << "#{EMPTY_NOTE} — recall via search_knowledge tags:[\"memory\"])\n" if total.zero?
      out.join
    end

    private

    # One line of inert text: unsafe characters removed, whitespace collapsed, runs of "="
    # shortened so no entry can imitate the `=== end guidance ===` sentinel, then capped.
    def clean(text, limit)
      text.to_s.gsub(UNSAFE, " ").gsub(/\s+/, " ").gsub(/={3,}/, "==").strip[0, limit].to_s
    end

    def reserve_bytes
      1024
    end

    def order_sql
      "CASE WHEN '#{FEEDBACK_TAG}' = ANY(tags) THEN 0 ELSE 1 END, COALESCE(last_used_at, updated_at) DESC, id"
    end

    def header(total)
      "# Platform memory digest — generated #{@now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')} — #{total} entries\n"
    end

    def entry(row)
      provenance = row.provenance.is_a?(Hash) ? row.provenance : {}
      slug = clean(provenance["guidance_key"].to_s.delete_prefix(KEY_PREFIX), SLUG_CHARS).delete(" ")
      description = clean(row.content, DESCRIPTION_CHARS)
      title = clean(row.title, TITLE_CHARS)
      tail = slug.empty? ? "" : " [memory-#{slug}]"
      "- #{title} — #{description}#{tail}\n"
    end
  end
end
