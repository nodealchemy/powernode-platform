# frozen_string_literal: true

module Ai
  module DataSources
    # Ordered FAILOVER across equivalent data-source endpoints (primary + mirrors).
    #
    # PURPOSE
    #   When the same logical read is served by several interchangeable endpoints —
    #   a primary plus one or more mirrors / fallbacks — this service tries them IN
    #   ORDER and returns the FIRST successful FetchEnvelope. It is the resilience
    #   half of the multi-source long-tail: reconciliation MERGES results from many
    #   sources; failover picks ONE healthy source from an ordered preference list.
    #
    # FULL GOVERNED FETCH PER ATTEMPT
    #   Each attempt is a complete Ai::DataSources::QueryService#call, so EVERY
    #   governance gate applies independently per source: the per-source kill flag,
    #   per-source + per-agent quota, query-time ABAC/compliance governance, the
    #   response cache (a mirror may serve a warm cache hit), SSRF egress validation,
    #   the per-source circuit breaker, schema/quality, redacted audit persistence,
    #   and cost attribution. This service adds NO fetching of its own and NO bypass —
    #   it only sequences QueryService calls and annotates the winning provenance.
    #
    # SUCCESS / FAILURE
    #   A target SUCCEEDS when its FetchEnvelope has success:true. On success we stop
    #   immediately (no further mirrors are touched) and return THAT envelope with
    #   failover provenance stamped on it. A target FAILS when:
    #     * its envelope has success:false (error / timeout / rate_limited / blocked),
    #       OR
    #     * the QueryService call raises (defensive — QueryService is documented never
    #       to raise, but a target list / construction fault is caught here and counts
    #       as a failure so we move on rather than aborting the whole failover).
    #   A failed attempt advances to the NEXT target. NO sleep / backoff between
    #   attempts (the per-source circuit breaker already governs upstream pressure).
    #
    # ALL-FAIL OUTCOME
    #   When every target fails, we return the LAST failure FetchEnvelope (the final
    #   mirror's), with failover provenance stamped (failover_used:true,
    #   failover_attempts:<n>, failover_source:nil) so the caller sees a real,
    #   audited failure envelope rather than a synthesized one. When the target list
    #   is empty/blank, we return a synthesized error envelope (nothing was tried).
    #
    # PROVENANCE AUGMENTATION (added to the returned envelope's provenance)
    #   * failover_used    : Boolean — true when more than one target was attempted
    #                        (i.e. the primary did not win outright). False when the
    #                        first target succeeded on the first try.
    #   * failover_attempts: Integer — how many targets were actually tried.
    #   * failover_source  : String|nil — slug of the target that WON, or nil when all
    #                        failed.
    #
    # RESILIENCE
    #   Never raises: a per-attempt exception is caught and treated as a failure; a
    #   blank target list yields a synthesized error envelope. The default single-
    #   source path is unaffected — callers that have exactly one target get that
    #   source's envelope with failover_used:false and failover_attempts:1.
    #
    # CONTRACT
    #   Ai::DataSources::FailoverService
    #     .new(account:, agent: nil, user: nil)
    #     #query(targets, params: {}) => FetchEnvelope (Hash)
    #   where targets is an ORDERED Array of { data_source:, endpoint: } (primary first).
    class FailoverService
      # FetchEnvelope status token for the synthesized "nothing to try" envelope.
      STATUS_ERROR = "error"

      def initialize(account:, agent: nil, user: nil)
        @account = account
        @agent = agent
        @user = user
      end

      # Try each target in order until one returns success:true; return that envelope
      # with failover provenance. If all fail, return the last failure envelope with
      # failover provenance. params are passed through verbatim to every attempt.
      #
      # @param targets [Array<Hash>] ordered; each { data_source:, endpoint: } (String
      #   or Symbol keys tolerated).
      # @param params [Hash] query params forwarded to every QueryService attempt.
      # @return [Hash] FetchEnvelope.
      def query(targets, params: {})
        normalized = normalize_targets(targets)
        # Nothing to try: return the synthesized error envelope, but still route it
        # through #augment (attempts 0, source nil) so EVERY returned envelope —
        # success, all-fail, or no-targets — carries the same three failover keys and
        # a caller can read them off provenance unconditionally.
        return augment(no_targets_envelope, attempts: 0, source: nil) if normalized.empty?

        attempts = 0
        last_failure = nil

        normalized.each do |target|
          attempts += 1
          envelope = attempt_fetch(target, params)

          if envelope[:success] == true
            return augment(envelope, attempts: attempts, source: target_slug(target))
          end

          last_failure = envelope
        end

        # All targets failed: surface the LAST real failure envelope (audited per
        # source), annotated with the failover bookkeeping. failover_source is nil
        # because nothing won.
        augment(last_failure || no_targets_envelope, attempts: attempts, source: nil)
      rescue StandardError => e
        # Defense in depth: the loop already catches per-attempt faults, so reaching
        # here means a fault in sequencing itself. Never raise into the caller.
        Rails.logger.error(
          "[DataSources::FailoverService] failover error (#{e.class}); returning error envelope"
        )
        augment(no_targets_envelope, attempts: 0, source: nil)
      end

      private

      attr_reader :account, :agent, :user

      # Run ONE governed fetch for a target. Any exception is converted into a
      # failure envelope so the caller's loop simply advances to the next mirror.
      # QueryService is documented never to raise; this guard covers a construction
      # fault (e.g. a malformed data_source/endpoint) without aborting the failover.
      def attempt_fetch(target, params)
        envelope = Ai::DataSources::QueryService.new(
          data_source: target[:data_source],
          endpoint: target[:endpoint],
          params: params || {},
          agent: agent,
          user: user
        ).call

        # Defensive: a non-Hash return (should never happen) is treated as a failure.
        return synthesized_failure(target, "non-envelope result") unless envelope.is_a?(Hash)

        envelope
      rescue StandardError => e
        Rails.logger.warn(
          "[DataSources::FailoverService] attempt failed for #{target_slug(target)} (#{e.class})"
        )
        synthesized_failure(target, redact(e.message))
      end

      # Stamp the failover bookkeeping onto a (winning or final-failure) envelope's
      # provenance WITHOUT disturbing the rest of the envelope. failover_used is true
      # whenever we tried more than one target — i.e. the primary did not win on the
      # first attempt. Provenance is normalized to a Hash if a source omitted it.
      def augment(envelope, attempts:, source:)
        env = envelope.is_a?(Hash) ? envelope.dup : {}
        prov = env[:provenance] || env["provenance"] || {}
        prov = prov.is_a?(Hash) ? prov.dup : {}

        prov[:failover_used] = attempts.to_i > 1
        prov[:failover_attempts] = attempts.to_i
        prov[:failover_source] = source

        # Write back under the symbol key (the canonical FetchEnvelope spelling) and
        # drop any stale string-keyed provenance so there is a single source of truth.
        env.delete("provenance")
        env[:provenance] = prov
        env
      end

      # Coerce the targets list into an ordered Array of { data_source:, endpoint: }
      # with symbol keys, dropping malformed entries (missing data_source/endpoint)
      # so a bad mirror config cannot break the whole failover. Order is preserved.
      def normalize_targets(targets)
        Array(targets).filter_map do |t|
          next unless t.is_a?(Hash)

          ds = t[:data_source] || t["data_source"]
          ep = t[:endpoint] || t["endpoint"]
          next if ds.nil? || ep.nil?

          { data_source: ds, endpoint: ep }
        end
      end

      # Best-effort slug for a target's data source, for provenance + logs. Never
      # raises and never leaks anything but the public slug.
      def target_slug(target)
        ds = target[:data_source]
        ds.respond_to?(:slug) ? ds.slug.to_s : nil
      rescue StandardError
        nil
      end

      # A FetchEnvelope-shaped failure for an attempt that could not even produce an
      # envelope (construction fault / non-Hash return). Mirrors the QueryService
      # error-envelope shape so the caller's loop treats it uniformly.
      def synthesized_failure(target, message)
        {
          success: false,
          data: [],
          provenance: { slug: target_slug(target), failover_synthesized: true },
          status: STATUS_ERROR,
          duration_ms: 0,
          bytes: 0,
          error: message
        }
      end

      # The "no targets supplied / all sequencing failed" envelope — nothing was
      # actually fetched, so it carries no source.
      def no_targets_envelope
        {
          success: false,
          data: [],
          provenance: {},
          status: STATUS_ERROR,
          duration_ms: 0,
          bytes: 0,
          error: "no data sources available for failover"
        }
      end

      # Redact a caught exception message before it lands in an envelope/log — defense
      # against a source/credential detail leaking through an error string.
      def redact(message)
        Ai::Security::PiiRedactionService.new(account: account).redact(
          text: message.to_s, log: false
        )[:redacted_text]
      rescue StandardError
        "data source error"
      end
    end
  end
end
