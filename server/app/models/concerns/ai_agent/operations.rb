# frozen_string_literal: true

module AiAgent::Operations
  extend ActiveSupport::Concern

  # Clone agent for another account
  def clone_for_account(target_account, cloner_user)
    cloned_agent = self.dup
    cloned_agent.account = target_account
    cloned_agent.creator = cloner_user
    cloned_agent.name = "#{name} (Copy)"
    cloned_agent.slug = nil # Will be regenerated
    cloned_agent.status = "inactive"
    cloned_agent.last_executed_at = nil
    cloned_agent.mcp_registered_at = nil
    cloned_agent.save!
    cloned_agent
  end

  # Validate agent configuration
  def validate_configuration
    errors_list = []
    warnings_list = []

    # Check if agent has required fields
    errors_list << "Agent name is missing" if name.blank?
    errors_list << "Agent type is invalid" unless %w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer workflow_operations monitor].include?(agent_type)
    errors_list << "AI provider is missing or inactive" unless ai_provider&.is_active?
    errors_list << "MCP capabilities are missing" if mcp_capabilities.blank?

    # Check for warnings
    warnings_list << "Agent has never been executed" if last_executed_at.nil?
    warnings_list << "Agent description is missing" if description.blank?

    {
      valid: errors_list.empty?,
      errors: errors_list,
      warnings: warnings_list
    }
  end

  # Deactivate agent with reason
  def deactivate!(reason = nil)
    agent_metadata = self.mcp_metadata || {}
    agent_metadata["deactivated_reason"] = reason if reason.present?
    update!(status: "inactive", mcp_metadata: agent_metadata)

    # Create audit log entry
    AuditLog.create!(
      account: account,
      user: creator,
      resource_type: "AiAgent",
      resource_id: id.to_s,
      action: "updated",
      source: "system",
      severity: "medium",
      risk_level: "low",
      metadata: { "deactivation_reason" => reason }
    )
  end

  # Activate agent
  def activate!
    update!(status: "active")
  end

  class_methods do
    # Create agent from template data
    def create_from_template(account, provider, template_data, user)
      agent = new(
        account: account,
        provider: provider,
        creator: user,
        name: template_data[:name],
        description: template_data[:description],
        agent_type: template_data[:agent_type],
        mcp_capabilities: template_data[:mcp_capabilities] || [],
        mcp_tool_manifest: template_data[:mcp_tool_manifest] || {},
        version: template_data[:version] || "1.0.0",
        status: "active"
      )
      agent.save
      agent
    end

    # Search agents by name or description
    def search(query)
      return all if query.blank?
      where("name ILIKE :q OR description ILIKE :q", q: "%#{query}%")
    end

    # Get popular agents ordered by execution count
    def popular(limit: 10)
      left_joins(:ai_agent_executions)
        .group(:id)
        .order("COUNT(ai_agent_executions.id) DESC")
        .limit(limit)
    end
  end
end
