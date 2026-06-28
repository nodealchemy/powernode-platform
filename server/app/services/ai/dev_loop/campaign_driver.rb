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

        decision = campaign.record_decision!(
          decision_type: decision_type, title: title, rationale: rationale,
          task: task, user: @user, metadata: metadata
        )
        campaign.snapshot_progress!
        {
          task_key: task.task_key, status: task.status, decision_id: decision.id,
          campaign: campaign.reload.summary
        }
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
