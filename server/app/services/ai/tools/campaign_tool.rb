# frozen_string_literal: true

module Ai
  module Tools
    # MCP tools for Autonomous Improvement Campaigns. Thin wrapper over Ai::DevLoop::CampaignDriver:
    # start a campaign (+ its dedicated dev-loop), check live status (ledger + open questions +
    # decisions + loops), answer a parked question, and stop a campaign.
    class CampaignTool < BaseTool
      REQUIRED_PERMISSION = "ai.campaigns.manage"

      def self.definition
        {
          name: "campaign",
          description: "Manage Autonomous Improvement Campaigns: start a campaign (and its dev-loop), " \
                       "check status, answer parked questions, and stop it.",
          parameters: {
            action: { type: "string", required: true,
                      description: "campaign_start | campaign_status | campaign_claim | campaign_release | " \
                                   "campaign_answer_question | campaign_record_increment | campaign_stop" },
            campaign_id: { type: "string", required: false, description: "Campaign UUID or name" },
            holder: { type: "string", required: false, description: "Driver identity for the single-driver lease (campaign_claim/release)" },
            name: { type: "string", required: false, description: "Campaign name (campaign_start)" },
            description: { type: "string", required: false },
            configuration: { type: "object", required: false,
                             description: "Durable config: scope/posture/ordering/keep-going" },
            decision_authority: { type: "string", required: false,
                                  description: "supervised | monitored | trusted | autonomous (default trusted)" },
            stop_conditions: { type: "object", required: false, description: "e.g. { max_failed:, completion_pct: }" },
            question_id: { type: "string", required: false },
            answer: { type: "string", required: false },
            summary: { type: "string", required: false }
          }
        }
      end

      def self.action_definitions
        {
          "campaign_start" => {
            description: "Start an Autonomous Improvement Campaign: creates the campaign + a dedicated " \
                         "campaign-scoped Ralph loop that /dev-loop drains. Returns the campaign + loop.",
            parameters: {
              name: { type: "string", required: true, description: "Campaign name" },
              description: { type: "string", required: false },
              configuration: { type: "object", required: false, description: "scope/posture/ordering/keep-going" },
              decision_authority: { type: "string", required: false, description: "supervised|monitored|trusted|autonomous" },
              stop_conditions: { type: "object", required: false }
            }
          },
          "campaign_status" => {
            description: "Live status: refreshes the ledger and returns the campaign summary, open parked " \
                         "questions, recent decisions, and its loops.",
            parameters: { campaign_id: { type: "string", required: true, description: "Campaign UUID or name" } }
          },
          "campaign_claim" => {
            description: "Become the single active driver for a campaign before driving it. Returns " \
                         "ok:true with the lease when acquired/renewed, or ok:false with held_by when " \
                         "another driver holds it (back off instead of double-driving the campaign/<id> branch).",
            parameters: {
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              holder: { type: "string", required: false, description: "Driver identity (defaults to your user id)" }
            }
          },
          "campaign_release" => {
            description: "Release a campaign's single-driver lease when done driving it.",
            parameters: {
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              holder: { type: "string", required: false, description: "Driver identity (defaults to your user id)" }
            }
          },
          "campaign_answer_question" => {
            description: "Answer a parked question (can unblock its associated task).",
            parameters: {
              campaign_id: { type: "string", required: true },
              question_id: { type: "string", required: true },
              answer: { type: "string", required: true }
            }
          },
          "campaign_record_increment" => {
            description: "Record one completed campaign increment: marks a passed RalphTask on the campaign " \
                         "loop, logs a decision, and snapshots progress (so completion% reflects real work). " \
                         "Idempotent on task_key.",
            parameters: {
              campaign_id: { type: "string", required: true },
              title: { type: "string", required: true, description: "Short increment title" },
              summary: { type: "string", required: false, description: "What was done" },
              task_key: { type: "string", required: false, description: "Stable key for idempotency" },
              decision_type: { type: "string", required: false, description: "build|unblock|skip|remove|defer|policy|escalate (default build)" },
              rationale: { type: "string", required: false },
              status: { type: "string", required: false, description: "passed (default) | failed | skipped" }
            }
          },
          "campaign_stop" => {
            description: "Stop a campaign: pauses its loops (executors stop pulling) and marks it completed.",
            parameters: {
              campaign_id: { type: "string", required: true },
              summary: { type: "string", required: false, description: "Completion summary" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "campaign_start" then campaign_start(params)
        when "campaign_status" then campaign_status(params)
        when "campaign_claim" then campaign_claim(params)
        when "campaign_release" then campaign_release(params)
        when "campaign_answer_question" then campaign_answer_question(params)
        when "campaign_record_increment" then campaign_record_increment(params)
        when "campaign_stop" then campaign_stop(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def halted?
        account.respond_to?(:ai_suspended?) && account.ai_suspended?
      end

      def driver
        Ai::DevLoop::CampaignDriver.new(account: account, user: user)
      end

      def find_campaign(id)
        return nil if id.blank?

        account.ai_campaigns.where(id: id).first || account.ai_campaigns.find_by(name: id)
      end

      def campaign_start(params)
        return success_result(halted: true) if halted?
        return error_result("name is required") if params[:name].blank?

        result = driver.start(
          name: params[:name], description: params[:description],
          configuration: params[:configuration] || {},
          decision_authority: params[:decision_authority].presence || "trusted",
          stop_conditions: params[:stop_conditions] || {}
        )
        success_result(
          campaign: result[:campaign].summary,
          loop: { id: result[:loop].id, name: result[:loop].name, branch: result[:loop].branch }
        )
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      def campaign_status(params)
        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign

        success_result(driver.status(campaign))
      end

      def campaign_claim(params)
        return success_result(halted: true) if halted?

        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign

        success_result(driver.claim(campaign, holder: params[:holder]))
      rescue ArgumentError => e
        error_result(e.message)
      end

      def campaign_release(params)
        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign

        success_result(driver.release(campaign, holder: params[:holder]))
      end

      def campaign_answer_question(params)
        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign
        return error_result("question_id and answer are required") if params[:question_id].blank? || params[:answer].blank?

        success_result(question: driver.answer_question(campaign, question_id: params[:question_id], answer: params[:answer]))
      rescue ActiveRecord::RecordNotFound
        error_result("Question not found")
      end

      def campaign_record_increment(params)
        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign
        return error_result("title is required") if params[:title].blank?

        success_result(
          driver.record_increment!(
            campaign,
            title: params[:title], summary: params[:summary], task_key: params[:task_key],
            decision_type: params[:decision_type].presence || "build",
            rationale: params[:rationale], status: params[:status].presence || "passed",
            metadata: params[:metadata] || {}
          )
        )
      rescue ArgumentError => e
        error_result(e.message)
      end

      def campaign_stop(params)
        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign

        success_result(campaign: driver.stop(campaign, summary: params[:summary]))
      end
    end
  end
end
