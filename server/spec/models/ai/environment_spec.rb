# frozen_string_literal: true

require "rails_helper"

# Environment campaign, increment 1 — the noun for "which plane is this".
RSpec.describe Ai::Environment do
  let(:account) { create(:account) }

  describe "defaults per account" do
    it "creates dev, ci, staging, ops and prod for a new account, dev as the default, ops and prod protected" do
      slugs = account.environments.ordered.pluck(:slug)
      expect(slugs).to eq(%w[dev ci staging ops prod])

      expect(described_class.default_for(account).slug).to eq("dev")
      expect(account.environments.protected_only.pluck(:slug)).to contain_exactly("ops", "prod")
      expect(account.environments.find_by(slug: "prod").default_decision_authority).to eq("supervised")
    end

    it "does not mint a second default once the operator has moved the flag and removed a seeded slug" do
      ops = account.environments.find_by(slug: "ops")
      account.environments.find_by(slug: "dev").update!(is_default: false)
      ops.update!(is_default: true)
      # staging holds nothing on a fresh account (the extension bootstrap
      # seeds its templates into the default, dev), so it can go.
      account.environments.find_by(slug: "staging").destroy!

      expect { described_class.ensure_defaults_for!(account) }.not_to raise_error
      expect(account.environments.find_by!(slug: "staging").is_default).to be false
      expect(described_class.default_for(account)).to eq(ops)
      expect(account.environments.where(is_default: true).count).to eq(1)
    end

    it "is idempotent and leaves an operator-edited default alone" do
      account.environments.find_by(slug: "ops").update!(name: "Control Plane")
      expect { described_class.ensure_defaults_for!(account) }.not_to change { account.environments.count }
      expect(account.environments.find_by(slug: "ops").name).to eq("Control Plane")
    end
  end

  describe "invariants" do
    it "refuses a duplicate slug inside one account and allows it across accounts" do
      dup = described_class.new(account: account, slug: "prod", name: "Again")
      other = described_class.new(account: create(:account), slug: "custom", name: "Custom")

      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
      expect(other).to be_valid
    end

    it "allows exactly one default per account" do
      second = described_class.new(account: account, slug: "second", name: "Second", is_default: true)
      expect(second).not_to be_valid
      expect(second.errors[:is_default]).to be_present
    end

    it "accepts only the known decision authorities and positive blast radii" do
      env = described_class.new(account: account, slug: "x", name: "X", default_decision_authority: "yolo")
      expect(env).not_to be_valid
      env.default_decision_authority = "monitored"
      env.max_blast_radius = 0
      expect(env).not_to be_valid
      env.max_blast_radius = 3
      expect(env).to be_valid
    end
  end

  describe ".find_for_account" do
    it "resolves by slug or id inside the account only" do
      prod = account.environments.find_by(slug: "prod")
      expect(described_class.find_for_account(account.id, "PROD")).to eq(prod)
      expect(described_class.find_for_account(account.id, prod.id)).to eq(prod)
      expect(described_class.find_for_account(create(:account).id, prod.id)).to be_nil
      expect(described_class.find_for_account(account.id, "not-a-uuid-or-slug")).to be_nil
    end
  end

  describe "the promotion ladder (increment 4)" do
    it "seeds dev, ci and ops as following publishes and staging, prod as pinned" do
      follows = account.environments.ordered.map { |e| [ e.slug, e.follows_publish? ] }.to_h
      expect(follows).to eq("dev" => true, "ci" => true, "staging" => false, "ops" => true, "prod" => false)
    end

    it "orders the ladder by tier then position and names each rung's predecessor" do
      expect(described_class.ladder_for(account).map(&:slug)).to eq(%w[dev ci staging ops prod])
      env = ->(slug) { account.environments.find_by!(slug: slug) }
      expect(env.("dev").ladder_predecessor).to be_nil
      # ci is a sibling of dev (same tier), not its successor
      expect(env.("ci").ladder_predecessor).to be_nil
      # only PINNED environments are rungs: ops follows publishes and is skipped over
      expect(env.("staging").ladder_predecessor).to be_nil
      expect(env.("ops").ladder_predecessor.slug).to eq("staging")
      expect(env.("prod").ladder_predecessor.slug).to eq("staging")
      env.("ops").update!(auto_promote_on_publish: false)
      expect(env.("prod").ladder_predecessor.slug).to eq("ops")
    end

    it "tells the promotion-mode listener seam when a plane flips between following and pinned, and only then" do
      listener = double("listener")
      allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(Powernode::ExtensionRegistry).to receive(:provider).with(:environment_promotion_mode_listener).and_return(listener)
      ops = account.environments.find_by!(slug: "ops")

      expect(listener).to receive(:call).with(environment: ops).twice
      ops.update!(auto_promote_on_publish: false)
      ops.update!(name: "Operations (renamed)")
      ops.update!(auto_promote_on_publish: true)
    end

    it "validates max_blast_radius as a positive integer or nil" do
      env = account.environments.find_by!(slug: "ops")
      expect(env.update(max_blast_radius: 0)).to be false
      expect(env.update(max_blast_radius: nil)).to be true
      expect(env.update(max_blast_radius: 3)).to be true
    end
  end

  describe "projects" do
    it "attach to an environment of their own account only" do
      env = account.environments.find_by(slug: "staging")
      project = Ai::Project.new(account: account, name: "Ledger", environment: env)
      expect(project).to be_valid

      foreign = Ai::Project.new(account: create(:account), name: "Ledger", environment: env)
      expect(foreign).not_to be_valid
      expect(foreign.errors[:environment]).to be_present
    end
  end
end
