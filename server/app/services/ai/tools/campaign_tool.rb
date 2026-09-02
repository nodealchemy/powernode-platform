# frozen_string_literal: true

module Ai
  module Tools
    # MCP tools for Autonomous Improvement Campaigns. Thin wrapper over Ai::DevLoop::CampaignDriver:
    # start a campaign (+ its dedicated dev-loop), check live status (ledger + open questions +
    # decisions + loops), answer a parked question, and stop a campaign.
    class CampaignTool < BaseTool
      REQUIRED_PERMISSION = "ai.campaigns.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "campaign_answer_question", mutating: true
      declare_action "campaign_approve_proposal", mutating: true
      declare_action "campaign_check_rebase", mutating: false
      declare_action "campaign_claim", mutating: true
      declare_action "campaign_delegate", mutating: true
      declare_action "campaign_list", mutating: false
      declare_action "campaign_list_proposals", mutating: false
      declare_action "campaign_propose", mutating: true
      declare_action "campaign_record_increment", mutating: true
      declare_action "campaign_reject_proposal", mutating: true
      declare_action "campaign_release", mutating: true
      declare_action "campaign_start", mutating: true
      declare_action "campaign_status", mutating: false
      declare_action "campaign_stop", mutating: true
      declare_action "campaign_update_proposal", mutating: true

      def self.definition
        {
          name: "campaign",
          description: "Manage Autonomous Improvement Campaigns and the discovery/delegation control " \
                       "plane: propose a campaign into the queue, approve+spawn a proposal, start a " \
                       "campaign directly (and its dev-loop), check status, answer parked questions, stop it.",
          parameters: {
            action: { type: "string", required: true,
                      description: "campaign_propose | campaign_list_proposals | campaign_update_proposal | " \
                                   "campaign_approve_proposal | campaign_reject_proposal | " \
                                   "campaign_delegate | campaign_start | campaign_list | campaign_status | " \
                                   "campaign_claim | campaign_release | campaign_answer_question | " \
                                   "campaign_record_increment | campaign_check_rebase | campaign_stop" },
            campaign_id: { type: "string", required: false, description: "Campaign UUID or name" },
            proposal_id: { type: "string", required: false,
                           description: "CampaignProposal UUID (campaign_update_proposal/campaign_approve_proposal/campaign_reject_proposal)" },
            reason: { type: "string", required: false, description: "Rejection reason (campaign_reject_proposal)" },
            driver_kind: { type: "string", required: false, description: "claude_code|external_cli|platform_agent|platform_team|platform_mission (campaign_delegate)" },
            target: { type: "object", required: false, description: "Platform target ref: { agent_id|group_id|mission_id } (campaign_delegate)" },
            holder: { type: "string", required: false, description: "Driver identity for the single-driver lease (campaign_claim/release/delegate)" },
            name: { type: "string", required: false, description: "Campaign name (campaign_start)" },
            title: { type: "string", required: false, description: "Proposal title (campaign_propose)" },
            objective: { type: "string", required: false, description: "What the campaign should accomplish (campaign_propose)" },
            source: { type: "string", required: false, description: "discovery | trajectory | improvement | manual (campaign_propose)" },
            scope: { type: "string", required: false, description: "Target/repo scope label for dedupe (campaign_propose)" },
            suggested_workload: { type: "string", required: false, description: "improvement-campaign | feature-development | new-project" },
            suggested_driver: { type: "string", required: false, description: "claude_code | platform_agent | platform_team | platform_mission" },
            description: { type: "string", required: false, description: "Optional campaign description" },
            configuration: { type: "object", required: false,
                             description: "Durable config: scope/posture/ordering/keep-going" },
            decision_authority: { type: "string", required: false,
                                  description: "supervised | monitored | trusted | autonomous (default trusted)" },
            stop_conditions: { type: "object", required: false, description: "e.g. { max_failed:, completion_pct: }" },
            question_id: { type: "string", required: false, description: "Parked question UUID" },
            answer: { type: "string", required: false, description: "Answer to a parked question" },
            summary: { type: "string", required: false, description: "Increment/completion summary" },
            status: { type: "string", required: false, description: "Status filter (campaign_list / campaign_list_proposals)" },
            limit: { type: "integer", required: false, description: "Max rows to return (list actions, default 50)" }
          }
        }
      end

      def self.action_definitions
        {
          "campaign_propose" => {
            description: "Propose a new improvement/feature CAMPAIGN into the discovery/delegation queue " \
                         "(deduped per target). Use THIS for any request to create, propose, or queue a " \
                         "CAMPAIGN — NOT the generic create_proposal (which is for agent change-proposals). " \
                         "Returns the proposal; approve it with campaign_approve_proposal to spawn the campaign.",
            parameters: {
              title: { type: "string", required: true, description: "Short proposal title" },
              objective: { type: "string", required: true, description: "What the campaign should accomplish" },
              source: { type: "string", required: false, description: "discovery|trajectory|improvement|manual (default manual)" },
              scope: { type: "string", required: false, description: "Target/repo scope label (used for per-target dedupe)" },
              suggested_workload: { type: "string", required: false, description: "improvement-campaign|feature-development|new-project" },
              suggested_driver: { type: "string", required: false, description: "claude_code|platform_agent|platform_team|platform_mission" },
              decision_authority: { type: "string", required: false, description: "supervised|monitored|trusted|autonomous (default trusted)" },
              configuration: { type: "object", required: false, description: "Spawn configuration (scope/posture/plan_increments/...)" }
            }
          },
          "campaign_update_proposal" => {
            description: "Revise a proposed/queued CampaignProposal's fields before it's approved — the " \
                         "operator-directed review-round counterpart to campaign_propose (which is for " \
                         "creating/rediscovery-refreshing). Errors if the proposal is already approved, " \
                         "rejected, or spawned. Recomputes the dedupe fingerprint when scope/objective/" \
                         "suggested_workload change. Only the fields you pass are updated.",
            parameters: {
              proposal_id: { type: "string", required: true, description: "CampaignProposal UUID" },
              title: { type: "string", required: false, description: "New proposal title" },
              objective: { type: "string", required: false, description: "New objective" },
              source: { type: "string", required: false, description: "discovery|trajectory|improvement|manual" },
              scope: { type: "string", required: false, description: "New target/repo scope label" },
              suggested_workload: { type: "string", required: false, description: "improvement-campaign|feature-development|new-project" },
              suggested_driver: { type: "string", required: false, description: "claude_code|platform_agent|platform_team|platform_mission" },
              decision_authority: { type: "string", required: false, description: "supervised|monitored|trusted|autonomous" },
              configuration: { type: "object", required: false, description: "Replaces the proposal's spawn configuration" }
            }
          },
          "campaign_reject_proposal" => {
            description: "Reject a proposed/queued CampaignProposal — the operator decided not to pursue it. " \
                         "Terminal: a rejected proposal is never resurrected by a later campaign_propose " \
                         "rediscovery at the same fingerprint. Errors if already approved/rejected/spawned " \
                         "(use campaign_stop to stop an already-spawned campaign instead).",
            parameters: {
              proposal_id: { type: "string", required: true, description: "CampaignProposal UUID" },
              reason: { type: "string", required: false, description: "Why this proposal was rejected" }
            }
          },
          "campaign_list_proposals" => {
            description: "List the CAMPAIGN PROPOSAL QUEUE (the discovery/delegation control plane) for this " \
                         "account — the proposed/queued/approved/rejected/spawned campaign proposals awaiting " \
                         "review. Use THIS to answer 'what campaigns are proposed / in the discovery queue'.",
            parameters: {
              status: { type: "string", required: false, description: "Filter: proposed|queued|approved|rejected|spawned" },
              limit: { type: "integer", required: false, description: "Max rows (default 50)" }
            }
          },
          "campaign_list" => {
            description: "List this account's Autonomous Improvement CAMPAIGNS (spawned/active/completed), " \
                         "newest first. Use to answer 'what campaigns are running / exist'.",
            parameters: {
              status: { type: "string", required: false, description: "Filter: created|active|paused|completed|archived" },
              limit: { type: "integer", required: false, description: "Max rows (default 50)" }
            }
          },
          "campaign_approve_proposal" => {
            description: "Approve a queued/proposed proposal AND spawn its Ai::Campaign (and dev-loop) in one " \
                         "step — the concierge's 'create this campaign' action. Idempotent. Returns the " \
                         "proposal + the spawned campaign + its loop.",
            parameters: {
              proposal_id: { type: "string", required: true, description: "CampaignProposal UUID" }
            }
          },
          "campaign_delegate" => {
            description: "Route a campaign's dev-loop to a driver — claude_code (a Claude Code session " \
                         "drains the pull queue) or platform_agent|platform_team|platform_mission (the " \
                         "platform executor drains it). Reassignment releases the current single-driver " \
                         "lease so the new driver can claim it; for claude_code, pass holder to take the " \
                         "lease immediately.",
            parameters: {
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              driver_kind: { type: "string", required: true, description: "claude_code|external_cli|platform_agent|platform_team|platform_mission" },
              target: { type: "object", required: false, description: "Platform target ref: { agent_id|group_id|mission_id }" },
              holder: { type: "string", required: false, description: "Driver identity (claude_code: take the lease now)" }
            }
          },
          "campaign_start" => {
            description: "Start an Autonomous Improvement Campaign: creates the campaign + a dedicated " \
                         "campaign-scoped Ralph loop that /dev-loop drains. Returns the campaign + loop.",
            parameters: {
              name: { type: "string", required: true, description: "Campaign name" },
              description: { type: "string", required: false, description: "Optional campaign description" },
              configuration: { type: "object", required: false, description: "scope/posture/ordering/keep-going" },
              decision_authority: { type: "string", required: false, description: "supervised|monitored|trusted|autonomous" },
              stop_conditions: { type: "object", required: false, description: "e.g. { max_failed:, completion_pct: }" }
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
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              question_id: { type: "string", required: true, description: "Parked question UUID" },
              answer: { type: "string", required: true, description: "The operator's answer to the parked question" }
            }
          },
          "campaign_record_increment" => {
            description: "Record one completed campaign increment: marks a passed RalphTask on the campaign " \
                         "loop, logs a decision, and snapshots progress (so completion% reflects real work). " \
                         "Idempotent on task_key.",
            parameters: {
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              title: { type: "string", required: true, description: "Short increment title" },
              summary: { type: "string", required: false, description: "What was done" },
              task_key: { type: "string", required: false, description: "Stable key for idempotency" },
              decision_type: { type: "string", required: false, description: "build|unblock|skip|remove|defer|policy|escalate (default build)" },
              rationale: { type: "string", required: false, description: "Why this increment was done / decided" },
              status: { type: "string", required: false, description: "passed (default) | failed | skipped" },
              check_results: { type: "object", required: false,
                               description: "Verification evidence (e.g. {\"rspec\": \"12 examples, 0 failures\"}). " \
                                            "A passed increment records checks_passed=true ONLY when this carries " \
                                            "a green machine tally; without it the pass records as attested." }
            }
          },
          "campaign_check_rebase" => {
            description: "Advise the drivers of any open campaign whose branch is behind the target " \
                         "branch (default develop) that a rebase is needed — notifies them + flags " \
                         "likely conflicts. Run after a manual land or on a schedule (auto-lands trigger " \
                         "it automatically). Deduped per target tip.",
            parameters: {
              target_branch: { type: "string", required: false, description: "Target branch (default develop)" },
              exclude_campaign_id: { type: "string", required: false, description: "Campaign UUID to skip (e.g. the one just landed)" }
            }
          },
          "campaign_stop" => {
            description: "Stop a campaign: pauses its loops (executors stop pulling) and marks it completed.",
            parameters: {
              campaign_id: { type: "string", required: true, description: "Campaign UUID or name" },
              summary: { type: "string", required: false, description: "Completion summary" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "campaign_propose" then campaign_propose(params)
        when "campaign_update_proposal" then campaign_update_proposal(params)
        when "campaign_approve_proposal" then campaign_approve_proposal(params)
        when "campaign_reject_proposal" then campaign_reject_proposal(params)
        when "campaign_delegate" then campaign_delegate(params)
        when "campaign_list_proposals" then campaign_list_proposals(params)
        when "campaign_list" then campaign_list(params)
        when "campaign_start" then campaign_start(params)
        when "campaign_status" then campaign_status(params)
        when "campaign_claim" then campaign_claim(params)
        when "campaign_release" then campaign_release(params)
        when "campaign_answer_question" then campaign_answer_question(params)
        when "campaign_record_increment" then campaign_record_increment(params)
        when "campaign_check_rebase" then campaign_check_rebase(params)
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

      def find_proposal(id)
        return nil if id.blank?

        account.ai_campaign_proposals.where(id: id).first
      end

      def campaign_list_proposals(params)
        scope = account.ai_campaign_proposals
        scope = scope.by_status(params[:status]) if params[:status].present?
        success_result(proposals: scope.recent(params[:limit].presence&.to_i || 50).map(&:summary))
      end

      def campaign_list(params)
        scope = account.ai_campaigns
        scope = scope.where(status: params[:status]) if params[:status].present?
        success_result(campaigns: scope.recent(params[:limit].presence&.to_i || 50).map(&:summary))
      end

      def campaign_propose(params)
        return success_result(halted: true) if halted?
        return error_result("title and objective are required") if params[:title].blank? || params[:objective].blank?

        proposal = Ai::CampaignProposal.propose!(
          account: account,
          title: params[:title], objective: params[:objective],
          source: params[:source].presence || "manual",
          scope: params[:scope],
          suggested_workload: params[:suggested_workload],
          suggested_driver: params[:suggested_driver],
          decision_authority: params[:decision_authority].presence || "trusted",
          configuration: params[:configuration] || {}
        )
        success_result(proposal: proposal.summary)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      def campaign_update_proposal(params)
        return success_result(halted: true) if halted?

        proposal = find_proposal(params[:proposal_id])
        return error_result("Proposal not found") unless proposal

        attrs = params.slice(:title, :objective, :source, :scope, :suggested_workload,
                             :suggested_driver, :decision_authority, :configuration).compact
        return error_result("at least one field to update is required") if attrs.empty?

        proposal.update_fields!(**attrs)
        success_result(proposal: proposal.reload.summary)
      rescue ArgumentError => e
        error_result(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      def campaign_reject_proposal(params)
        return success_result(halted: true) if halted?

        proposal = find_proposal(params[:proposal_id])
        return error_result("Proposal not found") unless proposal
        unless Ai::CampaignProposal::PRE_APPROVAL_STATUSES.include?(proposal.status)
          return error_result("cannot reject a #{proposal.status} proposal — use campaign_stop for an already-spawned campaign")
        end

        proposal.reject!(user, reason: params[:reason])
        success_result(proposal: proposal.reload.summary)
      end

      def campaign_approve_proposal(params)
        return success_result(halted: true) if halted?

        proposal = find_proposal(params[:proposal_id])
        return error_result("Proposal not found") unless proposal

        proposal.approve!(user)
        campaign = Ai::CampaignProposals::SpawnService.new(account: account, user: user).spawn!(proposal)
        loop_record = campaign.ralph_loops.order(:created_at).first
        success_result(
          proposal: proposal.reload.summary,
          campaign: campaign.summary,
          loop: loop_record && { id: loop_record.id, name: loop_record.name, branch: loop_record.branch }
        )
      rescue ArgumentError => e
        error_result(e.message)
      end

      def campaign_delegate(params)
        return success_result(halted: true) if halted?

        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign
        return error_result("driver_kind is required") if params[:driver_kind].blank?

        success_result(
          driver.delegate(campaign, driver_kind: params[:driver_kind],
                                    target: params[:target] || {}, holder: params[:holder])
        )
      rescue ArgumentError => e
        error_result(e.message)
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

      def campaign_check_rebase(params)
        return success_result(halted: true) if halted?

        exclude = params[:exclude_campaign_id].present? ? find_campaign(params[:exclude_campaign_id]) : nil
        success_result(
          driver.notify_rebase_advisories(
            target_branch: params[:target_branch].presence || "develop", exclude: exclude
          )
        )
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
        return success_result(halted: true) if halted? # kill-switch: no ledger writes while AI-suspended

        campaign = find_campaign(params[:campaign_id])
        return error_result("Campaign not found") unless campaign
        return error_result("title is required") if params[:title].blank?

        success_result(
          driver.record_increment!(
            campaign,
            title: params[:title], summary: params[:summary], task_key: params[:task_key],
            decision_type: params[:decision_type].presence || "build",
            rationale: params[:rationale], status: params[:status].presence || "passed",
            metadata: params[:metadata] || {}, check_results: params[:check_results] || {}
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
