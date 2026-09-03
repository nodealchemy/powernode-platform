# frozen_string_literal: true

namespace :mcp do
  desc "Generate MCP tool catalog from PlatformApiToolRegistry action_definitions"
  task generate_tool_catalog: :environment do
    # The SAME map the runtime reads. `.all_tools` is `TOOLS.merge(extension_tools)`
    # (platform_api_tool_registry.rb), and every runtime consumer resolves through
    # it: McpPlatformToolRegistrar.sync_to_database!, .tool_classes, .find_tool_class
    # and PlatformApiToolRegistry.available_tools. Sourcing the narrower static
    # ::TOOLS here meant a tool contributed through the `register_extension_tools`
    # seam was synced to the mcp_tools table, executable, and advertised over MCP,
    # yet structurally absent from this catalog — the surface an operator reads
    # when sizing an MCP grant. Nothing warned: check-mcp-catalog-fresh.sh only
    # proves the doc matches the source it declares (IMP-86c839455f87).
    # Zero rows wide in the PUBLIC bundle — measured `extension_tools.size == 0`
    # with only public extensions loaded — so for the tracked artifact this is a
    # drift guard, pinned by spec/lib/tasks/mcp_tool_catalog_extension_tools_spec.rb.
    # It is NOT zero in every environment: a private-mode bundle
    # (`BUNDLE_GEMFILE=Gemfile.private`, POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1) or a
    # deployed node (POWERNODE_DEPLOYED=1) loads extension engines that register
    # through the seam, and this task then renders their actions too. That is the
    # intended behaviour for a locally generated catalog; the COMMITTED
    # docs/reference/auto/mcp-tools.md is the public rendering, and
    # scripts/check-mcp-catalog-fresh.sh pins that environment so a private-mode
    # regeneration cannot be committed silently.
    registry = Ai::Tools::PlatformApiToolRegistry.all_tools
    # Output path override, used by spec/lib/tasks/mcp_tool_catalog_extension_tools_spec.rb
    # so the generator can be exercised without writing over the committed catalog.
    output_path = ENV["MCP_TOOL_CATALOG_OUTPUT"].presence || Rails.root.join("..", "docs", "reference", "auto", "mcp-tools.md")

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
      "Ai::Tools::ToolCatalogTool" => "Knowledge & RAG",
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

    # A markdown table cell is pipe-delimited, so an unescaped `|` inside a
    # value ends the cell: the rest of it becomes phantom columns a renderer
    # drops. Publishing declared value sets makes that reachable directly (a `|`
    # inside an enum member), but it was NOT merely prospective — 107 rows of the
    # committed catalog were already being truncated at the first `|` of a
    # description that spelled its value set out as `a | b | c`, so
    # `system_create_service`'s `protocol` published as "https" where the tool
    # declares "https | http | tcp | tls (default https)".
    md_cell = lambda do |value|
      value.to_s.gsub(/\s*\n\s*/, " ").gsub("|") { '\|' }
    end

    # `array` on its own tells an operator nothing about what goes in it, and
    # the wire schema always carries an `items` (ParameterSchema fills the
    # permissive default when a tool declares none), so publish the element type
    # with it.
    type_cell = lambda do |spec|
      declared = Array(spec["type"]).map(&:to_s).reject(&:empty?)
      rendered = declared.presence&.join(" or ") || "string"

      items = spec["items"]
      if rendered == "array" && items.is_a?(Hash)
        element = Array(items["type"]).first.presence
        element ||= "object" if items.key?("properties")
        rendered = "array<#{element}>" if element
      end

      md_cell.call(rendered)
    end

    render_enum = lambda do |values|
      Array(values).map { |value| "`#{md_cell.call(value)}`" }.join(", ")
    end

    # The closed value set the wire constrains this parameter to. Before this it
    # existed in the catalog only if the description prose happened to restate
    # it, which is how the same set could be right on the wire and stale, partial
    # or absent in the document an operator sizes a grant from.
    #
    # A set can also sit BELOW the parameter, and ParameterSchema carries those
    # onto the wire too, so publishing only the top-level `enum` would leave the
    # same understatement in place for them:
    #   * on an array's `items` — the ELEMENTS are constrained, not the array, so
    #     the set is stated unqualified next to a Type cell that already reads
    #     `array<string>`;
    #   * on one property of a nested object — the parameter itself is NOT
    #     restricted to those values, so the set is prefixed with the property it
    #     constrains.
    # Depth stops at those two: a set nested two levels down (none is declared in
    # any core or public-extension tool today) still publishes as `-`, so read a
    # `-` as "nothing closed at this level", not as "the wire imposes no set".
    values_cell = lambda do |spec|
      sets = []
      sets << render_enum.call(spec["enum"]) if spec["enum"].present?

      items = spec["items"]
      if sets.empty? && items.is_a?(Hash) && items["enum"].present?
        sets << render_enum.call(items["enum"])
      end

      properties = spec["properties"]
      if properties.is_a?(Hash)
        properties.each do |nested_name, nested_spec|
          next unless nested_spec.is_a?(Hash) && nested_spec["enum"].present?

          sets << "#{md_cell.call(nested_name)}: #{render_enum.call(nested_spec['enum'])}"
        end
      end

      sets.presence&.join("; ") || "-"
    end

    # Generate markdown
    lines = []
    lines << "<!-- AUTO-GENERATED — DO NOT EDIT — see reference/auto/manifest.yml -->"
    lines << ""
    lines << "# MCP Tool Catalog"
    lines << ""
    lines << "> Auto-generated by `rails mcp:generate_tool_catalog` on #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"
    lines << "> Source: `Ai::Tools::PlatformApiToolRegistry.all_tools`"
    lines << "> Scope: static core `TOOLS` plus the tools registered by the extension engines loaded when this file was generated. The committed copy is the public-bundle rendering."
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

        # Render the SCHEMA a client is handed, not the authoring hash. Tool
        # parameters declare JSON Schema keywords beyond type/description —
        # measured in the public bundle, 72 of the 1818 published parameters
        # carry a closed value set and 77 an array element type — and
        # Ai::Tools::ParameterSchema has carried those onto both MCP wire paths
        # since IMP-e809396f9eda
        # (Api::V1::Mcp::StreamableHttpController's tools/list `inputSchema` and
        # Ai::Tools::McpPlatformToolRegistrar's mcp_tools rows / registry
        # manifest). This table read those keywords off the raw declaration and
        # emitted none of them, so a closed value set survived only as whatever
        # the description prose happened to say and an array published as
        # untyped: the catalog UNDERSTATED the contract the wire enforces, on the
        # surface an operator reads when sizing an MCP grant (IMP-fb5085178b09).
        #
        # Going through the shared converter — the same `.build` call both wire
        # paths make, not a third reading of the declarations here — is also what
        # makes the published defaults honest: an array that declares no `items`
        # reaches the client as `array<string>` (ParameterSchema::
        # DEFAULT_ARRAY_ITEMS) and is published as one. It subsumes the
        # JSON-Schema-vs-flat normalisation this task used to carry, because
        # `.build` accepts either form and hoists the DSL's per-parameter
        # `required:` flag into the schema's `required` array.
        schema = ::Ai::Tools::ParameterSchema.build(action[:parameters])
        properties = schema["properties"] || {}
        required_names = Array(schema["required"]).map(&:to_s)

        if properties.any?
          lines << ""
          lines << "| Parameter | Type | Required | Values | Description |"
          lines << "|-----------|------|----------|--------|-------------|"
          properties.each do |param_name, spec|
            required = required_names.include?(param_name.to_s) ? "Yes" : "No"
            lines << "| `#{param_name}` | #{type_cell.call(spec)} | #{required} | " \
                     "#{values_cell.call(spec)} | #{md_cell.call(spec['description'].presence || '-')} |"
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
