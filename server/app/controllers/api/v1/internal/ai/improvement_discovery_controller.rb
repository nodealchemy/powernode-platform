# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # D1 — the weekly discovery clock's server half (worker:
        # AiImprovementDiscoveryJob, cron weekly).
        #
        # Before this existed, improvement discovery had NO scheduled driver at
        # all: `platform.discover_improvements` returns guidance text naming the
        # analyzers a caller should run, and no cron referenced it or them (audit
        # 2026-09-10, §6.2). Every code-quality offer on the platform was
        # therefore filed by a human-driven session.
        #
        # Server-side because the worker is Sidekiq-only and reaches the server
        # over the internal mTLS API, and because the analyzer needs a working
        # copy on the node that holds the repository row.
        #
        # `::Ai::…` throughout: this class is lexically inside `Api::V1::…::Ai`,
        # so an unqualified `Ai::Improvement` would resolve to
        # `Api::V1::Internal::Ai::Improvement` and raise.
        class ImprovementDiscoveryController < InternalBaseController
          # POST /api/v1/internal/ai/improvement_discovery/run
          #
          # One tick. Iterates active accounts; the service applies the kill
          # switch and the environment ceiling per account and reports why it
          # skipped, so a tick that files nothing is distinguishable from a tick
          # that ran nothing.
          def run
            runs = []

            Account.find_each do |account|
              next unless account.active?

              summary = begin
                ::Ai::Improvement::DiscoveryRunService.new(account: account).run!
              rescue StandardError => e
                Rails.logger.error(
                  "[ImprovementDiscovery] run failed for account #{account.id}: #{e.class}: #{e.message}"
                )
                { status: "failed", account_id: account.id, skipped_reason: e.message,
                  offers_created: 0, offers_deduped: 0, findings: 0 }
              end

              record_run(account, summary)
              runs << summary
            end

            render_success(summarize(runs).merge(runs: runs))
          end

          private

          def summarize(runs)
            {
              accounts_processed: runs.count { |r| r[:status] == "completed" },
              accounts_skipped: runs.count { |r| r[:status] == "skipped" },
              accounts_failed: runs.count { |r| r[:status] == "failed" },
              findings: runs.sum { |r| r[:findings].to_i },
              offers_created: runs.sum { |r| r[:offers_created].to_i },
              offers_deduped: runs.sum { |r| r[:offers_deduped].to_i },
              analyzers_degraded: runs.flat_map { |r| Array(r[:analyzers_degraded]) }
            }
          end

          # The run record, one per ACCOUNT per tick — including a skipped one,
          # so "discovery last ran for this account at T, and declined because
          # X" is answerable. An aggregate row is not possible here and should
          # not be faked: AuditLog requires a non-null `account_id` and a
          # present `resource_id` (audit_log.rb:8,19), and `log_internal_audit`
          # rescues its own failure — so a nil-account "tick" row would be
          # silently dropped and the run history would read as empty forever.
          #
          # See the lane report for why this is an audit row and not a
          # queryable run table.
          def record_run(account, summary)
            log_internal_audit(
              "ai.improvement_discovery.run",
              "Account",
              account.id,
              summary.merge(account_id: account.id,
                            analyzers: ::Ai::Improvement::DiscoveryRunService::ANALYZERS)
            )
          end
        end
      end
    end
  end
end
