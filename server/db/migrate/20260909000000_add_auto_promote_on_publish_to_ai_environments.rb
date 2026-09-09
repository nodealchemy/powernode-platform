# frozen_string_literal: true

# Environment campaign, increment 4 — the promotion ladder.
#
# Which environments FOLLOW a module publish (their nodes serve the module's
# current version the moment it is published) and which are PINNED (their
# nodes serve the version an operator promoted into them, and nothing else).
# Operator ruling 2026-09-08: dev, ci and the control plane (ops) keep
# following publishes for now; staging and prod are pinned.
class AddAutoPromoteOnPublishToAiEnvironments < ActiveRecord::Migration[8.0]
  def up
    add_column :ai_environments, :auto_promote_on_publish, :boolean, default: true, null: false
    execute <<~SQL.squish
      UPDATE ai_environments SET auto_promote_on_publish = FALSE WHERE slug IN ('staging', 'prod')
    SQL
  end

  def down
    remove_column :ai_environments, :auto_promote_on_publish
  end
end
