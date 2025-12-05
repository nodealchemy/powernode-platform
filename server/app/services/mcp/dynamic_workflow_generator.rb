# frozen_string_literal: true

module Mcp
  # Dynamic workflow generation from templates and configurations
  # Enables runtime workflow composition and template instantiation
  class DynamicWorkflowGenerator
    attr_reader :account, :user

    def initialize(account:, user:)
      @account = account
      @user = user
    end

    # Generate workflow from template
    def generate_from_template(template:, parameters:, name: nil)
      raise ArgumentError, "Template must be an AiWorkflow" unless template.is_template?

      workflow_name = name || "#{template.name} - #{Time.current.strftime('%Y%m%d-%H%M%S')}"

      workflow = AiWorkflow.create!(
        account: account,
        creator: user,
        name: workflow_name,
        description: "Generated from template: #{template.name}",
        slug: generate_slug(workflow_name),
        status: 'draft',
        visibility: 'private',
        is_template: false,
        configuration: merge_template_config(template.configuration, parameters),
        metadata: {
          'generated_from_template' => template.id,
          'template_name' => template.name,
          'generation_timestamp' => Time.current.iso8601,
          'parameters' => parameters
        }
      )

      # Copy and parameterize nodes
      copy_nodes_from_template(template, workflow, parameters)

      # Copy and parameterize edges
      copy_edges_from_template(template, workflow)

      # Apply parameter transformations
      apply_parameter_transformations(workflow, parameters)

      workflow
    end

    # Generate workflow from configuration DSL
    def generate_from_config(config:, name:)
      validate_workflow_config(config)

      workflow = AiWorkflow.create!(
        account: account,
        creator: user,
        name: name,
        description: config['description'] || "Generated workflow",
        slug: generate_slug(name),
        status: 'draft',
        visibility: config['visibility'] || 'private',
        is_template: false,
        configuration: config['workflow_config'] || {},
        metadata: {
          'generated_dynamically' => true,
          'generation_timestamp' => Time.current.iso8601,
          'config_version' => config['version'] || '1.0.0'
        }
      )

      # Generate nodes from config
      generate_nodes_from_config(workflow, config['nodes'])

      # Generate edges from config
      generate_edges_from_config(workflow, config['edges'])

      # Apply conditional logic
      apply_conditional_logic(workflow, config['conditions']) if config['conditions']

      workflow
    end

    # Generate workflow from JSON specification
    def generate_from_json(json_spec:, name: nil)
      spec = JSON.parse(json_spec)

      workflow_name = name || spec['name'] || "Generated Workflow #{SecureRandom.hex(4)}"

      workflow = AiWorkflow.create!(
        account: account,
        creator: user,
        name: workflow_name,
        description: spec['description'] || "Generated from JSON specification",
        slug: generate_slug(workflow_name),
        status: spec['status'] || 'draft',
        visibility: spec['visibility'] || 'private',
        is_template: false,
        configuration: spec['configuration'] || {},
        metadata: {
          'generated_from_json' => true,
          'generation_timestamp' => Time.current.iso8601,
          'json_spec_version' => spec['version']
        }
      )

      # Create nodes from JSON
      node_map = create_nodes_from_json(workflow, spec['nodes'])

      # Create edges from JSON
      create_edges_from_json(workflow, spec['edges'], node_map)

      workflow
    end

    # Generate multi-agent workflow
    def generate_multi_agent_workflow(name:, agents:, collaboration_pattern: 'sequential')
      workflow = AiWorkflow.create!(
        account: account,
        creator: user,
        name: name,
        description: "Multi-agent workflow with #{agents.length} agents",
        slug: generate_slug(name),
        status: 'draft',
        visibility: 'private',
        configuration: {
          'multi_agent' => true,
          'collaboration_pattern' => collaboration_pattern,
          'agent_count' => agents.length
        },
        metadata: {
          'generated_multi_agent' => true,
          'agents' => agents.map { |a| { id: a[:id], name: a[:name] } }
        }
      )

      case collaboration_pattern
      when 'sequential'
        generate_sequential_agent_flow(workflow, agents)
      when 'parallel'
        generate_parallel_agent_flow(workflow, agents)
      when 'hierarchical'
        generate_hierarchical_agent_flow(workflow, agents)
      when 'mesh'
        generate_mesh_agent_flow(workflow, agents)
      else
        raise ArgumentError, "Unknown collaboration pattern: #{collaboration_pattern}"
      end

      workflow
    end

    # Generate workflow from natural language description (AI-assisted)
    def generate_from_description(description:, name: nil)
      # This would integrate with an AI agent to interpret natural language
      # For now, we'll create a basic structure and mark it for AI completion

      workflow_name = name || "AI-Generated Workflow #{SecureRandom.hex(4)}"

      workflow = AiWorkflow.create!(
        account: account,
        creator: user,
        name: workflow_name,
        description: description,
        slug: generate_slug(workflow_name),
        status: 'draft',
        visibility: 'private',
        configuration: {
          'ai_generated' => true,
          'requires_completion' => true
        },
        metadata: {
          'generation_method' => 'natural_language',
          'original_description' => description,
          'generation_timestamp' => Time.current.iso8601
        }
      )

      # Create placeholder nodes for AI completion
      create_placeholder_nodes(workflow, description)

      workflow
    end

    # Compose workflow from multiple sub-workflows
    def compose_from_workflows(name:, workflows:, composition_strategy: 'sequential')
      composed = AiWorkflow.create!(
        account: account,
        creator: user,
        name: name,
        description: "Composed from #{workflows.length} workflows",
        slug: generate_slug(name),
        status: 'draft',
        visibility: 'private',
        configuration: {
          'composed' => true,
          'composition_strategy' => composition_strategy,
          'source_workflows' => workflows.map(&:id)
        },
        metadata: {
          'composed_from' => workflows.map { |w| { id: w.id, name: w.name } }
        }
      )

      case composition_strategy
      when 'sequential'
        compose_sequential(composed, workflows)
      when 'parallel'
        compose_parallel(composed, workflows)
      when 'conditional'
        compose_conditional(composed, workflows)
      end

      composed
    end

    private

    # Copy nodes from template with parameterization
    def copy_nodes_from_template(template, workflow, parameters)
      template.ai_workflow_nodes.each do |template_node|
        config = parameterize_config(template_node.configuration, parameters)

        workflow.ai_workflow_nodes.create!(
          node_id: template_node.node_id,
          node_type: template_node.node_type,
          name: parameterize_string(template_node.name, parameters),
          description: parameterize_string(template_node.description, parameters),
          configuration: config,
          position_x: template_node.position_x,
          position_y: template_node.position_y,
          metadata: template_node.metadata.merge('from_template' => template.id)
        )
      end
    end

    # Copy edges from template
    def copy_edges_from_template(template, workflow)
      template.ai_workflow_edges.each do |template_edge|
        workflow.ai_workflow_edges.create!(
          source_node_id: template_edge.source_node_id,
          target_node_id: template_edge.target_node_id,
          edge_type: template_edge.edge_type,
          condition: template_edge.condition,
          metadata: template_edge.metadata
        )
      end
    end

    # Merge template configuration with parameters
    def merge_template_config(template_config, parameters)
      template_config.deep_merge(parameters.stringify_keys)
    end

    # Parameterize configuration values
    def parameterize_config(config, parameters)
      return config unless config.is_a?(Hash)

      config.deep_transform_values do |value|
        case value
        when String
          parameterize_string(value, parameters)
        when Hash
          parameterize_config(value, parameters)
        else
          value
        end
      end
    end

    # Replace parameter placeholders in strings
    def parameterize_string(string, parameters)
      return string unless string.is_a?(String)

      result = string.dup
      parameters.each do |key, value|
        result.gsub!("{{#{key}}}", value.to_s)
        result.gsub!("${#{key}}", value.to_s)
      end
      result
    end

    # Apply parameter transformations
    def apply_parameter_transformations(workflow, parameters)
      transformations = parameters['transformations'] || []

      transformations.each do |transform|
        case transform['type']
        when 'node_filter'
          filter_nodes(workflow, transform['filter'])
        when 'edge_modification'
          modify_edges(workflow, transform['modifications'])
        when 'config_override'
          override_config(workflow, transform['overrides'])
        end
      end
    end

    # Generate nodes from configuration
    def generate_nodes_from_config(workflow, nodes_config)
      nodes_config.each_with_index do |node_config, index|
        workflow.ai_workflow_nodes.create!(
          node_id: node_config['id'] || "node_#{index}",
          node_type: node_config['type'],
          name: node_config['name'],
          description: node_config['description'],
          configuration: node_config['config'] || {},
          position_x: node_config['position']&.dig('x') || (index * 200),
          position_y: node_config['position']&.dig('y') || 100,
          metadata: node_config['metadata'] || {}
        )
      end
    end

    # Generate edges from configuration
    def generate_edges_from_config(workflow, edges_config)
      return unless edges_config

      edges_config.each do |edge_config|
        workflow.ai_workflow_edges.create!(
          source_node_id: edge_config['from'],
          target_node_id: edge_config['to'],
          edge_type: edge_config['type'] || 'default',
          condition: edge_config['condition'],
          metadata: edge_config['metadata'] || {}
        )
      end
    end

    # Apply conditional logic to workflow
    def apply_conditional_logic(workflow, conditions)
      conditions.each do |condition|
        # Create conditional edges based on rules
        workflow.ai_workflow_edges.create!(
          source_node_id: condition['source'],
          target_node_id: condition['target'],
          edge_type: 'conditional',
          condition: condition['expression'],
          metadata: { 'conditional_rule' => condition }
        )
      end
    end

    # Create nodes from JSON specification
    def create_nodes_from_json(workflow, nodes_json)
      node_map = {}

      nodes_json.each do |node_json|
        node = workflow.ai_workflow_nodes.create!(
          node_id: node_json['id'],
          node_type: node_json['type'],
          name: node_json['name'],
          description: node_json['description'],
          configuration: node_json['configuration'] || {},
          position_x: node_json['x'] || 0,
          position_y: node_json['y'] || 0,
          metadata: node_json['metadata'] || {}
        )

        node_map[node_json['id']] = node
      end

      node_map
    end

    # Create edges from JSON specification
    def create_edges_from_json(workflow, edges_json, node_map)
      return unless edges_json

      edges_json.each do |edge_json|
        workflow.ai_workflow_edges.create!(
          source_node_id: edge_json['source'],
          target_node_id: edge_json['target'],
          edge_type: edge_json['type'] || 'default',
          condition: edge_json['condition'],
          metadata: edge_json['metadata'] || {}
        )
      end
    end

    # Generate sequential agent flow
    def generate_sequential_agent_flow(workflow, agents)
      start_node = workflow.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        configuration: {},
        position_x: 100,
        position_y: 100
      )

      previous_node = start_node

      agents.each_with_index do |agent, index|
        agent_node = workflow.ai_workflow_nodes.create!(
          node_id: "agent_#{agent[:id]}",
          node_type: 'ai_agent',
          name: agent[:name],
          configuration: { 'agent_id' => agent[:id] },
          position_x: 100 + (index + 1) * 250,
          position_y: 100
        )

        workflow.ai_workflow_edges.create!(
          source_node_id: previous_node.node_id,
          target_node_id: agent_node.node_id,
          edge_type: 'default'
        )

        previous_node = agent_node
      end

      end_node = workflow.ai_workflow_nodes.create!(
        node_id: 'end',
        node_type: 'end',
        name: 'End',
        configuration: {},
        position_x: 100 + (agents.length + 1) * 250,
        position_y: 100
      )

      workflow.ai_workflow_edges.create!(
        source_node_id: previous_node.node_id,
        target_node_id: end_node.node_id,
        edge_type: 'default'
      )
    end

    # Generate parallel agent flow
    def generate_parallel_agent_flow(workflow, agents)
      start_node = workflow.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        configuration: {},
        position_x: 400,
        position_y: 50
      )

      agent_nodes = agents.map.with_index do |agent, index|
        node = workflow.ai_workflow_nodes.create!(
          node_id: "agent_#{agent[:id]}",
          node_type: 'ai_agent',
          name: agent[:name],
          configuration: { 'agent_id' => agent[:id] },
          position_x: 100 + index * 200,
          position_y: 200
        )

        workflow.ai_workflow_edges.create!(
          source_node_id: start_node.node_id,
          target_node_id: node.node_id,
          edge_type: 'parallel'
        )

        node
      end

      merge_node = workflow.ai_workflow_nodes.create!(
        node_id: 'merge',
        node_type: 'merge',
        name: 'Merge Results',
        configuration: {},
        position_x: 400,
        position_y: 350
      )

      agent_nodes.each do |agent_node|
        workflow.ai_workflow_edges.create!(
          source_node_id: agent_node.node_id,
          target_node_id: merge_node.node_id,
          edge_type: 'default'
        )
      end

      end_node = workflow.ai_workflow_nodes.create!(
        node_id: 'end',
        node_type: 'end',
        name: 'End',
        configuration: {},
        position_x: 400,
        position_y: 500
      )

      workflow.ai_workflow_edges.create!(
        source_node_id: merge_node.node_id,
        target_node_id: end_node.node_id,
        edge_type: 'default'
      )
    end

    # Generate hierarchical agent flow
    def generate_hierarchical_agent_flow(workflow, agents)
      # First agent is coordinator
      coordinator = agents.first
      workers = agents[1..-1]

      start_node = workflow.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        position_x: 400,
        position_y: 50
      )

      coordinator_node = workflow.ai_workflow_nodes.create!(
        node_id: "coordinator_#{coordinator[:id]}",
        node_type: 'ai_agent',
        name: "Coordinator: #{coordinator[:name]}",
        configuration: { 'agent_id' => coordinator[:id], 'role' => 'coordinator' },
        position_x: 400,
        position_y: 150
      )

      workflow.ai_workflow_edges.create!(
        source_node_id: start_node.node_id,
        target_node_id: coordinator_node.node_id
      )

      # Worker nodes
      workers.each_with_index do |worker, index|
        worker_node = workflow.ai_workflow_nodes.create!(
          node_id: "worker_#{worker[:id]}",
          node_type: 'ai_agent',
          name: "Worker: #{worker[:name]}",
          configuration: { 'agent_id' => worker[:id], 'role' => 'worker', 'coordinator_id' => coordinator[:id] },
          position_x: 200 + index * 150,
          position_y: 300
        )

        workflow.ai_workflow_edges.create!(
          source_node_id: coordinator_node.node_id,
          target_node_id: worker_node.node_id,
          edge_type: 'command'
        )
      end
    end

    # Generate mesh agent flow (all-to-all communication)
    def generate_mesh_agent_flow(workflow, agents)
      start_node = workflow.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        position_x: 400,
        position_y: 50
      )

      # Create shared blackboard
      blackboard_node = workflow.ai_workflow_nodes.create!(
        node_id: 'shared_blackboard',
        node_type: 'transform',
        name: 'Shared Blackboard',
        configuration: { 'blackboard' => true },
        position_x: 400,
        position_y: 150
      )

      workflow.ai_workflow_edges.create!(
        source_node_id: start_node.node_id,
        target_node_id: blackboard_node.node_id
      )

      # All agents connect to blackboard
      agents.each_with_index do |agent, index|
        angle = (2 * Math::PI * index) / agents.length
        radius = 200

        agent_node = workflow.ai_workflow_nodes.create!(
          node_id: "agent_#{agent[:id]}",
          node_type: 'ai_agent',
          name: agent[:name],
          configuration: { 'agent_id' => agent[:id], 'mesh_mode' => true },
          position_x: 400 + (radius * Math.cos(angle)).to_i,
          position_y: 300 + (radius * Math.sin(angle)).to_i
        )

        workflow.ai_workflow_edges.create!(
          source_node_id: blackboard_node.node_id,
          target_node_id: agent_node.node_id,
          edge_type: 'broadcast'
        )
      end
    end

    # Create placeholder nodes for AI completion
    def create_placeholder_nodes(workflow, description)
      workflow.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        position_x: 100,
        position_y: 100
      )

      workflow.ai_workflow_nodes.create!(
        node_id: 'ai_placeholder',
        node_type: 'ai_agent',
        name: 'AI-Generated Steps',
        description: "To be completed based on: #{description}",
        configuration: { 'requires_ai_completion' => true },
        position_x: 350,
        position_y: 100
      )

      workflow.ai_workflow_nodes.create!(
        node_id: 'end',
        node_type: 'end',
        name: 'End',
        position_x: 600,
        position_y: 100
      )
    end

    # Compose workflows sequentially
    def compose_sequential(composed, workflows)
      start_node = composed.ai_workflow_nodes.create!(
        node_id: 'start',
        node_type: 'start',
        name: 'Start',
        position_x: 100,
        position_y: 100
      )

      previous_node = start_node

      workflows.each_with_index do |workflow, index|
        sub_workflow_node = composed.ai_workflow_nodes.create!(
          node_id: "sub_workflow_#{workflow.id}",
          node_type: 'sub_workflow',
          name: workflow.name,
          configuration: { 'workflow_id' => workflow.id },
          position_x: 100 + (index + 1) * 300,
          position_y: 100
        )

        composed.ai_workflow_edges.create!(
          source_node_id: previous_node.node_id,
          target_node_id: sub_workflow_node.node_id
        )

        previous_node = sub_workflow_node
      end
    end

    # Compose workflows in parallel
    def compose_parallel(composed, workflows)
      # Similar to parallel agent flow but with sub-workflows
      split_node = composed.ai_workflow_nodes.create!(
        node_id: 'split',
        node_type: 'split',
        name: 'Split',
        position_x: 400,
        position_y: 100
      )

      workflows.each_with_index do |workflow, index|
        composed.ai_workflow_nodes.create!(
          node_id: "sub_workflow_#{workflow.id}",
          node_type: 'sub_workflow',
          name: workflow.name,
          configuration: { 'workflow_id' => workflow.id },
          position_x: 200 + index * 200,
          position_y: 250
        )
      end
    end

    # Compose workflows with conditional routing
    def compose_conditional(composed, workflows)
      # Create router node that directs to different workflows based on conditions
    end

    # Helper methods
    def generate_slug(name)
      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-').strip
      ensure_unique_slug(base_slug)
    end

    def ensure_unique_slug(base_slug)
      slug = base_slug
      counter = 1

      while AiWorkflow.exists?(account_id: account.id, slug: slug)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end

      slug
    end

    def validate_workflow_config(config)
      raise ArgumentError, "Config must include 'nodes'" unless config['nodes'].present?
      raise ArgumentError, "Nodes must be an array" unless config['nodes'].is_a?(Array)
    end

    def filter_nodes(workflow, filter)
      # Apply filters to remove unwanted nodes
    end

    def modify_edges(workflow, modifications)
      # Apply edge modifications
    end

    def override_config(workflow, overrides)
      # Override workflow configuration
    end
  end
end
