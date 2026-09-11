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
        # over the internal mTLS API. The server does not run the linters
        # either (D1b): each unit hands one account's repositories to the
        # registered discovery executor, and the results come back later
        # through `DiscoveryRunService#ingest!`.
        #
        # `::Ai::…` throughout: this class is lexically inside `Api::V1::…::Ai`,
        # so an unqualified `Ai::Improvement` would resolve to
        # `Api::V1::Internal::Ai::Improvement` and raise.
        class ImprovementDiscoveryController < InternalBaseController
          # POST /api/v1/internal/ai/improvement_discovery/run   { position: n }
          #
          # ONE UNIT PER CALL (D1 review H2). A tick used to be one POST that
          # swept every account, called through the RETRYING connection inside
          # a job-level retry: one slow tick became up to eighteen concurrent
          # sweeps. Now the worker walks `DiscoveryRunService.units` by
          # position, one non-retrying POST per unit, and nothing re-sends it.
          # A unit is one account (D1b: one lease per account per tick), and
          # it dispatches rather than analyses.
          #
          # AGGREGATE COUNTS ONLY (D1 review M1). The caller is an
          # account-bound worker and this door runs every account's units, so
          # the response names no account, repository, environment or error
          # text. Per-account detail lives in that account's own audit row.
          def run
            position = unit_position
            return render_error("position must be a non-negative integer", status: :unprocessable_content) if position.nil?

            units = ::Ai::Improvement::DiscoveryRunService.units
            return render_success(unit_result(nil, position: position, total: units.size)) if position >= units.size

            account = ::Account.find_by(id: units[position])
            summary = account && run_unit(account)
            record_run(account, summary) if summary

            render_success(unit_result(summary, position: position, total: units.size))
          end

          # POST /api/v1/internal/ai/improvement_discovery/timed_out   { position: n }
          #
          # The worker stopped waiting on unit n (D1 re-verify). The unit is
          # recorded on its account as not measured, reason timeout, so the run
          # history never reads as if it was not tried. The server-side run may
          # still finish and record its own outcome later; the newest record is
          # the one DiscoveryRun.last_for answers. Aggregate answer only (M1).
          def timed_out
            position = unit_position
            return render_error("position must be a non-negative integer", status: :unprocessable_content) if position.nil?

            units = ::Ai::Improvement::DiscoveryRunService.units
            account = position < units.size ? ::Account.find_by(id: units[position]) : nil
            if account
              record_run(account, { phase: "dispatch", status: "not_measured", reason: "timeout",
                                    account_id: account.id, findings: 0, offers_created: 0,
                                    offers_deduped: 0, offers_parked: 0, analyzers_degraded: [] })
            end

            render_success({ recorded: account.present? })
          end

          private

          def unit_position
            position = Integer(params.fetch(:position, 0), exception: false)
            position.nil? || position.negative? ? nil : position
          end

          def run_unit(account)
            ::Ai::Improvement::DiscoveryRunService.new(account: account).run!
          rescue StandardError => e
            Rails.logger.error("[ImprovementDiscovery] run failed for account #{account.id}: #{e.class}: #{e.message}")
            # The class only (D1 review L4): this is written to an audit row.
            { phase: "dispatch", status: "failed", account_id: account.id, failure: e.class.name,
              offers_created: 0, offers_deduped: 0, offers_parked: 0, findings: 0, analyzers_degraded: [] }
          end

          def unit_result(summary, position:, total:)
            summary ||= {}
            remaining = [ total - position - 1, 0 ].max
            {
              ran_unit: summary.present?,
              status: summary[:status],
              findings: summary[:findings].to_i,
              offers_created: summary[:offers_created].to_i,
              offers_deduped: summary[:offers_deduped].to_i,
              offers_parked: summary[:offers_parked].to_i,
              analyzers_degraded: Array(summary[:analyzers_degraded]).size,
              position: position,
              next_position: position + 1,
              remaining: remaining,
              done: remaining.zero?
            }
          end

          # The run record, one per UNIT (an account) per tick — including a
          # skipped one,
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
