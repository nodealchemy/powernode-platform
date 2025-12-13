# frozen_string_literal: true

# Migration to consolidate workflow node types:
# - KB Article: kb_article_create, kb_article_read, kb_article_update, kb_article_search, kb_article_publish → kb_article
# - Page: page_create, page_read, page_update, page_publish → page
# - MCP: mcp_tool, mcp_resource, mcp_prompt → mcp_operation
#
# This reduces 12 node types to 3, with action/operation parameters in configuration.
# Total node types: 34 → 24
class ConsolidateWorkflowNodeTypes < ActiveRecord::Migration[8.0]
  # Node type mappings for consolidation
  KB_ARTICLE_TYPES = %w[kb_article_create kb_article_read kb_article_update kb_article_search kb_article_publish].freeze
  PAGE_TYPES = %w[page_create page_read page_update page_publish].freeze
  MCP_TYPES = %w[mcp_tool mcp_resource mcp_prompt].freeze

  def up
    # Step 1: Remove old CHECK constraint FIRST (before updating data)
    # This is necessary because the old constraint doesn't include consolidated types
    remove_check_constraint :ai_workflow_nodes, name: 'ai_workflow_nodes_type_check'

    # Step 2: Migrate KB Article nodes
    execute_sql_update(
      'kb_article',
      KB_ARTICLE_TYPES,
      ->(type) { type.gsub('kb_article_', '') }
    )

    # Step 3: Migrate Page nodes
    execute_sql_update(
      'page',
      PAGE_TYPES,
      ->(type) { type.gsub('page_', '') }
    )

    # Step 4: Migrate MCP nodes
    execute_sql_update(
      'mcp_operation',
      MCP_TYPES,
      ->(type) { type.gsub('mcp_', '') }
    )

    # Step 5: Add new CHECK constraint with consolidated node types (24 types)
    add_check_constraint :ai_workflow_nodes,
      build_node_type_constraint(consolidated_node_types),
      name: 'ai_workflow_nodes_type_check'
  end

  def down
    # Step 1: Remove consolidated CHECK constraint FIRST (before updating data)
    remove_check_constraint :ai_workflow_nodes, name: 'ai_workflow_nodes_type_check'

    # Step 2: Restore KB Article nodes
    KB_ARTICLE_TYPES.each do |old_type|
      action = old_type.gsub('kb_article_', '')
      execute <<-SQL.squish
        UPDATE ai_workflow_nodes
        SET node_type = '#{old_type}',
            configuration = configuration - 'action'
        WHERE node_type = 'kb_article'
          AND configuration->>'action' = '#{action}'
      SQL
    end

    # Step 3: Restore Page nodes
    PAGE_TYPES.each do |old_type|
      action = old_type.gsub('page_', '')
      execute <<-SQL.squish
        UPDATE ai_workflow_nodes
        SET node_type = '#{old_type}',
            configuration = configuration - 'action'
        WHERE node_type = 'page'
          AND configuration->>'action' = '#{action}'
      SQL
    end

    # Step 4: Restore MCP nodes
    MCP_TYPES.each do |old_type|
      operation_type = old_type.gsub('mcp_', '')
      execute <<-SQL.squish
        UPDATE ai_workflow_nodes
        SET node_type = '#{old_type}',
            configuration = configuration - 'operation_type'
        WHERE node_type = 'mcp_operation'
          AND configuration->>'operation_type' = '#{operation_type}'
      SQL
    end

    # Step 5: Restore original CHECK constraint with old node types
    add_check_constraint :ai_workflow_nodes,
      build_node_type_constraint(original_node_types),
      name: 'ai_workflow_nodes_type_check'
  end

  private

  def execute_sql_update(new_type, old_types, action_extractor)
    old_types.each do |old_type|
      action = action_extractor.call(old_type)
      config_key = new_type == 'mcp_operation' ? 'operation_type' : 'action'

      execute <<-SQL.squish
        UPDATE ai_workflow_nodes
        SET node_type = '#{new_type}',
            configuration = configuration || '{"#{config_key}": "#{action}"}'::jsonb
        WHERE node_type = '#{old_type}'
      SQL
    end
  end

  def build_node_type_constraint(types)
    type_array = types.map { |t| "'#{t}'::character varying::text" }.join(', ')
    "node_type::text = ANY (ARRAY[#{type_array}])"
  end

  def consolidated_node_types
    %w[
      start end trigger
      ai_agent prompt_template data_processor transform
      condition loop delay merge split
      database file validator
      email notification
      api_call webhook scheduler
      human_approval sub_workflow
      kb_article page mcp_operation
    ]
  end

  def original_node_types
    %w[
      start end trigger
      ai_agent prompt_template data_processor transform
      condition loop delay merge split
      database file validator
      email notification
      api_call webhook scheduler
      human_approval sub_workflow
      kb_article_create kb_article_read kb_article_update kb_article_search kb_article_publish
      page_create page_read page_update page_publish
      mcp_tool mcp_resource mcp_prompt
    ]
  end
end
