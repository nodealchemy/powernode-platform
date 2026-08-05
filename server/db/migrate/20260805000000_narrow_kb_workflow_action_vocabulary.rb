# frozen_string_literal: true

# Drops `delete` from the knowledge_base_workflows action vocabulary.
#
# No code path could ever write it durably: KnowledgeBase::Article declares
# `has_many :workflows, dependent: :destroy` (article.rb:22) and Workflow's
# `belongs_to :article` is required, so a row recording a deletion is cascaded
# away by the very act it records. It saved fine; it could not survive its own
# subject. Article deletions are recorded in audit_logs instead — see
# Api::V1::Kb::ArticlesController#record_article_deletion! — whose resource_id
# is a plain string with no foreign key and therefore outlives the row it names.
#
# The CHECK constraint owns this vocabulary and
# KnowledgeBase::Workflow::VALID_ACTIONS mirrors it; spec/models asserts the two
# match exactly, in BOTH directions, so the constant is narrowed in the same
# commit as this migration. They cannot move separately.
#
# Safe on existing data: a `delete` row cannot exist — nothing wrote one, and
# any that had been written would have been destroyed alongside its article.
# Confirmed against production before this was written (zero
# knowledge_base_workflows rows of any action).
#
# Reversible: #down restores the original seven-value constraint byte-for-byte
# as db/migrate/20250101000004_knowledge_base_baseline.rb created it.
class NarrowKbWorkflowActionVocabulary < ActiveRecord::Migration[8.1]
  TABLE = :knowledge_base_workflows
  CONSTRAINT_NAME = "valid_kb_workflow_action"

  # Written in the form Postgres normalizes to, so the schema dump and the
  # baseline migration's constraint stay textually identical.
  WITHOUT_DELETE = "action::text = ANY (ARRAY['create'::character varying::text, " \
                   "'edit'::character varying::text, 'publish'::character varying::text, " \
                   "'unpublish'::character varying::text, 'archive'::character varying::text, " \
                   "'review'::character varying::text])"

  WITH_DELETE = "action::text = ANY (ARRAY['create'::character varying::text, " \
                "'edit'::character varying::text, 'publish'::character varying::text, " \
                "'unpublish'::character varying::text, 'archive'::character varying::text, " \
                "'delete'::character varying::text, 'review'::character varying::text])"

  def up
    remove_check_constraint TABLE, WITH_DELETE, name: CONSTRAINT_NAME
    add_check_constraint TABLE, WITHOUT_DELETE, name: CONSTRAINT_NAME
  end

  def down
    remove_check_constraint TABLE, WITHOUT_DELETE, name: CONSTRAINT_NAME
    add_check_constraint TABLE, WITH_DELETE, name: CONSTRAINT_NAME
  end
end
