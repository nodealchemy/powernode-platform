# frozen_string_literal: true

require "rails_helper"

# HIER-P2I: a conversation that was attached to the GLOBAL canonical concierge
# before the doors learned to clone (every concierge conversation minted before
# this increment) must keep working — so the service resolves its acting agent
# through Ai::Agents::AccountPrincipalResolver: the account's clone, minted on
# first use. The conversation row is not rewritten; only the principal that
# executes is.
RSpec.describe Ai::ConciergeService, "canonical principals never execute (HIER-P2I)" do
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let(:global_concierge) do
    create(:ai_agent, :global, owner_account: seeding_account, is_concierge: true, status: "active",
                               is_system: true, name: "Powernode Assistant", slug: "powernode-assistant",
                               source_key: "powernode-assistant")
  end
  let(:conversation) do
    create(:ai_conversation, account: account, user: user, agent: global_concierge, provider: provider)
  end

  it "acts as the account's clone of a canonical the conversation was attached to" do
    service = described_class.new(conversation: conversation, user: user)

    acting = service.instance_variable_get(:@agent)
    expect(acting.id).not_to eq(global_concierge.id)
    expect(acting.account_id).to eq(account.id)
    expect(acting.cloned_from_id).to eq(global_concierge.id)
    expect(conversation.reload.ai_agent_id).to eq(global_concierge.id)
  end

  it "leaves an account-owned conversation agent untouched" do
    own = create(:ai_agent, account: account, creator: user, provider: provider, is_concierge: true, status: "active")
    conv = create(:ai_conversation, account: account, user: user, agent: own, provider: provider)

    expect(described_class.new(conversation: conv, user: user).instance_variable_get(:@agent)).to eq(own)
  end

  # Q1: a refusal from a guarded writer is a stated, actionable answer, never the generic error.
  describe "when a writer refuses a global row" do
    let(:service) { described_class.new(conversation: conversation, user: user) }
    let(:refusal) { Ai::Agents::GlobalRowRefused.new("Refused: x", reason: "global_canonical_row") }

    it "answers with the no-shadow wording from the top-level rescue" do
      allow(service).to receive(:find_credential).and_raise(refusal)

      expect { service.process_message("hi") }.to change { conversation.messages.count }.by(1)
      expect(conversation.messages.last.content).to eq(Ai::Agents::ShadowWriteGuard::NO_SHADOW_MESSAGE)
    end

    it "does not let the router's best-effort rescue swallow it into a passthrough" do
      allow(Ai::ConciergeRouter).to receive(:route).and_raise(refusal)

      service.process_message("hi")

      expect(conversation.messages.last.content).to eq(Ai::Agents::ShadowWriteGuard::NO_SHADOW_MESSAGE)
    end
  end
end
