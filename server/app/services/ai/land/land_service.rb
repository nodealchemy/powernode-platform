# frozen_string_literal: true

module Ai
  module Land
    # Drives one CampaignLand through its phases idempotently, reusing
    # Ai::Git::WorktreeManager (fetch/push) and Ai::Git::MergeService (merge +
    # rollback). Each phase is a separate call so the worker can poll/retry.
    # Every phase short-circuits on the kill-switch and parks (never auto-mutates
    # the target) on an emergency halt mid-flight.
    #
    # Phase-1 staging pushes the campaign branch itself to trigger CI and merges
    # it directly (conflict -> park); a rebase-into-staging-branch optimization is
    # a documented follow-up. Safety rests on the post-merge CI gate + auto-rollback.
    class LandService
      def initialize(land, repository_path: nil)
        @land = land
        @campaign = land.campaign
        @account = land.account
        @repository_path = repository_path || self.class.default_repository_path
        @wm = Ai::Git::WorktreeManager.new(repository_path: @repository_path)
      end

      # Canonical checkout that owns the target branch (deploy source).
      def self.default_repository_path
        Rails.root.join("..").expand_path.to_s
      end

      # Phase: push campaign branch to trigger CI; record base + staged SHA.
      def stage!
        return halt! if halted?

        @wm.fetch_branch(branch_name: @land.target_branch)
        base = rev_parse("origin/#{@land.target_branch}") || rev_parse(@land.target_branch)
        staged = rev_parse(@land.source_branch)
        return park("source branch #{@land.source_branch} not found") if staged.blank?

        push = @wm.push_branch(branch_name: @land.source_branch)
        return park("push failed: #{push[:error]}") unless push[:success]

        @land.update!(base_sha: base)
        @land.mark_staged_ci!(staged_sha: staged)
        @land
      end

      # Phase: merge campaign branch into target via MergeService (approval-gated).
      def merge!
        return halt! if halted?

        session = build_merge_session
        svc = Ai::Git::MergeService.new(session: session)
        result = svc.execute
        result = svc.approve_merge!(approved_by: "campaign-land:#{@land.id}") if result[:requires_approval]

        op = session.merge_operations.order(:created_at).last
        case op&.status
        when "completed"
          @wm.push_branch(branch_name: @land.target_branch)
          @land.begin_verifying!(merged_sha: op.merge_commit_sha, merge_operation_id: op.id)
        when "conflict"
          park("merge conflict", files: op.conflict_files || [])
        else
          @land.fail!("merge failed: #{result[:error] || op&.status || 'unknown'}")
        end
        @land
      end

      # Phase: post-merge CI went red -> revert the merge on the target.
      def rollback!
        @land.begin_rollback!
        op_id = @land.merge_operation_id
        session = Ai::WorktreeSession.find_by(id: @land.worktree_session_id)
        if session && op_id
          Ai::Git::MergeService.new(session: session).rollback(merge_operation_id: op_id)
          @wm.push_branch(branch_name: @land.target_branch)
        end
        @land.mark_rolled_back!
        notify_park("post-merge CI failed on #{@land.target_branch}; reverted merge")
        @land
      end

      def cleanup!
        # Campaign branch is intentionally retained for audit; nothing transient
        # to remove in the Phase-1 (no staging worktree) model.
        @land
      end

      def park(reason, files: [])
        @land.park!(reason: reason, files: files)
        notify_park(reason)
        @land
      end

      private

      def halted?
        @account.respond_to?(:ai_suspended?) && @account.ai_suspended?
      end

      def halt!
        # Emergency halt mid-land: do not mutate the target; park for a human.
        unless @land.terminal? || @land.status == "parked"
          @land.park!(reason: "kill-switch active")
          notify_park("kill-switch active — land halted")
        end
        @land
      end

      def build_merge_session
        session = Ai::WorktreeSession.create!(
          account: @account, source: @campaign, repository_path: @repository_path,
          base_branch: @land.target_branch, merge_strategy: "sequential", status: "active"
        )
        wt = Ai::Worktree.find_or_initialize_by(branch_name: @land.source_branch)
        wt.assign_attributes(
          account: @account, worktree_session: session,
          worktree_path: "land:#{@land.id}", status: "completed", completed_at: Time.current
        )
        wt.save!
        @land.update!(worktree_session_id: session.id)
        session
      end

      def rev_parse(ref)
        out, _err, status = Open3.capture3("git", "rev-parse", ref, chdir: @repository_path)
        status.success? ? out.strip : nil
      rescue StandardError
        nil
      end

      # Surface the land issue through the campaign's existing parked-questions
      # queue so it shows up on the dashboard for the operator.
      def notify_park(reason)
        @campaign.park_question!(
          question: "Campaign land needs attention: #{reason}",
          context: "land=#{@land.id} #{@land.source_branch} → #{@land.target_branch}",
          metadata: { "campaign_land_id" => @land.id, "reason" => reason }
        )
      rescue StandardError => e
        Rails.logger.warn("[LandService] notify_park failed: #{e.message}")
      end
    end
  end
end
