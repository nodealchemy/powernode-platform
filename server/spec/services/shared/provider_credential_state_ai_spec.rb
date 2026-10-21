# frozen_string_literal: true

require "rails_helper"

# An AI credential only counts as "configured" on a provider that can serve a
# call: active and routable. The Claude Code local-sessions scope and inactive
# providers do not complete the wizard step.
RSpec.describe Shared::ProviderCredentialState, "ai routable filter" do
  let(:account) { create(:account) }

  def credential_on(provider)
    create(:ai_provider_credential, account: account, provider: provider)
  end

  it "does not count a credential on the Claude Code scope" do
    scope = Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)
    credential_on(scope)

    expect(described_class.has_credentials?(account, :ai)).to be(false)
  end

  it "does not count a credential on an inactive provider" do
    credential_on(create(:ai_provider, account: account, is_active: false))

    expect(described_class.has_credentials?(account, :ai)).to be(false)
  end

  it "counts a credential on an active routable provider" do
    credential_on(create(:ai_provider, account: account, is_active: true))

    expect(described_class.credential_state(account, :ai_provider_credentials)).to include(has_credentials: true, count: 1)
  end
end
