# frozen_string_literal: true

module Ai
  module AgentProposals
    # What approving an Ai::AgentProposal STARTS, by proposal_type. Approval is the
    # triage (the operator chose direct-to-queue); the loop guardrails still govern
    # whatever executes the work. One seam for every approval door (the controller,
    # batch_review, the gateway cascade): Ai::AgentProposal#approve! calls it.
    #
    #   feature, code_change,      a task in the account's dev-improve queue (the one
    #   process_improvement        dev_next_task drains); closed by dev_complete_task
    #                              (Ai::AgentProposals::Completion)
    #   architecture,              an Ai::CampaignProposal through the campaign_propose
    #   sweep_execution            seam; closed when the spawned campaign completes
    #   agent_create               an ACCOUNT-scoped, inactive agent, created now from the payload
    #                              (Ai::ClaudeExport::AgentImportApplier); implemented at once
    #   configuration (gitops)     the gitops apply service applies it and marks it implemented
    #   configuration (others),    ACKNOWLEDGEMENT ONLY: nothing is started. The filers of
    #   knowledge_update           these (data-source and architecture-catalog tools) expose no
    #                              apply service, so claiming a handoff would be false.
    #
    # Idempotent: the task key and the campaign-proposal scope derive from the proposal id,
    # the agent from its slug, so a replay finds what the first run made.
    class Handoff
      DEV_TASK = "dev_task"
      CAMPAIGN_PROPOSAL = "campaign_proposal"
      AGENT = "agent"
      GITOPS = "gitops"
      ACKNOWLEDGED = "acknowledged"
      KINDS = [ DEV_TASK, CAMPAIGN_PROPOSAL, AGENT, GITOPS, ACKNOWLEDGED ].freeze

      DEV_TASK_TYPES = %w[feature code_change process_improvement].freeze
      CAMPAIGN_TYPES = %w[architecture sweep_execution].freeze

      # Same 1..20 band the improvement offers use (ImprovementPromotionService#priority_for).
      TASK_PRIORITY = { "low" => 5, "medium" => 10, "high" => 15, "critical" => 20 }.freeze
      OBJECTIVE_MAX = 5_000
      CHANGES_MAX = 4_000

      class Failed < StandardError; end

      Result = Struct.new(:kind, :id, :implemented_ref, :note, keyword_init: true) do
        def details
          { "handoff_kind" => kind, "handoff_id" => id, "handoff_note" => note }.compact
        end
      end

      def self.call(proposal, actor: nil)
        new(proposal, actor: actor).call
      end

      def initialize(proposal, actor: nil)
        @proposal = proposal
        @actor = actor
      end

      def call
        type = proposal.proposal_type
        return dev_task if DEV_TASK_TYPES.include?(type)
        return campaign_proposal if CAMPAIGN_TYPES.include?(type)
        return agent if type == "agent_create"
        return gitops if type == "configuration" && gitops_source?

        acknowledged
      rescue ActiveRecord::ActiveRecordError, ArgumentError, Ai::Campaigns::Authorization::Refused,
             Ai::ClaudeExport::AgentImportApplier::Invalid => e
        raise Failed, "#{proposal.proposal_type} handoff failed: #{e.message}"
      end

      # Stable per proposal; matches the dev-improve commit convention (LandingCheck::BINDABLE_KEY).
      # Whether approving this proposal would only acknowledge it (start nothing). Decided
      # from the proposal alone, before approval, so batch_review can tell the two apart.
      def self.acknowledgement_only?(proposal)
        type = proposal.proposal_type
        return false if DEV_TASK_TYPES.include?(type) || CAMPAIGN_TYPES.include?(type) || type == "agent_create"

        !(type == "configuration" && gitops_source?(proposal))
      end

      def self.gitops_source?(proposal)
        changes = proposal.proposed_changes
        changes.is_a?(Hash) && changes["source"] == "gitops"
      end

      def self.task_key_for(proposal)
        "IMP-#{Digest::SHA256.hexdigest("agent_proposal:#{proposal.id}")[0, 12]}"
      end

      def self.campaign_scope_for(proposal)
        "agent_proposal:#{proposal.id}"
      end

      private

      attr_reader :proposal, :actor

      def account
        proposal.account
      end

      def dev_task
        loop_record = Ai::DevLoop::ImprovementPromotionService.dev_improve_loop(account)
        key = self.class.task_key_for(proposal)
        task = find_or_create_task(loop_record, key)
        Result.new(kind: DEV_TASK, id: task.id, note: "dev-improve task #{key}")
      end

      # The savepoint lets a concurrent twin's unique-key win be answered with its row
      # instead of poisoning the approval's transaction.
      def find_or_create_task(loop_record, key)
        ApplicationRecord.transaction(requires_new: true) do
          task = loop_record.ralph_tasks.find_or_initialize_by(task_key: key)
          if task.new_record?
            task.assign_attributes(task_attributes)
            task.save!
          end
          task
        end
      rescue ActiveRecord::RecordNotUnique
        loop_record.ralph_tasks.find_by!(task_key: key)
      end

      def task_attributes
        {
          description: proposal.title,
          acceptance_criteria: acceptance_criteria,
          priority: TASK_PRIORITY.fetch(proposal.priority, 10),
          execution_type: "agent",
          metadata: {
            "proposal_id" => proposal.id,
            "proposal_agent_id" => proposal.ai_agent_id,
            "kind" => proposal.proposal_type,
            "source" => "agent_proposal",
            "executor_hint" => "claude_code",
            "files" => files_hint
          }.compact
        }
      end

      def acceptance_criteria
        parts = [
          "Agent proposal #{proposal.id} (#{proposal.proposal_type}, #{proposal.priority}), approved by an operator.",
          proposal.description.presence,
          (proposal.rationale.presence && "Rationale: #{proposal.rationale}"),
          (changes_text.presence && "Proposed changes:\n#{changes_text}"),
          "Re-verify the premise against current code BEFORE changing anything. Write a failing spec FIRST and " \
          "confirm it is red. Name this task's key in the commit message. Report outcome=passed with the landed " \
          "commit_sha: that commit becomes the proposal's implemented_ref."
        ]
        parts.compact.join("\n\n")
      end

      def changes_text
        changes = proposal.proposed_changes
        return "" if changes.blank?

        JSON.pretty_generate(changes).truncate(CHANGES_MAX)
      end

      def files_hint
        files = proposal.proposed_changes.is_a?(Hash) ? proposal.proposed_changes["files"] : nil
        files.is_a?(Array) ? files.map(&:to_s) : nil
      end

      def campaign_proposal
        campaign_proposal = Ai::CampaignProposal.propose!(
          account: account,
          title: proposal.title,
          objective: (proposal.description.presence || proposal.title).to_s.truncate(OBJECTIVE_MAX),
          source: "improvement",
          scope: self.class.campaign_scope_for(proposal),
          evidence: { "proposal_id" => proposal.id, "proposal_type" => proposal.proposal_type,
                      "rationale" => proposal.rationale },
          principal: Ai::Campaigns::Authorization::AGENT_PROPOSAL_HANDOFF
        )
        Result.new(kind: CAMPAIGN_PROPOSAL, id: campaign_proposal.id, note: "campaign proposal #{campaign_proposal.id}")
      end

      def agent
        created = Ai::ClaudeExport::AgentImportApplier.new(proposal, creator: actor).apply!
        Result.new(kind: AGENT, id: created.id, implemented_ref: created.id, note: "agent #{created.slug}")
      end

      def gitops_source?
        self.class.gitops_source?(proposal)
      end

      def gitops
        Result.new(kind: GITOPS, note: "applied by the gitops apply service; it marks the proposal implemented")
      end

      def acknowledged
        Result.new(kind: ACKNOWLEDGED, note: "acknowledgement only: nothing was started, no apply service exists for this type")
      end
    end
  end
end
