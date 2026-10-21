# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProviderDefaultService do
  let(:account) { create(:account) }

  def working(name, order, default: false)
    create(:ai_provider, account: account, name: name, provider_type: "custom", priority_order: order,
                         is_active: true, metadata: default ? { "is_default" => true } : {}).tap do |p|
      create(:ai_provider_credential, account: account, provider: p)
    end
  end

  describe ".ensure_default!" do
    it "does not displace a working default" do
      current = working("Current", 1, default: true)
      newcomer = working("Newcomer", 2)

      expect(described_class.ensure_default!(newcomer)).to be(false)

      expect(Ai::Provider.default_for_account(account)).to eq(current)
      expect(newcomer.reload.priority_order).to eq(2)
    end

    it "takes over when the current default can no longer serve" do
      broken = working("Broken", 1, default: true)
      broken.update_columns(is_active: false)
      newcomer = working("Newcomer", 2)

      expect(described_class.ensure_default!(newcomer)).to be(true)
      expect(newcomer.reload.metadata["is_default"]).to be(true)
    end
  end

  describe ".set_default!" do
    it "locks every account provider, target included, in ONE ordered statement (no lock-order deadlock)" do
      working("A", 1, default: true)
      target = working("B", 2)
      working("C", 3)
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].include?("FOR UPDATE") }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.set_default!(target)
      end

      expect(statements.size).to eq(1)
      expect(statements.first).to match(/ORDER BY "ai_providers"\."id" ASC/i)
      expect(statements.first).not_to match(/<>|!=/)
    end
  end

  describe ".heal!" do
    it "moves the default to the best working provider when the flagged one stopped being eligible" do
      broken = working("Broken", 1, default: true)
      backup = working("Backup", 2)
      Ai::ProviderCredential.where(ai_provider_id: broken.id).delete_all
      broken.reload

      described_class.heal!(account)

      expect(Ai::Provider.default_for_account(account)).to eq(backup)
      expect(broken.reload.metadata["is_default"]).to be(false)
    end

    it "leaves no default when nothing is eligible" do
      only = working("Only", 1, default: true)
      only.update_columns(is_active: false)

      described_class.heal!(account)

      expect(only.reload.metadata["is_default"]).to be(false)
    end
  end

  describe "Ai::Provider.default_for_account" do
    it "ignores a flagged provider that cannot serve" do
      flagged = create(:ai_provider, account: account, is_active: true, metadata: { "is_default" => true })

      expect(flagged).to be_persisted
      expect(Ai::Provider.default_for_account(account)).to be_nil
    end
  end

  describe "healing on removal" do
    it "heals when the default provider is destroyed (its default-only credential goes with it)" do
      first = working("First", 1, default: true)
      second = working("Second", 2)

      expect(first.destroy).to be_truthy

      expect(Ai::Provider.default_for_account(account)).to eq(second)
    end

    it "heals when a credential destroy leaves the default without an active credential" do
      first = working("First", 1, default: true)
      second = working("Second", 2)
      spare = create(:ai_provider_credential, account: account, provider: first, is_active: false)
      expect(spare).to be_persisted

      first.provider_credentials.active.find_each(&:destroy)

      expect(Ai::Provider.default_for_account(account)).to eq(second)
    end
  end

  describe "clones of canonical agents" do
    let(:creator) { create(:user, account: account) }

    def clone_on(provider, pin: nil)
      create(:ai_agent, account: account, creator: creator, provider: provider,
                        cloned_from_id: create(:ai_agent, :global, owner_account: account).id,
                        mcp_metadata: pin ? { "model_config" => { "model" => pin } } : {})
    end

    it "repoints UNPINNED resolver-minted clones to the new default and leaves pinned clones alone" do
      old = working("Old", 1, default: true)
      chosen = working("Chosen", 2)
      unpinned = clone_on(old)
      pinned = clone_on(old, pin: "pinned-model-x")
      allow(Ai::Agent).to receive(:provider_family_for).and_return(nil)

      described_class.set_default!(chosen)

      expect(unpinned.reload.ai_provider_id).to eq(chosen.id)
      expect(pinned.reload.ai_provider_id).to eq(old.id)
    end

    it "repoints unpinned clones off a provider that is being destroyed" do
      doomed = working("Doomed", 1, default: true)
      survivor = working("Survivor", 2)
      unpinned = clone_on(doomed)

      described_class.release_clones!(doomed)
      expect(doomed.reload.destroy).to be_truthy

      expect(unpinned.reload.ai_provider_id).to eq(survivor.id)
    end
  end
end
