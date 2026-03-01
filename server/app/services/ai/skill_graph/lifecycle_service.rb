# frozen_string_literal: true

module Ai
  module SkillGraph
    class LifecycleService
      MAX_PROPOSAL_DEPTH = 3

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Full research-to-proposal pipeline: research a topic, create a proposal with
      # overlap analysis and suggested dependencies, optionally auto-approve
      def research_and_propose(topic:, requesting_agent: nil, requesting_user: nil)
        Rails.logger.info "[SkillGraph::LifecycleService] research_and_propose for topic: #{topic.truncate(100)}"

        research_result = research_service.research(
          topic: topic,
          requesting_agent: requesting_agent
        )

        overlap_analysis = research_service.detect_overlaps(
          proposed_name: topic,
          proposed_description: topic
        )

        suggested_deps = research_service.suggest_dependencies(
          proposed_skill_attrs: { name: topic, description: topic, category: nil }
        )

        # Build confidence from research coverage
        confidence = calculate_confidence(research_result, overlap_analysis)

        proposal = create_proposal(
          attributes: {
            name: topic,
            description: "Auto-proposed skill from research on: #{topic}",
            category: infer_category(research_result),
            proposed_by_agent_id: requesting_agent&.id,
            proposed_by_user_id: requesting_user&.id,
            research_report: research_result,
            overlap_analysis: overlap_analysis,
            suggested_dependencies: suggested_deps,
            confidence_score: confidence,
            trust_tier_at_proposal: requesting_agent&.respond_to?(:trust_tier) ? requesting_agent.trust_tier : nil
          }
        )

        return proposal unless proposal.is_a?(Ai::SkillProposal)

        # Submit the proposal
        submit_proposal(proposal_id: proposal.id)

        # Detect sub-topics and create child proposals
        create_sub_proposals(proposal, research_result)

        proposal.reload
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::LifecycleService] research_and_propose failed: #{e.message}"
        { error: e.message }
      end

      # Create a proposal in draft status
      def create_proposal(attributes:)
        attrs = attributes.compact
        attrs = attrs.symbolize_keys if attrs.respond_to?(:symbolize_keys)

        proposal = Ai::SkillProposal.create!(
          attrs.merge(account: account, status: "draft")
        )

        Rails.logger.info "[SkillGraph::LifecycleService] Proposal created: #{proposal.id} (#{proposal.name})"
        proposal
      end

      # Transition a draft proposal to proposed; auto-approve if trust tier allows
      def submit_proposal(proposal_id:)
        proposal = find_proposal!(proposal_id)

        proposal.submit!
        Rails.logger.info "[SkillGraph::LifecycleService] Proposal submitted: #{proposal.id}"

        # Auto-approve if trust tier is sufficient and feature flag enabled
        if proposal.can_auto_approve? && auto_create_enabled?
          Rails.logger.info "[SkillGraph::LifecycleService] Auto-approving proposal #{proposal.id}"
          proposal.update!(auto_approved: true)
          approve_proposal(proposal_id: proposal.id, reviewer: nil)
          create_skill_from_proposal(proposal_id: proposal.id)
        end

        proposal.reload
      end

      # Approve a proposed proposal
      def approve_proposal(proposal_id:, reviewer:)
        proposal = find_proposal!(proposal_id)

        if reviewer
          proposal.approve!(reviewer)
        else
          # Auto-approval path (no reviewer)
          proposal.update!(status: "approved", reviewed_at: Time.current)
        end

        Rails.logger.info "[SkillGraph::LifecycleService] Proposal approved: #{proposal.id}"
        proposal
      end

      # Reject a proposed proposal
      def reject_proposal(proposal_id:, reviewer:, reason:)
        proposal = find_proposal!(proposal_id)

        proposal.reject!(reviewer, reason: reason)
        Rails.logger.info "[SkillGraph::LifecycleService] Proposal rejected: #{proposal.id} — #{reason}"
        proposal
      end

      # Create an actual skill from an approved proposal
      def create_skill_from_proposal(proposal_id:)
        proposal = find_proposal!(proposal_id)
        raise "Proposal must be approved to create skill" unless proposal.status == "approved"

        skill = nil

        ActiveRecord::Base.transaction do
          # Use SkillService for actual skill creation (reuse existing infrastructure)
          skill = skill_service.create_skill(
            attributes: {
              name: proposal.name,
              description: proposal.description,
              category: proposal.category || "productivity",
              system_prompt: proposal.system_prompt,
              commands: proposal.commands,
              tags: proposal.tags,
              status: "active",
              is_enabled: true,
              metadata: (proposal.metadata || {}).merge(
                "created_from_proposal" => proposal.id,
                "auto_approved" => proposal.auto_approved
              )
            }
          )

          # Sync to knowledge graph via BridgeService
          bridge_service.sync_skill(skill)

          # Create KG edges for suggested dependencies
          create_dependency_edges(skill, proposal.suggested_dependencies)

          # Snapshot initial version
          create_initial_version(skill, proposal)

          # Mark proposal as created
          proposal.mark_created!(skill)
        end

        Rails.logger.info "[SkillGraph::LifecycleService] Skill created from proposal: #{skill.id} (#{skill.name})"
        { skill: skill, proposal: proposal.reload }
      end

      # List proposals with optional filters
      def list_proposals(filters: {})
        scope = Ai::SkillProposal.for_account(account.id)

        scope = scope.by_status(filters[:status]) if filters[:status].present?
        scope = scope.where(category: filters[:category]) if filters[:category].present?
        scope.order(created_at: :desc)
      end

      private

      def find_proposal!(proposal_id)
        Ai::SkillProposal.find_by!(id: proposal_id, account_id: account.id)
      end

      def create_dependency_edges(skill, suggested_dependencies)
        return unless suggested_dependencies.is_a?(Array)

        suggested_dependencies.each do |dep|
          dep_hash = dep.is_a?(Hash) ? dep.with_indifferent_access : next
          target_id = dep_hash[:skill_id]
          relation = dep_hash[:relation_type] || "requires"
          confidence = dep_hash[:confidence] || 0.7

          bridge_service.create_skill_edge(
            source_skill_id: skill.id,
            target_skill_id: target_id,
            relation_type: relation,
            weight: confidence,
            confidence: confidence
          )
        rescue StandardError => e
          Rails.logger.warn "[SkillGraph::LifecycleService] Edge creation failed for dep #{target_id}: #{e.message}"
        end
      end

      def create_initial_version(skill, proposal)
        Ai::SkillVersion.create!(
          account: account,
          ai_skill: skill,
          version: "1.0.0",
          change_type: "manual",
          system_prompt: skill.system_prompt,
          commands: skill.commands || [],
          tags: skill.tags || [],
          change_reason: "Initial version created from proposal #{proposal.id}",
          metadata: {
            snapshot: {
              name: skill.name,
              description: skill.description,
              category: skill.category
            }
          },
          created_by_agent_id: proposal.proposed_by_agent_id,
          created_by_user_id: proposal.proposed_by_user_id,
          is_active: true,
          effectiveness_score: 0.5
        )
      end

      def create_sub_proposals(parent_proposal, research_result)
        return if proposal_depth(parent_proposal) >= MAX_PROPOSAL_DEPTH

        findings = research_result.dig(:findings, :knowledge_graph) || []
        sub_topics = findings
          .select { |f| f[:similarity].to_f.between?(0.4, 0.7) }
          .first(3)

        sub_topics.each do |finding|
          create_proposal(
            attributes: {
              name: "#{parent_proposal.name} — #{finding[:name]}",
              description: "Sub-skill discovered during research for #{parent_proposal.name}: #{finding[:description]}",
              category: parent_proposal.category,
              proposed_by_agent_id: parent_proposal.proposed_by_agent_id,
              proposed_by_user_id: parent_proposal.proposed_by_user_id,
              parent_proposal_id: parent_proposal.id,
              confidence_score: finding[:similarity].to_f * 0.8
            }
          )
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::LifecycleService] Sub-proposal creation failed: #{e.message}"
      end

      def proposal_depth(proposal)
        depth = 0
        current = proposal
        while current.parent_proposal_id.present? && depth < MAX_PROPOSAL_DEPTH + 1
          current = Ai::SkillProposal.find_by(id: current.parent_proposal_id)
          break unless current

          depth += 1
        end
        depth
      end

      def calculate_confidence(research_result, overlap_analysis)
        source_count = (research_result[:findings] || {}).values.count { |v| v.is_a?(Array) && v.any? }
        total_findings = research_result[:total_findings].to_i
        max_overlap = (overlap_analysis[:overlaps] || []).map { |o| o[:similarity].to_f }.max || 0

        # More sources = higher confidence, high overlap = lower confidence
        base = [source_count * 0.15, 0.6].min
        coverage = [total_findings * 0.02, 0.3].min
        overlap_penalty = max_overlap > 0.7 ? (max_overlap - 0.7) * 2 : 0

        [(base + coverage - overlap_penalty).round(4), 0.0].max
      end

      def infer_category(research_result)
        # Try to infer from knowledge graph findings
        kg_findings = research_result.dig(:findings, :knowledge_graph) || []
        categories = kg_findings.filter_map { |f| f.dig(:properties, "category") || f.dig(:properties, :category) }
        categories.tally.max_by { |_, count| count }&.first || "productivity"
      end

      def auto_create_enabled?
        Shared::FeatureFlagService.enabled?(:skill_lifecycle_auto_create, account)
      end

      def research_service
        @research_service ||= ResearchService.new(account)
      end

      def skill_service
        @skill_service ||= Ai::SkillService.new(account: account)
      end

      def bridge_service
        @bridge_service ||= BridgeService.new(account)
      end
    end
  end
end
