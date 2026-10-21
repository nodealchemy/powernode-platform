# frozen_string_literal: true

require "rails_helper"

# Round-4 L-A: every tool the concierge bridge builds itself carries the
# bridge's driver, so a concierge built from a tool door (driver unknown)
# never lets a tool fall back to its stand-in `user`, whatever the tool does.
RSpec.describe Ai::ConciergeToolBridge, "driver on tools it builds" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:runner) { create(:user, account: account) }
  let(:concierge) { create(:ai_agent, account: account, creator: creator, is_concierge: true) }
  let(:conversation) { create(:ai_conversation, account: account, user: creator, agent: concierge) }

  def provisioning_tool_driver(driving_user)
    bridge = described_class.new(agent: concierge, account: account, conversation: conversation, user: creator,
                                 driving_user: driving_user)
    allow_any_instance_of(Ai::Provisioning::IntentCaptureService).to receive(:classify)
      .and_return({ intent_type: described_class::PROVISIONING_INTENT, confidence: 1.0 })
    built = nil
    allow(Ai::Tools::ProvisioningTool).to receive(:new).and_wrap_original do |m, **kw|
      built = m.call(**kw)
      allow(built).to receive(:execute).and_return({ success: true })
      built
    end
    bridge.send(:classify_and_dispatch_provisioning, natural_language: "give me a running memcached instance")
    built
  end

  it "hands the provisioning tool an explicit nil driver from a tool-door concierge" do
    tool = provisioning_tool_driver(nil)
    expect(tool.instance_variable_defined?(:@driving_user)).to be(true)
    expect(tool.send(:known_driving_user)).to be_nil
  end

  it "hands it the REST driver otherwise" do
    expect(provisioning_tool_driver(runner).send(:known_driving_user)).to eq(runner)
  end
end
