# frozen_string_literal: true

require "rails_helper"

# IMP-e8513b30152d — seeds never re-run after first boot, so a tenant created
# through core's post-bootstrap account path gets its inactive `claude-code`
# provider scope (the row Claude Code runs are recorded under when no
# credentialed Anthropic provider exists) at provision time, through the same
# seam the baseline seed uses.
RSpec.describe Accounts::ProvisionService, "claude-code provider scope" do
  it "seeds the inactive, non-routable claude-code scope for the new tenant" do
    result = described_class.call(name: "Tenant Two", admin_email: "owner@tenant-two.test",
                                  admin_password: TestUsers::PASSWORD)

    scope = result.account.ai_providers.find_by(slug: "claude-code")
    expect(scope).to be_present
    expect(scope.is_active).to be false
    expect(scope.provider_identifier).to eq(Ai::ClaudeExport::ProviderScopeSeeder::SOURCE_KEY)
    expect(Ai::Provider.platform_routable.where(account: result.account)).not_to include(scope)
  end
end
