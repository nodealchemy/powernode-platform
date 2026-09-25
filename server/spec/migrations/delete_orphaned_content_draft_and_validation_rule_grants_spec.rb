# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260925050000_delete_orphaned_content_draft_and_validation_rule_grants.rb")

# fc-27 removed the ai.content_drafts.* and admin.validation_rules.*
# permission definitions; role_permissions rows granting them are orphans
# that RolePermission's own validation would now refuse to create, so the
# fixtures below insert them with raw SQL, as a pre-removal deployment has them.
RSpec.describe DeleteOrphanedContentDraftAndValidationRuleGrants do
  subject(:migration) { described_class.new }

  let(:role) { create(:role) }
  let(:connection) { ActiveRecord::Base.connection }

  def grant(permission_name)
    connection.execute(<<~SQL)
      INSERT INTO role_permissions (role_id, permission_name)
      VALUES (#{connection.quote(role.id)}, #{connection.quote(permission_name)})
    SQL
  end

  def granted_names
    connection.select_values(
      "SELECT permission_name FROM role_permissions WHERE role_id = #{connection.quote(role.id)} ORDER BY permission_name"
    )
  end

  before do
    grant("ai.content_drafts.read")
    grant("ai.content_drafts.manage")
    grant("admin.validation_rules.manage")
    grant("ai.agents.read")
    grant("admin.settings.read")
  end

  describe "#up" do
    it "deletes only the orphaned grants and keeps every other grant" do
      migration.up

      expect(granted_names).to eq(%w[admin.settings.read ai.agents.read])
    end

    it "is idempotent: a second run deletes nothing more and does not raise" do
      migration.up

      expect { migration.up }.not_to raise_error
      expect(granted_names).to eq(%w[admin.settings.read ai.agents.read])
    end

    it "logs counts only, never a role id" do
      logged = []
      allow(migration).to receive(:say) { |message, *| logged << message }

      migration.up

      expect(logged.join("\n")).to include("3")
      expect(logged.join("\n")).not_to include(role.id)
    end
  end

  describe "#down" do
    it "is irreversible" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
