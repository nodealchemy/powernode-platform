# frozen_string_literal: true

require "rails_helper"

# Environment campaign, increment 4 — the operator's knobs on a plane.
RSpec.describe Ai::Tools::EnvironmentTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:tool)    { described_class.new(account: account, user: user) }

  def call(action, **rest) = tool.execute(params: { action: action }.merge(rest))

  it "lists the ladder in order with every knob and each rung's predecessor" do
    r = call("environment_list")
    expect(r[:success]).to be true
    rows = r.dig(:data, :environments)
    expect(rows.map { |e| e[:slug] }).to eq(%w[dev ci staging ops prod])
    prod = rows.last
    expect(prod).to include(auto_promote_on_publish: false, is_protected: true, ladder_predecessor_slug: "staging",
                            max_blast_radius: nil, default_decision_authority: "supervised")
    expect(r.dig(:data, :scope)).to eq("account")
  end

  it "updates only the keys given, by slug or id, and reports what changed" do
    r = call("environment_update", environment: "ops", max_blast_radius: 2, approval_required_categories: [ "release.*" ])
    expect(r[:success]).to be true
    expect(r.dig(:data, :updated)).to contain_exactly("max_blast_radius", "approval_required_categories")
    ops = account.environments.find_by!(slug: "ops")
    expect(ops.max_blast_radius).to eq(2)
    expect(ops.approval_required_categories).to eq([ "release.*" ])
    expect(ops.follows_publish?).to be true

    r2 = call("environment_update", environment: ops.id, auto_promote_on_publish: false, max_blast_radius: nil)
    expect(r2[:success]).to be true
    expect(ops.reload.follows_publish?).to be false
    expect(ops.max_blast_radius).to be_nil
  end

  it "keeps a string-keyed false (an MCP body) instead of dropping it" do
    r = tool.execute(params: { "action" => "environment_update", "environment" => "ops",
                               "auto_promote_on_publish" => false }.with_indifferent_access)
    expect(r[:success]).to be true
    expect(account.environments.find_by!(slug: "ops").follows_publish?).to be false
  end

  it "refuses an unknown environment, another account's, an invalid value and an empty update" do
    expect(call("environment_update", environment: "moon", max_blast_radius: 1)[:success]).to be false
    foreign = create(:account).environments.find_by!(slug: "prod")
    expect(call("environment_update", environment: foreign.id, max_blast_radius: 1)[:success]).to be false
    bad = call("environment_update", environment: "dev", default_decision_authority: "yolo")
    expect(bad[:success]).to be false
    expect(bad[:error]).to include("refused")
    expect(call("environment_update", environment: "dev")[:error]).to include("nothing to update")
  end

  it "requires ai.governance.manage to update but only ai.governance.read to list" do
    reader = described_class.new(account: account, user: create(:user, account: account, permissions: [ "ai.governance.read" ]))
    expect(reader.execute(params: { action: "environment_list" })[:success]).to be true
    denied = reader.execute(params: { action: "environment_update", environment: "dev", max_blast_radius: 1 })
    expect(denied[:success]).to be false
    expect(denied[:error]).to include("ai.governance.manage")
  end
end
