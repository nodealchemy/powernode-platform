# frozen_string_literal: true

module Ai
  module AgentProposals
    # One-off ops repair. Before "expired" existed, Ai::ProposalService#expire_overdue!
    # wrote "withdrawn" with reviewed_at nil, so a lapse looked exactly like the agent's
    # own retraction. A lapse is recognisable by timing: it was written by the sweep AFTER
    # the review deadline, whereas an agent's own withdraw! before the deadline was not.
    #
    #   status = 'withdrawn' AND reviewed_at IS NULL AND updated_at >= review_deadline
    #
    # DRY RUN BY DEFAULT: prints the count, the first 3 and the last 1 of the selection and
    # a full report of every withdrawn row, changes nothing. `apply: true` (APPLY=1 in the
    # rake task) marks each selected row expired and writes one ai.proposal.expired audit
    # row per change. Idempotent: once applied the rows no longer match.
    class ExpiryBackfill
      PREVIEW_HEAD = 3

      def initialize(apply: false, account_id: nil, io: nil)
        @apply = apply
        @account_id = account_id
        @io = io
      end

      def candidates
        scope = Ai::AgentProposal.where(status: "withdrawn", reviewed_at: nil)
                                 .where("ai_agent_proposals.review_deadline IS NOT NULL AND ai_agent_proposals.updated_at >= ai_agent_proposals.review_deadline")
        scope = scope.where(account_id: @account_id) if @account_id.present?
        scope.includes(:agent).order(:created_at, :id)
      end

      def run
        rows = candidates.to_a
        say "#{@apply ? 'APPLY' : 'DRY RUN'}: This will affect #{rows.size} proposal(s)."
        preview(rows)
        say(@apply ? "" : "Nothing was changed. Re-run with APPLY=1 to apply.")
        apply!(rows) if @apply
        full_report
        { applied: @apply, count: rows.size, ids: rows.map(&:id) }
      end

      private

      def preview(rows)
        return if rows.empty?

        shown = rows.first(PREVIEW_HEAD)
        shown += [ rows.last ] unless shown.include?(rows.last)
        say "Selection (first #{PREVIEW_HEAD} and last 1):"
        shown.each { |row| say "  #{line(row)}" }
        say "  ... #{rows.size - shown.size} more" if rows.size > shown.size
      end

      def apply!(rows)
        rows.each do |row|
          ActiveRecord::Base.transaction do
            row.update!(status: "expired")
            Audit.record!(row, "expired", actor: nil, source: "system",
                          details: { "backfill" => true, "previous_status" => "withdrawn" })
          end
        end
        say "Marked #{rows.size} proposal(s) expired, one audit row each."
      end

      def full_report
        scope = Ai::AgentProposal.where(status: "withdrawn")
        scope = scope.where(account_id: @account_id) if @account_id.present?
        all = scope.includes(:agent).order(:created_at, :id).to_a
        say ""
        say "ALL WITHDRAWN ROWS (#{all.size}): title | type | filer agent | created"
        all.each { |row| say "  #{row.title} | #{row.proposal_type} | #{row.agent&.name} | #{row.created_at.to_date}" }
      end

      def line(row)
        "#{row.id}  #{row.title}  #{row.proposal_type}  #{row.agent&.name}  #{row.created_at.iso8601}"
      end

      def say(text)
        (@io || $stdout).puts(text)
      end
    end
  end
end
