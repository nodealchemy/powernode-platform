# frozen_string_literal: true

require "rails_helper"

# A promotion grant is a person's standing, time-boxed permission for ONE agent
# to perform ONE gated category (release.promote) into ONE environment. These
# examples pin the row's own limits: what it may say at issue, and what can
# never change after it exists.
RSpec.describe Ai::PromotionGrant, type: :model do
  let(:account) { create(:account) }
  let(:ops) { account.environments.find_by!(slug: "ops") }

  def build_grant(**attrs)
    build(:ai_promotion_grant, account: account, **attrs).tap do |grant|
      # The validation errors on one attribute, after running them.
      grant.define_singleton_method(:errors_on_validate) { |attr| validate; errors[attr] }
    end
  end

  describe "issue-time limits" do
    it "is valid when issued from a person's own session" do
      expect(build_grant).to be_valid
    end

    it "caps the lifetime at 24 hours from creation" do
      expect(build_grant(expires_at: 24.hours.from_now - 1.minute)).to be_valid

      grant = build_grant(expires_at: 24.hours.from_now + 1.minute)
      expect(grant).not_to be_valid
      expect(grant.errors[:expires_at].join).to include("24 hours")
    end

    it "refuses an expiry in the past" do
      grant = build_grant(expires_at: 1.minute.ago)
      expect(grant).not_to be_valid
      expect(grant.errors[:expires_at]).to be_present
    end

    it "allows only categories on the allowlist" do
      grant = build_grant(action_category: "system.task.terminate")
      expect(grant).not_to be_valid
      expect(grant.errors[:action_category]).to be_present
    end

    it "requires a reason, an agent and an environment" do
      expect(build_grant(reason: "  ")).not_to be_valid
      expect(build_grant(agent: nil)).not_to be_valid
      expect(build_grant(environment: nil)).not_to be_valid
    end

    it "refuses max_uses below 1" do
      expect(build_grant(max_uses: 0)).not_to be_valid
      expect(build_grant(max_uses: 3)).to be_valid
    end

    it "refuses an agent or environment from another account" do
      other = create(:account)
      expect(build_grant(agent: create(:ai_agent, account: other))).not_to be_valid
      expect(build_grant(environment: other.environments.find_by!(slug: "ops"))).not_to be_valid
    end

    it "refuses a module id that is not a uuid" do
      grant = build_grant(module_ids: [ "not-a-uuid" ])
      expect(grant).not_to be_valid
      expect(grant.errors[:module_ids]).to be_present
    end

    # The tool door can never issue a grant, whatever credential it carries:
    # only the REST session origin can, and the row refuses every other.
    it "refuses creation from any door that is not a person's own session" do
      (Ai::Tools::CallOrigin::ALL + [ Ai::ApprovalDecision::REST_OTHER, nil ]).each do |origin|
        grant = build_grant(issuing_origin: origin)
        expect(grant).not_to be_valid, "origin #{origin.inspect} was admitted"
        expect(grant.errors[:base].join).to include("own session")
      end
    end
  end

  # MEDIUM-1: a strict plane — supervised, or tier 3 and up (prod) — takes a
  # grant only when it is bounded on every axis the server can enforce.
  describe "strict planes (supervised, or tier >= 3)" do
    let(:prod) { account.environments.find_by!(slug: "prod") }
    let(:bounded) { { environment: prod, max_uses: 3, module_ids: [ SecureRandom.uuid ], expires_at: 4.hours.from_now - 1.minute } }

    it "admits a grant bounded by max uses, modules and a 4h lifetime" do
      expect(build_grant(**bounded)).to be_valid
    end

    it "requires max_uses, at most #{described_class::STRICT_MAX_USES}" do
      expect(build_grant(**bounded, max_uses: nil).errors_on_validate(:max_uses)).to be_present
      expect(build_grant(**bounded, max_uses: described_class::STRICT_MAX_USES + 1).errors_on_validate(:max_uses)).to be_present
      expect(build_grant(**bounded, max_uses: described_class::STRICT_MAX_USES)).to be_valid
    end

    it "requires at least one module" do
      expect(build_grant(**bounded, module_ids: []).errors_on_validate(:module_ids)).to be_present
    end

    it "caps the lifetime at 4 hours" do
      grant = build_grant(**bounded, expires_at: 4.hours.from_now + 1.minute)
      expect(grant.errors_on_validate(:expires_at).join).to include("4 hours")
    end

    it "applies to a supervised plane below tier 3 too" do
      staging = account.environments.find_by!(slug: "staging")
      staging.update!(default_decision_authority: "supervised")
      expect(build_grant(environment: staging, expires_at: 8.hours.from_now)).not_to be_valid
    end

    it "does not apply to ops (monitored, tier 2): 24h, any module, no use cap" do
      expect(build_grant(environment: ops, expires_at: 23.hours.from_now)).to be_valid
      expect(build_grant(environment: ops).strict_plane?).to be(false)
      expect(build_grant(environment: prod).strict_plane?).to be(true)
    end
  end

  describe "granter_driven_only" do
    it "defaults to false" do
      expect(build_grant.granter_driven_only).to be(false)
    end

    it "is fixed at issue like every other term" do
      grant = create(:ai_promotion_grant, account: account)
      expect(grant.update(granter_driven_only: true)).to be(false)
    end
  end

  describe "after issue" do
    let!(:grant) { create(:ai_promotion_grant, account: account, max_uses: 2) }

    it "cannot be extended or retargeted" do
      expect(grant.update(expires_at: grant.expires_at + 1.hour)).to be(false)
      grant.reload
      expect(grant.update(max_uses: 5)).to be(false)
      grant.reload
      expect(grant.update(environment: account.environments.find_by!(slug: "prod"))).to be(false)
      grant.reload
      expect(grant.update(module_ids: [ SecureRandom.uuid ])).to be(false)
    end

    it "cannot be un-revoked once revoked" do
      grant.revoke!(by: grant.granted_by)
      expect(grant.reload).to be_revoked

      expect(grant.update(revoked_at: nil, revoked_by_id: nil)).to be(false)
      expect(grant.reload.revoked_at).to be_present
    end

    it "refuses a uses_count above max_uses" do
      expect(grant.update(uses_count: 3)).to be(false)
    end

    it "reports its status" do
      expect(grant.status).to eq("active")
      expect(grant.uses_remaining).to eq(2)

      grant.update_columns(uses_count: 2)
      expect(grant.reload.status).to eq("exhausted")

      travel_to(grant.expires_at + 1.second) { expect(grant.status).to eq("expired") }
    end
  end

  describe "the category catalog seam (Ai::PromotionGrants::Catalog)" do
    let(:catalog) { Ai::PromotionGrants::Catalog }

    it "answers no permission when no extension registers a catalog (fail closed)" do
      allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(Powernode::ExtensionRegistry).to receive(:provider).with(catalog::PROVIDER_KEY).and_return(nil)

      expect(catalog.required_permission("release.promote")).to be_nil
      expect(catalog.subjects(account: account, action_category: "release.promote")).to eq([])
    end

    it "never asks the provider about a category outside the allowlist" do
      provider = double("catalog provider")
      allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(Powernode::ExtensionRegistry).to receive(:provider).with(catalog::PROVIDER_KEY).and_return(provider)
      allow(provider).to receive(:required_permission).and_return("ai.agents.read")

      expect(catalog.required_permission("system.task.terminate")).to be_nil
      expect(catalog.required_permission("release.promote")).to eq("ai.agents.read")
    end
  end
end
