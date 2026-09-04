# frozen_string_literal: true

require "rails_helper"

# IMP-e8513b30152d — the `claude-code` provider scope Claude Code runs are
# recorded under (Ai::ClaudeExport::ExecutionRecorder) is a BASELINE seed: one
# inactive, credential-less row per account, keyed by a source_key so a re-seed
# adopts rather than duplicates. Seeds never re-run after first boot, so the
# same seam (Ai::ClaudeExport::ProviderScopeSeeder) is also called by
# Accounts::ProvisionService for tenants created later — pinned in
# spec/services/accounts/provision_service_claude_code_scope_spec.rb.
RSpec.describe "ai_claude_code_provider_seed" do
  def load_seed!
    silence_warnings { load Rails.root.join("db", "seeds", "ai_claude_code_provider_seed.rb") }
  end

  let(:source_key) { Ai::ClaudeExport::ProviderScopeSeeder::SOURCE_KEY }

  it "is registered in db/seeds.rb's baseline block" do
    seeds = File.read(Rails.root.join("db", "seeds.rb"))
    baseline_block = seeds[/^if Powernode::Seeds\.baseline\?\n.*?^end\n/m]
    expect(baseline_block).to be_present
    expect(baseline_block).to include("safe_load('ai_claude_code_provider_seed.rb')")
  end

  it "is a no-op on a fresh install with no account yet" do
    expect(Account.count).to eq(0)
    expect { load_seed! }.not_to raise_error
    expect(Ai::Provider.where(slug: "claude-code")).to be_empty
  end

  context "with accounts" do
    let!(:first_account) { create(:account) }
    let!(:second_account) { create(:account) }

    it "creates one inactive, non-routable, credential-less claude-code scope per account, keyed by source_key" do
      expect { load_seed! }.to change { Ai::Provider.where(slug: "claude-code").count }.from(0).to(2)

      [ first_account, second_account ].each do |account|
        scope = account.ai_providers.find_by(slug: "claude-code")
        expect(scope).to be_present
        expect(scope.is_active).to be false
        expect(scope.provider_type).to eq("anthropic")
        expect(scope.provider_identifier).to eq(source_key)
        expect(scope.metadata).to include("execution_source" => "claude_code", "synthetic" => true, "source_key" => source_key)
        expect(scope.provider_credentials).to be_empty
        expect(Ai::Provider.platform_routable.where(account: account)).not_to include(scope)
      end
    end

    it "is idempotent and adopts a scope minted before the seed existed, backfilling its source_key" do
      legacy = create(:ai_provider, account: first_account, slug: "claude-code", name: "Claude Code (local sessions)",
                                    provider_type: "anthropic", is_active: false, supported_models: [],
                                    metadata: { "execution_source" => "claude_code", "synthetic" => true })
      expect(legacy.provider_identifier).to be_nil

      load_seed!
      load_seed!

      expect(Ai::Provider.where(slug: "claude-code").count).to eq(2)
      expect(first_account.ai_providers.where(slug: "claude-code").count).to eq(1)
      expect(legacy.reload.provider_identifier).to eq(source_key)
      expect(legacy.metadata["source_key"]).to eq(source_key)
    end
  end
end
