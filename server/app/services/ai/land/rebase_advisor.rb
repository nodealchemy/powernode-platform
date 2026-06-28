# frozen_string_literal: true

require "open3"

module Ai
  module Land
    # Proactively notifies the drivers of open campaigns when the target branch (develop)
    # has advanced past their campaign branch — so they rebase EARLY and surface conflicts
    # small, instead of discovering a large conflict at land time. This is the cooperative
    # half of conflict avoidance between concurrent campaigns/worktrees: when one campaign
    # lands (or develop otherwise moves), every other in-flight campaign is told it is now
    # behind and should rebase before its own land.
    #
    # Read-only against git (merge-base / rev-list / diff). Notification is deduped per
    # target SHA so a campaign is advised once per develop tip, not on every check.
    class RebaseAdvisor
      DEFAULT_TARGET = "develop"

      Advisory = Struct.new(
        :campaign, :branch, :target_branch, :target_sha, :commits_behind, :likely_conflicts,
        keyword_init: true
      )

      def initialize(account:, repository_path: nil)
        @account = account
        @repository_path = repository_path || Ai::Land::LandService.default_repository_path
      end

      # Open campaigns whose branch is behind `target_branch` (target has commits the branch
      # lacks). `exclude` skips a campaign (e.g. the one that just landed). Returns [Advisory].
      def stale_advisories(target_branch: DEFAULT_TARGET, exclude: nil)
        target_sha = rev_parse(target_branch)
        return [] if target_sha.blank?

        @account.ai_campaigns.open.filter_map do |campaign|
          next if exclude && campaign.id == exclude.id

          branch = campaign.ralph_loops.order(:created_at).first&.branch
          next if branch.blank? || !branch_exists?(branch)
          next if branch_contains?(target_branch, branch) # branch already has target's tip

          Advisory.new(
            campaign: campaign, branch: branch, target_branch: target_branch, target_sha: target_sha,
            commits_behind: count_behind(target_branch, branch),
            likely_conflicts: likely_conflict_files(target_branch, branch)
          )
        end
      end

      # Notify each stale campaign's driver (deduped per target SHA), persist the advisory
      # on the campaign, and log an activity-feed decision. Returns the advisories acted on.
      def notify_stale!(target_branch: DEFAULT_TARGET, exclude: nil)
        stale_advisories(target_branch: target_branch, exclude: exclude).select do |adv|
          already = (adv.campaign.configuration || {}).dig("rebase_advisory", "target_sha")
          next false if already == adv.target_sha # already advised for this develop tip

          announce!(adv)
          persist_advisory!(adv)
          true
        end
      end

      private

      def announce!(adv)
        user = adv.campaign.created_by
        return unless user

        conflicts = adv.likely_conflicts.first(8)
        files = conflicts.empty? ? "no overlapping files detected yet" : conflicts.join(", ")
        Notification.create_for_user(
          user,
          type: "agent_status_update",
          category: "ai",
          severity: "warning",
          title: "Rebase needed: #{adv.campaign.name}",
          message: "#{adv.target_branch} has advanced #{adv.commits_behind} commit(s) past " \
                   "#{adv.branch}. Rebase onto #{adv.target_branch} before landing to keep " \
                   "conflicts small. Likely conflicts: #{files}.",
          action_url: "/ai/campaigns/#{adv.campaign.id}",
          action_label: "View campaign"
        )
      rescue StandardError => e
        Rails.logger.warn("[RebaseAdvisor] notify failed for campaign #{adv.campaign.id}: #{e.message}")
      end

      def persist_advisory!(adv)
        cfg = (adv.campaign.configuration || {}).merge(
          "rebase_advisory" => {
            "target_branch" => adv.target_branch, "target_sha" => adv.target_sha,
            "commits_behind" => adv.commits_behind, "likely_conflicts" => adv.likely_conflicts,
            "advised_at" => Time.current.iso8601
          }
        )
        adv.campaign.update_column(:configuration, cfg) # rubocop:disable Rails/SkipsModelValidations
        adv.campaign.record_decision!(
          decision_type: "other",
          title: "Rebase needed: #{adv.target_branch} advanced #{adv.commits_behind} commit(s)",
          rationale: "Rebase #{adv.branch} onto #{adv.target_branch} before landing. Likely conflicts: " \
                     "#{adv.likely_conflicts.first(8).join(', ').presence || 'none detected'}."
        )
      end

      # ---- git (own runner, chdir to the repo — mirrors LandService#rev_parse) ----
      def git(*args)
        Open3.capture3("git", *args, chdir: @repository_path)
      end

      def rev_parse(ref)
        out, _err, status = git("rev-parse", ref)
        status.success? ? out.strip : nil
      end

      def branch_exists?(branch)
        _out, _err, status = git("rev-parse", "--verify", "--quiet", branch)
        status.success?
      end

      # True when `branch` already contains `target`'s tip (target is an ancestor of branch).
      def branch_contains?(target, branch)
        _out, _err, status = git("merge-base", "--is-ancestor", target, branch)
        status.success?
      end

      def count_behind(target, branch)
        out, _err, status = git("rev-list", "--count", "#{branch}..#{target}")
        status.success? ? out.strip.to_i : 0
      end

      def likely_conflict_files(target, branch)
        base, _err, status = git("merge-base", target, branch)
        return [] unless status.success?

        base = base.strip
        (diff_names(base, branch) & diff_names(base, target)).sort
      end

      def diff_names(from, to)
        out, _err, status = git("diff", "--name-only", "#{from}..#{to}")
        status.success? ? out.split("\n").map(&:strip).reject(&:empty?) : []
      end
    end
  end
end
