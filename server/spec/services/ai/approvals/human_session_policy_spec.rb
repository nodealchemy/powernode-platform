# frozen_string_literal: true

require "rails_helper"

# MCP identity plan D1 guard (b): which parked requests only a person, in their
# own session, may decide. Always a human-only action. Otherwise the account's
# own intervention policy rows decide first (conditions.requires_human_session
# true or false), then the operator's site-wide category list, then the code
# default, which applies because seeds never re-run on a live install:
# protected-environment actions, destructive actions, spend and campaign
# lifecycle.
RSpec.describe "Ai::Approvals::HumanSessionPolicy" do
  let(:setting_key) { Ai::Approvals::HumanSessionPolicy::SETTING_KEY }
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:chain) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: "autonomy_action", status: "active",
      is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "s1", "approvers" => [ "*" ], "required_approvals" => 1 } ]
    )
  end

  def request_for(category = nil, **data)
    data = data.merge(action_category: category) if category
    chain.create_request!(source_type: "X", source_id: SecureRandom.uuid, description: "d", request_data: data)
  end

  def mark!(category, value, target: account, active: true)
    Ai::InterventionPolicy.create!(account: target, action_category: category, scope: "action_type",
                                   policy: "require_approval", priority: 1, is_active: active,
                                   conditions: { "requires_human_session" => value })
  end

  describe "the code default (nothing configured)" do
    it "flags campaign lifecycle, spend, destructive-named categories and a protected environment" do
      %w[campaign.resume campaign.spec_probe campaign_land project.cost_control
         system.instance_pool_create system.instance_reap system.volume_snapshot_delete].each do |category|
        expect(request_for(category).requires_human_session?).to be(true), category
      end

      protected_env = request_for("spec.plain", environment: { id: SecureRandom.uuid, slug: "prod", is_protected: true })
      expect(protected_env.requires_human_session?).to be(true)
    end

    it "leaves an ordinary category, and an unprotected environment, to today's doors (the other arm)" do
      expect(request_for("spec.plain").requires_human_session?).to be(false)
      expect(request_for("mission_land").requires_human_session?).to be(false)
      expect(request_for("spec.plain", environment: { slug: "dev", is_protected: false }).requires_human_session?)
        .to be(false)
      expect(request_for.requires_human_session?).to be(false)
    end

    it "flags a parked tool call whose declaration is destructive, whatever its category is called" do
      stub_const("SpecWipeTool", Class.new(::Ai::Tools::BaseTool) do
        def self.definition = { name: "spec_wipe_tool", description: "d", parameters: {} }
        declare_action "spec_wipe", mutating: true, destructive: true
        declare_action "spec_touch", mutating: true
      end)

      wipe = request_for("spec.plain", params: { "tool_class" => "SpecWipeTool", "action" => "spec_wipe" })
      touch = request_for("spec.plain", params: { "tool_class" => "SpecWipeTool", "action" => "spec_touch" })
      stranger = request_for("spec.plain", params: { "tool_class" => "Kernel", "action" => "exit" })

      expect(wipe.requires_human_session?).to be(true)
      expect(touch.requires_human_session?).to be(false)
      expect(stranger.requires_human_session?).to be(false)
    end

    it "always flags a human-only request" do
      expect(request_for("spec.plain", requires_human_session: true).requires_human_session?).to be(true)
    end
  end

  describe "the account's intervention policy rows" do
    it "mark a category that the default leaves alone" do
      mark!("spec.plain", true)
      expect(request_for("spec.plain").requires_human_session?).to be(true)
    end

    it "unmark a category that the default flags, even in a protected environment" do
      mark!("campaign.spec_probe", false)
      expect(request_for("campaign.spec_probe").requires_human_session?).to be(false)

      mark!("spec.plain", false)
      expect(request_for("spec.plain", environment: { is_protected: true }).requires_human_session?).to be(false)
    end

    it "never unmark a human-only request" do
      mark!("spec.plain", false)
      expect(request_for("spec.plain", requires_human_session: true).requires_human_session?).to be(true)
    end

    it "prefer the row naming the category over a wildcard row" do
      mark!("*", true)
      mark!("spec.quiet", false)
      expect(request_for("spec.loud").requires_human_session?).to be(true)
      expect(request_for("spec.quiet").requires_human_session?).to be(false)
    end

    it "count only when active, in this account, and carrying the key" do
      mark!("spec.plain", true, active: false)
      mark!("spec.plain", true, target: other_account)
      Ai::InterventionPolicy.create!(account: account, action_category: "campaign.spec_probe", scope: "action_type",
                                     policy: "require_approval", priority: 1, is_active: true, conditions: {})

      expect(request_for("spec.plain").requires_human_session?).to be(false)
      expect(request_for("campaign.spec_probe").requires_human_session?).to be(true)
    end
  end

  describe "the operator's site-wide category list" do
    it "replaces the default category patterns" do
      SiteSetting.set(setting_key,[ "spec.listed*" ], setting_type: "json")

      expect(request_for("spec.listed_one").requires_human_session?).to be(true)
      expect(request_for("campaign.spec_probe").requires_human_session?).to be(false)
      # The environment and destructive arms are not categories, and stay on.
      expect(request_for("spec.plain", environment: { is_protected: true }).requires_human_session?).to be(true)
    end

    it "falls back to the default when the setting is not a list of strings (fail closed)" do
      SiteSetting.set(setting_key,{ "not" => "a list" }, setting_type: "json")
      expect(request_for("campaign.spec_probe").requires_human_session?).to be(true)
    end

    it "yields to the account's own row" do
      SiteSetting.set(setting_key,[ "spec.listed*" ], setting_type: "json")
      mark!("spec.listed_one", false)
      expect(request_for("spec.listed_one").requires_human_session?).to be(false)
    end
  end

  it "reads a gateway request's action_type as its category" do
    expect(request_for(nil, action_type: "campaign_land").requires_human_session?).to be(true)
    expect(request_for(nil, action_type: "mission_land").requires_human_session?).to be(false)
  end
end
