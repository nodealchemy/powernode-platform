# frozen_string_literal: true

module Ai
  module DevLoop
    # Orchestrates an Autonomous Improvement Campaign on top of the existing Ralph-loop machinery.
    # Starting a campaign creates the Campaign record plus a dedicated, campaign-scoped Ralph loop
    # that /dev-loop drains via dev_next_task / dev_complete_task. The driver is the single seam the
    # MCP campaign_* tools call, and where decision-authority / parked-question policy is applied.
    class CampaignDriver
      DEFAULT_GUARDRAILS = [
        "One task per iteration — finish or report before pulling the next",
        "Re-verify the finding against current code BEFORE changing anything (findings rot)",
        "Write a failing test reproducing the finding FIRST; confirm it is red",
        "Independent review of the diff before committing (don't trust green alone)",
        "Commit only to the campaign branch — never develop/master, never push",
        "After 3 failed attempts on the same task, report outcome=failed and stop"
      ].freeze

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Create the campaign + its dedicated Ralph loop, mark it active, take a first snapshot.
      def start(name:, description: nil, configuration: {}, decision_authority: "trusted", stop_conditions: {})
        campaign = @account.ai_campaigns.create!(
          name: name, description: description, created_by_id: @user&.id,
          configuration: configuration || {}, decision_authority: decision_authority,
          stop_conditions: stop_conditions || {}, status: "created"
        )
        loop = create_campaign_loop(campaign)
        campaign.start!
        campaign.snapshot_progress!
        { campaign: campaign, loop: loop }
      end

      # Live status: refresh the ledger, then return the campaign summary, its open questions, its
      # recent decisions, and its loops — everything the dashboard / an operator needs.
      def status(campaign)
        campaign.snapshot_progress!
        {
          campaign: campaign.reload.summary,
          activity: campaign.activity_feed(limit: 20),
          open_questions: campaign.open_questions_list.map(&:summary),
          recent_decisions: campaign.campaign_decisions.recent(10).map(&:summary),
          loops: campaign.ralph_loops.map do |l|
            { id: l.id, name: l.name, branch: l.branch, status: l.status,
              total_tasks: l.ralph_tasks.count }
          end
        }
      end

      # Become (or renew being) the single active driver for this campaign before
      # driving it. A campaign/<id> branch + the progress ledger are mutated by
      # whoever drives the campaign; two concurrent drivers race. Returns
      # { ok: true, lease: {holder:, expires_at:} } when this holder now holds the
      # lease, or { ok: false, held_by:, expires_at: } when another driver holds it —
      # the caller backs off instead of double-driving. `holder` identifies the driver
      # (e.g. a session id); defaults to the driver's user id.
      def claim(campaign, holder: nil, ttl: nil)
        who = (holder.presence || @user&.id&.to_s)
        ok = if ttl
               campaign.acquire_driver_lease!(holder: who, ttl: ttl)
             else
               campaign.acquire_driver_lease!(holder: who)
             end
        campaign.reload
        if ok
          campaign.touch_activity!
          { ok: true, lease: campaign.driver_lease_info }
        else
          { ok: false, held_by: campaign.driver_lease_holder, expires_at: campaign.driver_lease_expires_at }
        end
      end

      # Release this campaign's single-driver lease (call when done driving). Returns
      # { ok: true } once the lease is free, { ok: false } if a different driver holds it.
      def release(campaign, holder: nil)
        who = (holder.presence || @user&.id&.to_s)
        { ok: campaign.release_driver_lease!(holder: who) }
      end

      # Answer a parked question (which can unblock its associated task downstream).
      def answer_question(campaign, question_id:, answer:)
        q = campaign.parked_questions.find(question_id)
        q.answer!(answer, user: @user)
        q.reload.summary
      end

      # Stop the campaign: pause its loops' scheduling (executors stop pulling) + mark completed.
      def stop(campaign, summary: nil)
        campaign.ralph_loops.each do |l|
          l.pause_schedule!(reason: "campaign stopped") if l.respond_to?(:pause_schedule!)
        end
        campaign.complete!(summary)
        campaign.reload.summary
      end

      # Record one completed campaign increment in a single call: mark a RalphTask
      # on the campaign loop (passed by default), log a decision, and snapshot
      # progress — so completion% reflects real work without each driver having to
      # hand-assemble those three steps (previously manual/instruction-dependent).
      # Idempotent on task_key.
      def record_increment!(campaign, title:, summary: nil, task_key: nil, decision_type: "build",
                            rationale: nil, status: "passed", metadata: {})
        loop_record = campaign.ralph_loops.order(:created_at).first
        raise ArgumentError, "campaign has no loop to record against" unless loop_record

        key = (task_key.presence || "increment-#{title}").to_s.parameterize
        key = "increment-#{SecureRandom.hex(4)}" if key.blank?
        task = loop_record.ralph_tasks.find_or_initialize_by(task_key: key[0, 120])
        task.description = summary.presence || title
        task.status = status
        task.iteration_completed_at = Time.current if Ai::RalphTask::TERMINAL_STATUSES.include?(status)
        task.metadata = (task.metadata || {}).merge(metadata)
        task.save!

        iteration = record_iteration!(loop_record, task, status: status, summary: summary.presence || title, metadata: metadata)

        decision = campaign.record_decision!(
          decision_type: decision_type, title: title, rationale: rationale,
          task: task, user: @user, metadata: metadata
        )
        campaign.snapshot_progress!
        {
          task_key: task.task_key, status: task.status,
          iteration_number: iteration&.iteration_number, decision_id: decision.id,
          campaign: campaign.reload.summary
        }
      end

      # Record a Ralph iteration for a CC-driven increment. The platform executor
      # writes RalphIteration rows per run; loops driven from Claude Code (composing
      # /improve + /dev-loop) otherwise have NO iteration history. This fills it in.
      # Idempotent-ish: re-recording the same task adds a new iteration row (each run
      # is a real iteration); callers pass a stable task_key for the task itself.
      def record_iteration!(loop_record, task, status:, summary:, metadata: {})
        iter_status = case status
                      when "failed" then "failed"
                      when "skipped" then "skipped"
                      else "completed"
                      end
        now = Time.current
        number = (loop_record.ralph_iterations.maximum(:iteration_number) || 0) + 1
        loop_record.ralph_iterations.create!(
          iteration_number: number, ralph_task: task, status: iter_status,
          started_at: now, completed_at: now, duration_ms: 0,
          checks_passed: (status == "passed"), ai_output: summary,
          git_branch: loop_record.branch, git_commit_sha: metadata["commit"]
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[CampaignDriver] record_iteration! failed: #{e.message}")
        nil
      end

      # Backfill: give existing campaign loops their campaign's display name (for the
      # execution interface), replacing the legacy "campaign-<id>" names. Idempotent.
      # Returns the count renamed.
      def relabel_campaign_loops!
        renamed = 0
        @account.ai_campaigns.find_each do |campaign|
          campaign.ralph_loops.where.not(name: campaign.name).find_each do |loop_record|
            loop_record.update!(name: campaign.name)
            renamed += 1
          end
        end
        renamed
      end

      # Request that a completed campaign change-set be landed to a target branch.
      # Creates an Ai::CampaignLand behind the approval gate (auto-approves only
      # for an autonomous campaign). The land worker drives it from there.
      def request_land(campaign, source_branch: nil, target_branch: "develop", description: nil, priority: 0)
        Ai::Land::ApprovalBinding.request_land_approval(
          campaign: campaign,
          source_branch: source_branch || campaign.ralph_loops.first&.branch,
          target_branch: target_branch,
          description: description,
          requested_by: @user,
          priority: priority
        )
      end

      private

      def create_campaign_loop(campaign)
        campaign.ralph_loops.create!(
          account: @account,
          # Human campaign name for the execution interface (loops are referenced by
          # id / campaign_id / branch, never by this name — safe to be display-friendly).
          name: campaign.name,
          description: "Drives campaign: #{campaign.name}",
          ai_tool: "claude_code",
          scheduling_mode: "manual",
          status: "pending",
          branch: "campaign/#{campaign.id}",
          max_iterations: 500,
          configuration: {
            "workload" => "improvement-campaign",
            "campaign_id" => campaign.id,
            "guardrails" => DEFAULT_GUARDRAILS
          }
        )
      end
    end
  end
end
