# frozen_string_literal: true

# fc-27 deleted the ai/content_drafts and admin/validation_rules REST
# controllers and, with them, the ai.content_drafts.* and
# admin.validation_rules.* permission definitions in config/permissions.rb.
# Role grants of those names already in role_permissions now name permissions
# that no longer exist (RolePermission's own validation refuses to create
# them). They grant nothing, but they surface as undefined permissions in
# role listings and audits, so this removes them.
#
# Idempotent: a re-run matches no rows. Irreversible: the permissions no
# longer exist, so there is nothing meaningful to restore.
class DeleteOrphanedContentDraftAndValidationRuleGrants < ActiveRecord::Migration[8.0]
  # `_` is escaped: unescaped, LIKE reads it as a one-character wildcard.
  ORPHANED_PATTERNS = [ 'ai.content\_drafts.%', 'admin.validation\_rules.%' ].freeze

  def up
    conditions = ORPHANED_PATTERNS.map { |pattern| "permission_name LIKE #{connection.quote(pattern)}" }.join(" OR ")
    deleted = exec_delete("DELETE FROM role_permissions WHERE #{conditions}", "SQL", [])
    say "Deleted #{deleted} orphaned role_permissions grant(s) for removed permissions"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
