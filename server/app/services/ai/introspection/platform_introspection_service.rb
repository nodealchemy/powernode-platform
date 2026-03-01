# frozen_string_literal: true

module Ai
  module Introspection
    class PlatformIntrospectionService
      CACHE_TTL = 5.minutes
      CACHE_PREFIX = "platform_introspection"

      def initialize(account:)
        @account = account
      end

      def list_resources(type:)
        cache_key = "#{CACHE_PREFIX}:#{@account.id}:resources:#{type}"

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        result = case type.to_s
        when "agents"
          list_agents
        when "workflows"
          list_workflows
        when "pipelines"
          list_pipelines
        when "teams"
          list_teams
        else
          { error: "Unknown resource type: #{type}" }
        end

        redis.setex(cache_key, CACHE_TTL.to_i, result.to_json)
        result
      end

      def get_resource_config(type:, id:)
        case type.to_s
        when "agent"
          agent = Ai::Agent.find_by(id: id, account: @account)
          return nil unless agent
          { id: agent.id, name: agent.name, provider_id: agent.ai_provider_id, temperature: agent.temperature,
            system_prompt_length: agent.system_prompt&.length,
            status: agent.status, created_at: agent.created_at }
        when "workflow"
          workflow = Ai::Workflow.find_by(id: id, account: @account)
          return nil unless workflow
          { id: workflow.id, name: workflow.name, node_count: workflow.nodes.count,
            trigger_types: workflow.triggers.pluck(:trigger_type).uniq, status: workflow.status,
            created_at: workflow.created_at }
        when "pipeline"
          pipeline = Devops::Pipeline.find_by(id: id, account_id: @account.id)
          return nil unless pipeline
          { id: pipeline.id, name: pipeline.name, steps_count: pipeline.pipeline_steps.count,
            created_at: pipeline.created_at }
        when "team"
          team = Ai::AgentTeam.find_by(id: id, account: @account)
          return nil unless team
          { id: team.id, name: team.name, members_count: team.team_members.count,
            created_at: team.created_at }
        end
      end

      def dependency_map
        cache_key = "#{CACHE_PREFIX}:#{@account.id}:dependencies"

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        result = {
          models: {
            "Ai::Agent" => extract_associations(Ai::Agent),
            "Ai::Workflow" => extract_associations(Ai::Workflow),
            "Ai::AgentTeam" => extract_associations(Ai::AgentTeam),
            "Devops::Pipeline" => extract_associations(Devops::Pipeline)
          }
        }

        redis.setex(cache_key, CACHE_TTL.to_i, result.to_json)
        result
      end

      def capability_inventory
        cache_key = "#{CACHE_PREFIX}:#{@account.id}:capabilities"

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        result = {
          mcp_tools: list_mcp_tools,
          workflow_node_types: Ai::WorkflowNode.distinct.pluck(:node_type),
          providers: Ai::Provider.pluck(:name, :provider_type)
        }

        redis.setex(cache_key, CACHE_TTL.to_i, result.to_json)
        result
      end

      def recent_events(source_type: nil, status: nil, limit: 50)
        events = Ai::ExecutionEvent.by_account(@account.id)
        events = events.by_source_type(source_type) if source_type.present?
        events = events.by_status(status) if status.present?
        events.recent(limit).map do |event|
          {
            id: event.id,
            source_type: event.source_type,
            source_id: event.source_id,
            event_type: event.event_type,
            status: event.status,
            duration_ms: event.duration_ms,
            cost_usd: event.cost_usd&.to_f,
            error_class: event.error_class,
            error_message: event.error_message,
            created_at: event.created_at
          }
        end
      end

      private

      def list_agents
        agents = Ai::Agent.where(account: @account)
        {
          count: agents.count,
          items: agents.limit(100).map { |a| { id: a.id, name: a.name, status: a.status, provider_id: a.ai_provider_id } }
        }
      end

      def list_workflows
        workflows = Ai::Workflow.where(account: @account)
        {
          count: workflows.count,
          items: workflows.limit(100).map { |w| { id: w.id, name: w.name, status: w.status, nodes: w.nodes.count } }
        }
      end

      def list_pipelines
        pipelines = Devops::Pipeline.where(account_id: @account.id)
        {
          count: pipelines.count,
          items: pipelines.limit(100).map { |p| { id: p.id, name: p.name, steps: p.pipeline_steps.count } }
        }
      end

      def list_teams
        teams = Ai::AgentTeam.where(account: @account)
        {
          count: teams.count,
          items: teams.limit(100).map { |t| { id: t.id, name: t.name, members: t.members.count } }
        }
      end

      def extract_associations(model_class)
        model_class.reflect_on_all_associations.map do |assoc|
          { name: assoc.name, type: assoc.macro, class_name: assoc.class_name }
        rescue
          { name: assoc.name, type: assoc.macro }
        end
      end

      def list_mcp_tools
        registry = Mcp::RegistryService.new(account: @account)
        tools = registry.list_tools
        tools.map { |t| { id: t[:id] || t["id"], name: t[:name] || t["name"] } }
      rescue
        []
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      end
    end
  end
end
