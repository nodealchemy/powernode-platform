# frozen_string_literal: true

module Ai
  module Teams
    class ConfigurationService
      module RoleManagement
        extend ActiveSupport::Concern

        def list_roles(team_id)
          team = find_team(team_id)
          team.ai_team_roles.ordered_by_priority
        end

        def create_role(team_id, params)
          team = find_team(team_id)

          Ai::TeamRole.create!(
            account: account,
            agent_team: team,
            role_name: params[:role_name],
            role_type: params[:role_type] || "worker",
            role_description: params[:role_description],
            responsibilities: params[:responsibilities],
            goals: params[:goals],
            capabilities: params[:capabilities] || [],
            constraints: params[:constraints] || [],
            tools_allowed: params[:tools_allowed] || [],
            priority_order: params[:priority_order] || 0,
            can_delegate: params[:can_delegate] || false,
            can_escalate: params[:can_escalate] || true,
            max_concurrent_tasks: params[:max_concurrent_tasks] || 1,
            context_access: params[:context_access] || {},
            ai_agent_id: params[:agent_id]
          )
        end

        def update_role(team_id, role_id, params)
          team = find_team(team_id)
          role = team.ai_team_roles.find(role_id)
          role.update!(params.slice(
            :role_name, :role_type, :role_description, :responsibilities,
            :goals, :capabilities, :constraints, :tools_allowed, :priority_order,
            :can_delegate, :can_escalate, :max_concurrent_tasks, :context_access
          ))
          role
        end

        def assign_agent_to_role(team_id, role_id, agent_id)
          team = find_team(team_id)
          role = team.ai_team_roles.find(role_id)
          agent = account.ai_agents.find(agent_id)
          role.update!(ai_agent: agent)
          role
        end

        def delete_role(team_id, role_id)
          team = find_team(team_id)
          role = team.ai_team_roles.find(role_id)
          role.destroy!
        end

        # Channel management

        def list_channels(team_id)
          team = find_team(team_id)
          team.ai_team_channels
        end

        def create_channel(team_id, params)
          team = find_team(team_id)

          if params[:participant_roles].present?
            params[:participant_roles].each do |role_id|
              team.ai_team_roles.find(role_id)  # Raises RecordNotFound if invalid
            end
          end

          Ai::TeamChannel.create!(
            agent_team: team,
            name: params[:name],
            channel_type: params[:channel_type] || "broadcast",
            description: params[:description],
            participant_roles: params[:participant_roles] || [],
            message_schema: params[:message_schema] || {},
            is_persistent: params[:is_persistent] != false,
            message_retention_hours: params[:message_retention_hours],
            routing_rules: params[:routing_rules] || {}
          )
        end

        def get_channel(team_id, channel_id)
          team = find_team(team_id)
          team.ai_team_channels.find(channel_id)
        end

        def update_channel(team_id, channel_id, params)
          team = find_team(team_id)
          channel = team.ai_team_channels.find(channel_id)

          if params[:participant_roles].present?
            params[:participant_roles].each do |role_id|
              team.ai_team_roles.find(role_id)
            end
          end

          channel.update!(
            name: params[:name] || channel.name,
            channel_type: params[:channel_type] || channel.channel_type,
            description: params.key?(:description) ? params[:description] : channel.description,
            participant_roles: params.key?(:participant_roles) ? params[:participant_roles] : channel.participant_roles,
            message_schema: params.key?(:message_schema) ? params[:message_schema] : channel.message_schema,
            is_persistent: params.key?(:is_persistent) ? params[:is_persistent] : channel.is_persistent,
            message_retention_hours: params.key?(:message_retention_hours) ? params[:message_retention_hours] : channel.message_retention_hours,
            routing_rules: params.key?(:routing_rules) ? params[:routing_rules] : channel.routing_rules
          )

          channel
        end

        def delete_channel(team_id, channel_id)
          team = find_team(team_id)
          channel = team.ai_team_channels.find(channel_id)
          channel.destroy!
          channel
        end

        # Template management

        def list_templates(filters = {})
          templates = Ai::TeamTemplate.all
          templates = templates.public_templates if filters[:public_only]
          templates = templates.system_templates if filters[:system_only]
          templates = templates.by_category(filters[:category]) if filters[:category].present?
          templates = templates.by_topology(filters[:topology]) if filters[:topology].present?
          templates = templates.order(usage_count: :desc)
          templates = templates.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
          templates
        end

        def get_template(template_id)
          Ai::TeamTemplate.find(template_id)
        end

        def create_template(params, user: nil)
          Ai::TeamTemplate.create!(
            account: account,
            name: params[:name],
            description: params[:description],
            category: params[:category],
            team_topology: params[:team_topology] || "hierarchical",
            role_definitions: params[:role_definitions] || [],
            channel_definitions: params[:channel_definitions] || [],
            workflow_pattern: params[:workflow_pattern] || {},
            default_config: params[:default_config] || {},
            is_public: params[:is_public] || false,
            tags: params[:tags] || [],
            created_by: user
          )
        end

        def publish_template(template_id)
          template = account.ai_team_templates.find(template_id)
          template.publish!
          template
        end
      end
    end
  end
end
