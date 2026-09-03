# frozen_string_literal: true

require "rails_helper"

# IMP-e8513b30152d — the FIRST account of a wizard install is created here, and
# the wizard's seed step (POST /api/v1/setup/seed -> Setup::SeedService) routes
# to the extension :account_seeder seam, which no-ops in core mode and never
# loads db/seeds.rb. So db:seed is NOT a guarantee for this account: the
# bootstrap must seed the `claude-code` provider scope itself, or every Claude
# Code self-report against that install is refused forever.
RSpec.describe Setup::FirstAdminService, "claude-code provider scope" do
  it "seeds the inactive, non-routable claude-code scope for the bootstrapped account" do
    result = described_class.call(
      email: "root@powernode.internal", password: TestUsers::PASSWORD, name: "Root"
    )

    scope = result.account.ai_providers.find_by(slug: Ai::ClaudeExport::ProviderScopeSeeder::SLUG)
    expect(scope).to be_present
    expect(scope.is_active).to be false
    expect(scope.provider_identifier).to eq(Ai::ClaudeExport::ProviderScopeSeeder::SOURCE_KEY)
    expect(Ai::Provider.platform_routable.where(account: result.account)).not_to include(scope)
  end

  it "seeds the scope for an account that already existed before the bootstrap" do
    account = create(:account)

    result = described_class.call(email: "root@powernode.internal", password: TestUsers::PASSWORD)

    expect(result.account).to eq(account)
    expect(account.ai_providers.where(slug: Ai::ClaudeExport::ProviderScopeSeeder::SLUG).count).to eq(1)
  end
end
