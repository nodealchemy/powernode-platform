# frozen_string_literal: true

class UpdateAiWorkflowNodesConstraintAddMissingTypes < ActiveRecord::Migration[8.0]
  def up
    # Remove existing CHECK constraint
    remove_check_constraint :ai_workflow_nodes, name: "ai_workflow_nodes_type_check"

    # Add updated CHECK constraint with ALL node types from model validation (38 types)
    # Core workflow: start, end, trigger
    # AI & Processing: ai_agent, prompt_template, data_processor, transform
    # Flow control: condition, loop, delay, merge, split
    # Data: database, file, validator
    # Communication: email, notification, api_call, webhook, scheduler
    # Advanced: human_approval, sub_workflow
    # Knowledge Base: kb_article_create, kb_article_read, kb_article_update, kb_article_search, kb_article_publish
    # Pages: page_create, page_read, page_update, page_publish
    add_check_constraint :ai_workflow_nodes,
      "node_type::text = ANY (ARRAY[" \
        "'start'::character varying::text, " \
        "'end'::character varying::text, " \
        "'trigger'::character varying::text, " \
        "'ai_agent'::character varying::text, " \
        "'prompt_template'::character varying::text, " \
        "'data_processor'::character varying::text, " \
        "'transform'::character varying::text, " \
        "'condition'::character varying::text, " \
        "'loop'::character varying::text, " \
        "'delay'::character varying::text, " \
        "'merge'::character varying::text, " \
        "'split'::character varying::text, " \
        "'database'::character varying::text, " \
        "'file'::character varying::text, " \
        "'validator'::character varying::text, " \
        "'email'::character varying::text, " \
        "'notification'::character varying::text, " \
        "'api_call'::character varying::text, " \
        "'webhook'::character varying::text, " \
        "'scheduler'::character varying::text, " \
        "'human_approval'::character varying::text, " \
        "'sub_workflow'::character varying::text, " \
        "'kb_article_create'::character varying::text, " \
        "'kb_article_read'::character varying::text, " \
        "'kb_article_update'::character varying::text, " \
        "'kb_article_search'::character varying::text, " \
        "'kb_article_publish'::character varying::text, " \
        "'page_create'::character varying::text, " \
        "'page_read'::character varying::text, " \
        "'page_update'::character varying::text, " \
        "'page_publish'::character varying::text" \
      "])",
      name: "ai_workflow_nodes_type_check"
  end

  def down
    # Revert to previous constraint (13 types only)
    remove_check_constraint :ai_workflow_nodes, name: "ai_workflow_nodes_type_check"

    add_check_constraint :ai_workflow_nodes,
      "node_type::text = ANY (ARRAY[" \
        "'start'::character varying::text, " \
        "'end'::character varying::text, " \
        "'ai_agent'::character varying::text, " \
        "'api_call'::character varying::text, " \
        "'webhook'::character varying::text, " \
        "'condition'::character varying::text, " \
        "'loop'::character varying::text, " \
        "'transform'::character varying::text, " \
        "'delay'::character varying::text, " \
        "'human_approval'::character varying::text, " \
        "'sub_workflow'::character varying::text, " \
        "'merge'::character varying::text, " \
        "'split'::character varying::text" \
      "])",
      name: "ai_workflow_nodes_type_check"
  end
end
