# frozen_string_literal: true

namespace :mcp do
  desc "Generate MCP tool catalog from PlatformApiToolRegistry action_definitions"
  task generate_tool_catalog: :environment do
    registry = Ai::Tools::PlatformApiToolRegistry::TOOLS
    output_path = Rails.root.join("..", "docs", "reference", "auto", "mcp-tools.md")

    # Group actions by registry comment categories
    categories = {
      "Project & CI/CD" => [],
      "Agent Management" => [],
      "Agent Containers" => [],
      "Team Management" => [],
      "Workflow Management" => [],
      "Pipeline Management" => [],
      "Memory Management" => [],
      "Knowledge & RAG" => [],
      "KB Article Management" => [],
      "Page Management" => [],
      "Compound Learning" => [],
      "Shared Knowledge" => [],
      "Skills" => [],
      "Knowledge Quality" => [],
      "Knowledge Graph" => [],
      "AI Safety & Autonomy" => [],
      "Workspace & Communication" => [],
      "Activity Monitoring" => [],
      "System Health" => [],
      "Concierge" => [],
      "Image Generation" => [],
      "Docker Management" => []
    }

    # Map tool classes to categories based on registry comments
    class_to_category = {
      "Ai::Tools::ProjectInitTool" => "Project & CI/CD",
      "Ai::Tools::RunnerDispatchTool" => "Project & CI/CD",
      "Ai::Tools::AgentManagementTool" => "Agent Management",
      "Ai::Tools::ContainerDeploymentTool" => "Agent Containers",
      "Ai::Tools::ContainerStatusTool" => "Agent Containers",
      "Ai::Tools::ContainerLogsTool" => "Agent Containers",
      "Ai::Tools::ContainerTerminateTool" => "Agent Containers",
      "Ai::Tools::TeamManagementTool" => "Team Management",
      "Ai::Tools::WorkflowManagementTool" => "Workflow Management",
      "Ai::Tools::PipelineManagementTool" => "Pipeline Management",
      "Ai::Tools::MemoryTool" => "Memory Management",
      "Ai::Tools::KnowledgeTool" => "Knowledge & RAG",
      "Ai::Tools::RagManagementTool" => "Knowledge & RAG",
      "Ai::Tools::ApiReferenceTool" => "Knowledge & RAG",
      "Ai::Tools::KbArticleManagementTool" => "KB Article Management",
      "Ai::Tools::PageManagementTool" => "Page Management",
      "Ai::Tools::LearningTool" => "Compound Learning",
      "Ai::Tools::SharedKnowledgeTool" => "Shared Knowledge",
      "Ai::Tools::SkillTool" => "Skills",
      "Ai::Tools::KnowledgeQualityTool" => "Knowledge Quality",
      "Ai::Tools::KnowledgeGraphTool" => "Knowledge Graph",
      "Ai::Tools::KillSwitchTool" => "AI Safety & Autonomy",
      "Ai::Tools::AgentAutonomyTool" => "AI Safety & Autonomy",
      "Ai::Tools::ConversationTool" => "Conversations & Workspaces",
      "Ai::Tools::ActivityMonitorTool" => "Activity Monitoring",
      "Ai::Tools::IntegrationHealthTool" => "System Health",
      "Ai::Tools::ImageGenerationTool" => "Image Generation",
      "Ai::Tools::DockerContainerTool" => "Docker Management",
      "Ai::Tools::DockerServiceTool" => "Docker Management",
      "Ai::Tools::DockerStackTool" => "Docker Management",
      "Ai::Tools::DockerClusterTool" => "Docker Management",
      "Ai::Tools::DockerHostTool" => "Docker Management",
      "Ai::Tools::DockerImageTool" => "Docker Management",
      "Ai::Tools::DockerNetworkVolumeTool" => "Docker Management",
      "Ai::Tools::RepoManagementTool" => "Project & CI/CD",
      "Ai::Tools::AgentMemoryManagementTool" => "Memory Management",
      "Ai::Tools::GovernanceTool" => "AI Safety & Autonomy",
      "Ai::Tools::CoordinationTool" => "AI Safety & Autonomy",
      "Ai::Tools::SelfImprovementTool" => "AI Safety & Autonomy",
      "Ai::Tools::CampaignTool" => "Improvement Campaigns"
    }

    # Collect action definitions grouped by category
    tool_classes_seen = Set.new
    action_count = 0

    registry.each do |action_name, class_name|
      category = class_to_category[class_name] || "Uncategorized"
      categories[category] ||= []

      begin
        klass = class_name.constantize
        action_defs = klass.action_definitions

        if action_defs.key?(action_name)
          defn = action_defs[action_name]
        else
          defn = { description: klass.definition[:description], parameters: klass.definition[:parameters]&.except(:action) || {} }
        end

        # Publish the permission that ACTUALLY gates this action, not the class
        # floor. Laddered tools resolve dispatch as
        # `ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION` (see
        # Ai::Tools::SystemFleetTool#required_perm_for and its 25 siblings), so
        # emitting only the floor understated the real bar on 337 of the 604
        # advertised actions — publishing "system.nodes.read" for
        # system_deploy_platform and system_rotate_vault_transit_pepper alike.
        # This is the surface an operator reads when sizing an MCP grant, and a
        # privilege UNDERSTATEMENT is the direction that makes a dangerous verb
        # look safe (IMP-a63365dc0f41).
        #
        # KEYED ON THE ACTION THAT RUNS, NOT ON THE NAME INVOKED — and resolved
        # by the SHARED resolver, not re-derived here. The rule (alias hop,
        # inherited-constant semantics, why a registry-key lookup misses
        # CodeMemoryTool's four alias-keyed entries) is stated once, at
        # Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for, which the
        # registrar's two database/manifest write sites call as well
        # (IMP-bab07f770c0e). A second copy is a second place to get the alias
        # hop wrong, which is how those four verbs survived inside this change's
        # own first cut.
        permission = ::Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for(klass, action_name)

        categories[category] << {
          action: action_name,
          class_name: class_name,
          description: defn[:description],
          parameters: defn[:parameters] || {},
          permission: permission
        }

        tool_classes_seen << class_name
        action_count += 1
      rescue NameError => e
        puts "  Warning: Could not load #{class_name} for action '#{action_name}': #{e.message}"
        categories[category] << {
          action: action_name,
          class_name: class_name,
          description: "(class not found)",
          parameters: {},
          permission: nil
        }
        action_count += 1
      end
    end

    # Generate markdown
    lines = []
    lines << "<!-- AUTO-GENERATED — DO NOT EDIT — see reference/auto/manifest.yml -->"
    lines << ""
    lines << "# MCP Tool Catalog"
    lines << ""
    lines << "> Auto-generated by `rails mcp:generate_tool_catalog` on #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"
    lines << "> Source: `Ai::Tools::PlatformApiToolRegistry::TOOLS`"
    lines << ""
    lines << "**#{action_count} actions** across **#{tool_classes_seen.size} tool classes**"
    lines << ""
    lines << "---"
    lines << ""

    categories.each do |category, actions|
      next if actions.empty?

      lines << "## #{category}"
      lines << ""

      actions.each do |action|
        lines << "### `#{action[:action]}`"
        lines << ""
        lines << "#{action[:description]}"
        lines << ""
        lines << "- **Tool class**: `#{action[:class_name]}`"
        lines << "- **Permission**: #{action[:permission] || 'none'}"

        params = action[:parameters]
        # Normalize JSON Schema format ({ type: "object", properties: {...}, required: [...] })
        # to flat format ({ param_name: { type:, required:, description: } })
        if params[:type] == "object" && params.key?(:properties)
          required_list = Array(params[:required]).map(&:to_s)
          flat_params = {}
          (params[:properties] || {}).each do |pname, pspec|
            flat_params[pname] = pspec.merge(required: required_list.include?(pname.to_s))
          end
          params = flat_params
        end

        if params.any?
          lines << ""
          lines << "| Parameter | Type | Required | Description |"
          lines << "|-----------|------|----------|-------------|"
          params.each do |param_name, spec|
            required = spec[:required] ? "Yes" : "No"
            lines << "| `#{param_name}` | #{spec[:type] || 'string'} | #{required} | #{spec[:description] || '-'} |"
          end
        else
          lines << "- **Parameters**: none"
        end

        lines << ""
      end

      lines << "---"
      lines << ""
    end

    # Write output
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, lines.join("\n"))

    puts "Generated catalog for #{action_count} actions across #{tool_classes_seen.size} tool classes"
    puts "Output: #{output_path}"
  end

  desc "Sync platform tools to mcp_tools database table (for frontend MCP browser)"
  task sync_tools: :environment do
    Account.find_each do |account|
      count = Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)
      puts "#{account.name}: synced #{count} tools"
    end
  end
end
