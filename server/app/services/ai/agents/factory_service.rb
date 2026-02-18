# frozen_string_literal: true

module Ai
  module Agents
    class FactoryService
      MAX_SPAWN_DEPTH = 5
      MAX_ACTIVE_CHILDREN = 10

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Spawn a new agent programmatically
      # @param parent [Ai::Agent] The parent agent (nil for root agents)
      # @param config [Hash] Agent configuration
      # @return [Hash] { success: Boolean, agent: Ai::Agent, lineage: Ai::AgentLineage }
      def spawn(parent:, config:)
        validate_spawn!(parent, config)

        ActiveRecord::Base.transaction do
          agent = create_agent(parent, config)
          lineage = create_lineage(parent, agent, config[:spawn_reason])
          trust_score = initialize_trust(agent, parent)
          budget = allocate_budget(agent, parent, config[:budget_cents])

          provision_workspace(agent) if config[:workspace]
          provision_sandbox(agent) if config[:sandbox]
          auto_assign_skills_from_parent(agent, parent) if parent

          Rails.logger.info("[AgentFactory] Spawned agent #{agent.id} from parent #{parent&.id}")

          {
            success: true,
            agent: agent,
            lineage: lineage,
            trust_score: trust_score,
            budget: budget
          }
        end
      rescue StandardError => e
        Rails.logger.error("[AgentFactory] Failed to spawn agent: #{e.message}")
        { success: false, error: e.message }
      end

      # Terminate an agent and optionally cascade to children
      # @param agent [Ai::Agent] Agent to terminate
      # @param policy [String] Termination policy: cascade, orphan, graceful
      # @param reason [String] Reason for termination
      def terminate(agent:, policy: nil, reason: "manual")
        policy ||= agent.try(:termination_policy) || "graceful"

        ActiveRecord::Base.transaction do
          case policy
          when "cascade"
            terminate_cascade(agent, reason)
          when "orphan"
            terminate_orphan(agent, reason)
          when "graceful"
            terminate_graceful(agent, reason)
          else
            Rails.logger.warn("[AgentFactory] Unknown termination policy: #{policy}, using graceful")
            terminate_graceful(agent, reason)
          end
        end

        Rails.logger.info("[AgentFactory] Terminated agent #{agent.id} with policy=#{policy}")
        { success: true, agent_id: agent.id, policy: policy }
      rescue StandardError => e
        Rails.logger.error("[AgentFactory] Failed to terminate agent #{agent.id}: #{e.message}")
        { success: false, error: e.message }
      end

      # Get the lineage tree for an agent
      def lineage_tree(agent:, depth: 3)
        build_lineage_tree(agent, depth, 0)
      end

      # Get all active children of an agent
      def active_children(agent:)
        Ai::AgentLineage
          .where(parent_agent_id: agent.id)
          .active
          .includes(:child_agent)
          .map(&:child_agent)
      end

      # Get the root ancestor of an agent
      def root_ancestor(agent:)
        current = agent
        visited = Set.new

        loop do
          lineage = Ai::AgentLineage.for_child(current.id).active.first
          break unless lineage
          break if visited.include?(lineage.parent_agent_id)

          visited.add(current.id)
          current = lineage.parent_agent
        end

        current
      end

      private

      def validate_spawn!(parent, config)
        raise ArgumentError, "Agent name is required" unless config[:name].present?

        return unless parent

        # Check spawn depth
        depth = calculate_depth(parent)
        max_depth = parent.try(:max_spawn_depth) || MAX_SPAWN_DEPTH
        raise "Maximum spawn depth (#{max_depth}) exceeded" if depth >= max_depth

        # Check active children limit
        children_count = Ai::AgentLineage.for_parent(parent.id).active.count
        raise "Maximum active children (#{MAX_ACTIVE_CHILDREN}) exceeded" if children_count >= MAX_ACTIVE_CHILDREN

        # Check trust level allows spawning
        trust = Ai::AgentTrustScore.find_by(agent_id: parent.id)
        if trust && trust.tier == "supervised"
          raise "Supervised agents cannot spawn children"
        end
      end

      def create_agent(parent, config)
        Ai::Agent.create!(
          account: account,
          name: config[:name],
          description: config[:description] || "Spawned by #{parent&.name || 'system'}",
          agent_type: config[:agent_type] || parent&.agent_type || "assistant",
          ai_provider_id: config[:provider_id] || parent&.ai_provider_id,
          creator_id: config[:creator_id] || parent&.creator_id,
          status: "active",
          metadata: (config[:metadata] || {}).merge(
            spawned: true,
            parent_agent_id: parent&.id,
            spawn_depth: parent ? calculate_depth(parent) + 1 : 0
          ),
          parent_agent_id: parent&.id,
          trust_level: "supervised",
          termination_policy: config[:termination_policy] || "graceful",
          max_spawn_depth: [(parent&.max_spawn_depth || MAX_SPAWN_DEPTH) - 1, 0].max,
          autonomy_config: config[:autonomy_config] || {}
        )
      end

      def create_lineage(parent, child, reason)
        return nil unless parent

        Ai::AgentLineage.create!(
          account: account,
          parent_agent: parent,
          child_agent: child,
          spawn_reason: reason || "programmatic_spawn",
          spawned_at: Time.current,
          metadata: {
            parent_trust_level: parent.try(:trust_level),
            parent_type: parent.agent_type
          }
        )
      end

      def initialize_trust(agent, parent)
        # Child starts at supervised, inheriting reduced parent scores
        parent_trust = parent ? Ai::AgentTrustScore.find_by(agent_id: parent.id) : nil

        Ai::AgentTrustScore.create!(
          account: account,
          agent: agent,
          reliability: parent_trust ? [parent_trust.reliability * 0.5, 0.3].max : 0.5,
          cost_efficiency: 0.5,
          safety: 1.0,
          quality: parent_trust ? [parent_trust.quality * 0.5, 0.3].max : 0.5,
          speed: 0.5,
          overall_score: 0.5,
          tier: "supervised",
          last_evaluated_at: Time.current,
          evaluation_count: 0,
          evaluation_history: []
        )
      end

      def allocate_budget(agent, parent, budget_cents)
        return nil unless parent && budget_cents.present?

        parent_budget = Ai::AgentBudget.where(agent_id: parent.id).active.first
        return nil unless parent_budget

        parent_budget.allocate_child(agent: agent, amount_cents: budget_cents)
      end

      def provision_workspace(agent)
        workspace_service = Ai::Git::AgentWorkspaceService.new(account: account)
        workspace_service.provision_workspace(agent: agent)
      rescue StandardError => e
        Rails.logger.warn("[AgentFactory] Failed to provision workspace for #{agent.id}: #{e.message}")
      end

      def provision_sandbox(agent)
        sandbox_service = Ai::Runtime::SandboxManagerService.new(account: account)
        sandbox_service.create_sandbox(agent: agent)
      rescue StandardError => e
        Rails.logger.warn("[AgentFactory] Failed to provision sandbox for #{agent.id}: #{e.message}")
      end

      def auto_assign_skills_from_parent(agent, parent)
        return unless parent.respond_to?(:skills) && parent.skills.any?
        return unless account.ai_knowledge_graph_nodes.active.skill_nodes.exists?

        bridge = Ai::SkillGraph::BridgeService.new(account)
        parent.skills.each do |skill|
          neighbors = bridge.auto_detect_relationships(skill)
          relevant_ids = (neighbors || []).map { |n| n[:skill_id] }.compact
          relevant_ids.each do |skill_id|
            agent.ai_agent_skills.find_or_create_by!(ai_skill_id: skill_id)
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.debug("[AgentFactory] Skill assignment skipped for #{agent.id}: #{e.message}")
          end
        end
      rescue => e
        Rails.logger.warn("[AgentFactory] Auto skill assignment failed for #{agent.id}: #{e.message}")
      end

      def calculate_depth(agent)
        depth = 0
        current_id = agent.id
        visited = Set.new

        loop do
          break if visited.include?(current_id)

          visited.add(current_id)
          lineage = Ai::AgentLineage.for_child(current_id).active.first
          break unless lineage

          depth += 1
          current_id = lineage.parent_agent_id
        end

        depth
      end

      def terminate_cascade(agent, reason)
        # Terminate all children first (depth-first)
        Ai::AgentLineage.for_parent(agent.id).active.find_each do |lineage|
          terminate_cascade(lineage.child_agent, "parent_cascade: #{reason}")
        end

        finalize_termination(agent, reason)
      end

      def terminate_orphan(agent, reason)
        # Detach children - they become root agents
        Ai::AgentLineage.for_parent(agent.id).active.find_each do |lineage|
          lineage.terminate!(reason: "parent_orphaned")
        end

        finalize_termination(agent, reason)
      end

      def terminate_graceful(agent, reason)
        # Wait for active children to complete, then terminate
        children = Ai::AgentLineage.for_parent(agent.id).active

        if children.exists?
          Rails.logger.info("[AgentFactory] Agent #{agent.id} has active children, marking for pending termination")
          agent.update!(status: "inactive", metadata: agent.metadata.merge(
            pending_termination: true,
            termination_reason: reason,
            termination_requested_at: Time.current.iso8601
          ))
        else
          finalize_termination(agent, reason)
        end
      end

      def finalize_termination(agent, reason)
        # Mark lineage as terminated
        Ai::AgentLineage.for_child(agent.id).active.find_each do |lineage|
          lineage.terminate!(reason: reason)
        end

        # Archive the agent
        agent.update!(status: "archived", metadata: agent.metadata.merge(
          terminated_at: Time.current.iso8601,
          termination_reason: reason
        ))
      end

      def build_lineage_tree(agent, max_depth, current_depth)
        return nil if current_depth > max_depth

        children = Ai::AgentLineage
          .for_parent(agent.id)
          .active
          .includes(:child_agent)
          .map { |l| build_lineage_tree(l.child_agent, max_depth, current_depth + 1) }
          .compact

        {
          id: agent.id,
          name: agent.name,
          type: agent.agent_type,
          status: agent.status,
          trust_level: agent.try(:trust_level),
          depth: current_depth,
          children: children
        }
      end
    end
  end
end
