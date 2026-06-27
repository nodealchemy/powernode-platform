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

      private

      def create_campaign_loop(campaign)
        campaign.ralph_loops.create!(
          account: @account,
          name: "campaign-#{campaign.id}",
          description: "Drives improvement campaign: #{campaign.name}",
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
