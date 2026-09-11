# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord class
  # in app/models (see ranking.rb).
  class Investigation
    # REWRITES THE OLD RANKING-FAILURE SHAPE (A6 review G2-3).
    #
    # Before the A6 state-3 batch, the conclude door recorded a ranking failure
    # as a bare string at `evidence["errors"]["ranking"]` and left the
    # investigation open. The batch replaced that writer with
    # `Ranking.record_outcome!`, which writes `evidence["ranking"]` as
    # `{state, reason, message, retryable, attempts, recorded_at}`. Nothing
    # reads the old key any more, so rows written in it are migrated rather
    # than kept readable:
    #
    #   - The string becomes a record whose reason is mapped from the message
    #     the old writer stored (`reason_for`), through `Ranking`'s own rule for
    #     gate refusals.
    #   - A row that is still OPEN is concluded on core's candidates, the way
    #     G2-2 concludes a failure on the job's last attempt. Its job ran under
    #     the old code, which never concluded a failure, so nothing will retry
    #     it. Left open, it would promise a retry and refuse every new
    #     investigation of its component.
    #   - A row a later attempt RANKED (concluded, with an agent) gets no
    #     record, because an agent's ranking clears it for new rows too.
    #   - A row that already carries the new record only loses the old key.
    #
    # Two entry points, the same split as `Ai::Providers::LiteralDefaultCleanup`:
    #   - `.auto_rewrite` is the data migration's. It acts on AUTO_LIMIT rows or
    #     fewer, changes nothing above that, and never raises, because live
    #     nodes apply pending migrations at boot.
    #   - `.operator_run` is the rake task's. It prints the count and a sample,
    #     and acts only when CONFIRM equals the current count.
    class LegacyRankingErrorRewrite
      AUTO_LIMIT = 5
      RAKE_TASK = "platform:rewrite_legacy_ranking_errors"

      # `#>` rather than `?`: ActiveRecord reads a bare `?` as a bind marker.
      LEGACY_KEY_SQL = "platform_investigations.evidence #> '{errors,ranking}' IS NOT NULL"

      GATE_PATTERN = /\ABlocked by security gate \((?<blocked_by>[^)]+)\)/
      GUARDRAIL_PREFIXES = [ "Blocked by input guardrail", "Blocked by output guardrail" ].freeze

      # Every message the old code stored for a ranker that answered unusably.
      UNUSABLE_MESSAGES = [
        "ranker returned no usable hypotheses",
        "ranker returned no output",
        "no ranking prompt could be resolved"
      ].freeze

      Outcome = Struct.new(:status, :count, :investigation_ids, :message, keyword_init: true)

      class << self
        def matching_ids
          ::Platform::Investigation.where(LEGACY_KEY_SQL).order(:id).pluck(:id)
        end

        # The migration's entry point. Never raises.
        def auto_rewrite(logger: Rails.logger)
          ids = matching_ids

          if ids.size > AUTO_LIMIT
            message = "[G2-3] #{ids.size} investigations carry the old evidence.errors.ranking shape, more than " \
                      "#{AUTO_LIMIT}, so this migration changed NOTHING. Review them with " \
                      "`bin/rails #{RAKE_TASK}`, then rewrite them with `bin/rails #{RAKE_TASK} CONFIRM=#{ids.size}`."
            logger.warn(message)
            return Outcome.new(status: :skipped, count: ids.size, investigation_ids: [], message: message)
          end

          if ids.empty?
            return Outcome.new(status: :nothing, count: 0, investigation_ids: [],
                               message: "[G2-3] no investigation carries the old ranking-error shape")
          end

          done = rewrite!(ids, logger: logger)
          Outcome.new(status: :rewritten, count: done.size, investigation_ids: done,
                      message: "[G2-3] rewrote the ranking-error shape on #{done.size} of #{ids.size} investigation(s)")
        rescue StandardError => e
          message = "[G2-3] ranking-error rewrite did not run (#{e.class}: #{e.message}); nothing changed. " \
                    "Retry with `bin/rails #{RAKE_TASK}`."
          logger.warn(message)
          Outcome.new(status: :error, count: nil, investigation_ids: [], message: message)
        end

        # The rake task's entry point. Acts only on an exact, current CONFIRM.
        def operator_run(confirm:, io: $stdout, logger: Rails.logger)
          ids = matching_ids

          io.puts "#{ids.size} investigation(s) carry the old evidence.errors.ranking shape."
          return Outcome.new(status: :nothing, count: 0, investigation_ids: [], message: "nothing to rewrite") if ids.empty?

          io.puts "  #{sample(ids).join(', ')}"

          if confirm.to_s.strip.empty?
            io.puts "Nothing changed. Re-run with CONFIRM=#{ids.size} to rewrite them."
            return Outcome.new(status: :unconfirmed, count: ids.size, investigation_ids: [], message: "unconfirmed")
          end

          unless confirm.to_s.match?(/\A\d+\z/) && confirm.to_i == ids.size
            io.puts "CONFIRM=#{confirm} does not match the current count (#{ids.size}); nothing changed."
            return Outcome.new(status: :mismatch, count: ids.size, investigation_ids: [], message: "mismatch")
          end

          done = rewrite!(ids, logger: logger)
          io.puts "Rewrote #{done.size} of #{ids.size}. Any row not rewritten is named in the log and keeps the old shape."
          Outcome.new(status: :rewritten, count: done.size, investigation_ids: done, message: "rewritten")
        end

        # The first 3 and the last 1, per the bulk-operation rule.
        def sample(ids)
          ids.size > 4 ? ids.first(3) + [ "…", ids.last ] : ids
        end

        # The record an old message becomes. `retryable` is false for every
        # rewritten row: an open one is concluded right after, and a concluded
        # one cannot be retried. The old writer kept no attempt count, and
        # inventing one would be a number nobody measured, so it is nil.
        def record_for(message, investigation, concluding:)
          reason, state = reason_for(message, investigation)
          prose = if concluding
                    "Ranking did not complete under the earlier worker (#{message}), and nothing was retrying " \
                      "it, so the investigation concluded on the platform's own candidates."
                  else
                    "Ranking did not complete: #{message}"
                  end

          { "state" => state, "reason" => reason, "message" => prose.truncate(500), "retryable" => false,
            "attempts" => nil, "recorded_at" => investigation.updated_at&.utc&.iso8601 }
        end

        # [reason, state] for a message the old code stored.
        def reason_for(message, investigation)
          ranking = ::Platform::Investigation::Ranking
          text = message.to_s

          if (gate = GATE_PATTERN.match(text)) || text.start_with?(*GUARDRAIL_PREFIXES)
            reason = ranking.refusal_reason(investigation, blocked_by: gate && gate[:blocked_by], message: text)
            state = reason == ranking::REASON_AUTOMATIC_SPEND_NEEDS_GRANT ? ranking::STATE_NOT_RUN : ranking::STATE_REFUSED
            [ reason, state ]
          elsif UNUSABLE_MESSAGES.include?(text)
            [ ranking::REASON_RANKER_UNUSABLE, ranking::STATE_FAILED ]
          else
            [ ranking::REASON_PROVIDER_ERROR, ranking::STATE_FAILED ]
          end
        end

        private

        # One transaction per row. A row that fails is logged by id and keeps
        # the old shape; the rest still proceed.
        def rewrite!(ids, logger:)
          ids.filter_map do |id|
            ::Platform::Investigation.transaction { rewrite_one!(::Platform::Investigation.lock.find(id)) }
            id
          rescue StandardError => e
            logger.warn("[G2-3] investigation #{id} was not rewritten (#{e.class}: #{e.message}); it keeps the old shape")
            nil
          end
        end

        def rewrite_one!(investigation)
          evidence = investigation.evidence.is_a?(Hash) ? investigation.evidence.deep_dup : {}
          errors = evidence["errors"].is_a?(Hash) ? evidence["errors"] : {}
          message = errors.delete("ranking").to_s
          evidence["errors"] = errors

          ranked = investigation.concluded? && investigation.agent_id.present?
          write = !ranked && !evidence["ranking"].is_a?(Hash)
          evidence["ranking"] = record_for(message, investigation, concluding: investigation.open?) if write

          investigation.update_columns(evidence: evidence, updated_at: Time.current)
          return unless write && investigation.open?

          ::Platform::InvestigationService.new(account: investigation.account).conclude!(investigation)
        end
      end
    end
  end
end
