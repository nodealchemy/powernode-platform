# frozen_string_literal: true

module Ai
  module Discovery
    # Turns standing improvement signals into campaign PROPOSALS — the discovery half of
    # the Campaign Discovery & Delegation Control Plane. Rather than 1:1 mapping each
    # ImprovementRecommendation to a proposal, it AGGREGATES the pending backlog per
    # target into one campaign-sized proposal ("drain N recommendations for <target>"),
    # deduped per target via CampaignProposal.propose!. A worker cron invokes this per
    # account; re-running refreshes the open proposal (count/evidence) rather than
    # enqueuing a duplicate, and never resurrects one the operator already decided.
    class CampaignProposalService
      # Minimum pending recommendations on a target for it to be worth a campaign.
      MIN_BACKLOG = 1

      def initialize(account:)
        @account = account
      end

      # Returns the proposals created or refreshed this scan.
      def scan!
        propose_from_improvement_backlog.compact
      end

      private

      attr_reader :account

      # Group the account's pending improvement recommendations by polymorphic target;
      # each target with a backlog becomes (or refreshes) one improvement-campaign proposal.
      def propose_from_improvement_backlog
        pending = account.ai_improvement_recommendations.pending.to_a
        return [] if pending.empty?

        pending.group_by { |rec| [rec.target_type, rec.target_id] }.filter_map do |(target_type, target_id), recs|
          next if recs.size < MIN_BACKLOG

          label = target_label(target_type, target_id)
          type_counts = recs.group_by(&:recommendation_type).transform_values(&:size)

          Ai::CampaignProposal.propose!(
            account: account,
            # Title carries the live count (refreshed each scan; NOT part of the fingerprint).
            title: "Drain #{recs.size} improvement recommendation(s) for #{label}",
            # Objective is STABLE per target (no count) so the per-target fingerprint is
            # stable across scans — a growing backlog refreshes, never duplicates.
            objective: "Drain the pending improvement-recommendation backlog for #{label}. " \
                       "Re-verify each finding against current code, fix test-first, and clear the backlog.",
            source: "improvement",
            scope: target_scope(target_type, target_id),
            suggested_workload: "improvement-campaign",
            evidence: {
              "target_type" => target_type,
              "target_id" => target_id,
              "recommendation_ids" => recs.map(&:id),
              "type_counts" => type_counts,
              "count" => recs.size,
              "max_confidence" => recs.filter_map(&:confidence_score).map(&:to_f).max
            }
          )
        end
      end

      # Human label for the target (repo full_name when it resolves to a GitRepository).
      def target_label(target_type, target_id)
        repo_full_name(target_type, target_id) ||
          "#{target_type.demodulize.underscore.humanize.downcase} #{target_id}"
      end

      # Stable scope string for fingerprinting (repo full_name preferred, else type:id).
      def target_scope(target_type, target_id)
        repo_full_name(target_type, target_id) || "#{target_type}:#{target_id}"
      end

      def repo_full_name(target_type, target_id)
        return nil unless target_type == "Devops::GitRepository"

        Devops::GitRepository.find_by(id: target_id)&.full_name.presence
      end
    end
  end
end
