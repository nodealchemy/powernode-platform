# frozen_string_literal: true

require "rails_helper"

# Deploy-4 incident (2026-09-04), MODEL-LAYER half. The seed layer now
# deliberately leaves a GLOBAL canonical provider-less when no provider can run
# its model pin (IMP-42881dd9aed0, commits 7d313dba0 + 5136e3975) — a global
# canonical is a template, and Ai::Agents::AccountPrincipalResolver.provider_for_pin
# picks a runnable provider per-account at execution time.
#
# But #auto_resolve_provider_from_model treated that sanctioned state as
# invalid: the callback fires on any mcp_metadata change, a provider-less row
# does not take its early return, and finding no active provider of the pin's
# family it added a base error. So a provider-less claude-pinned canonical on a
# plane with no active Anthropic provider sat valid while untouched and became
# UNSAVEABLE the moment anything touched its pin — the same class of mid-seed
# save failure that aborted the hierarchy seed.
#
# The hard error belongs to ACCOUNT-SCOPED rows only (#account_scoped_row?,
# the same predicate that makes `provider` mandatory there): those genuinely
# cannot execute without a provider.
RSpec.describe Ai::Agent, type: :model do
  let(:owner_account) { create(:account) }

  # The deploy-4 plane: the only ACTIVE provider is OpenAI.
  let!(:openai) { create(:ai_provider, :openai, account: owner_account, is_active: true, priority_order: 1) }

  # A claude-pinned GLOBAL canonical carrying no provider, as the seeds now
  # mint it. Built provider-first on an INACTIVE anthropic row (which the
  # callback's early return accepts) and then detached out of band, because
  # creating it provider-less is itself part of what this spec pins.
  def provider_less_canonical
    anthropic = create(:ai_provider, :anthropic, account: owner_account, is_active: false, priority_order: 2)
    agent = create(:ai_agent, :global, owner_account: owner_account, provider: anthropic,
                                       agent_type: "content_generator",
                                       mcp_metadata: { "model_config" => { "model" => "claude-sonnet-5" } })
    agent.update_columns(ai_provider_id: nil)
    agent.reload
  end

  describe "a GLOBAL canonical with no provider that can run its pin" do
    it "saves a pin change instead of hard-erroring, and stays provider-less" do
      agent = provider_less_canonical

      expect {
        agent.update!(mcp_metadata: { "model_config" => { "model" => "claude-opus-5" } })
      }.not_to raise_error

      expect(agent.reload.ai_provider_id).to be_nil
      expect(agent.mcp_metadata.dig("model_config", "model")).to eq("claude-opus-5")
    end

    it "can be CREATED provider-less, which is the state the seeds now mint" do
      agent = build(:ai_agent, :global, owner_account: owner_account, provider: nil,
                                        agent_type: "content_generator",
                                        mcp_metadata: { "model_config" => { "model" => "claude-sonnet-5" } })

      expect(agent.save).to be(true), -> { "expected save, got: #{agent.errors.full_messages.join('; ')}" }
      expect(agent.reload.ai_provider_id).to be_nil
    end

    it "still attaches an ACTIVE provider of the pin's family when one exists" do
      agent = provider_less_canonical
      runnable = create(:ai_provider, :anthropic, account: owner_account, is_active: true, priority_order: 3,
                                                  name: "Anthropic (runnable)", slug: "anthropic-runnable")

      agent.update!(mcp_metadata: { "model_config" => { "model" => "claude-opus-5" } })

      expect(agent.reload.ai_provider_id).to eq(runnable.id)
    end

    # NOT relaxed: a global row still carrying a provider of the WRONG family is
    # the deploy-4 row itself, and #model_matches_provider must keep refusing it.
    it "still refuses a global row whose attached provider cannot run the pin" do
      agent = create(:ai_agent, :global, owner_account: owner_account, provider: openai,
                                         mcp_metadata: { "model_config" => { "model" => "gpt-4o" } })

      agent.mcp_metadata = { "model_config" => { "model" => "claude-sonnet-5" } }

      expect(agent).not_to be_valid
      expect(agent.errors[:base].join).to include("incompatible with openai provider")
    end
  end

  describe "an ACCOUNT-SCOPED row" do
    it "still hard-errors when no active provider of the pin's family exists" do
      agent = create(:ai_agent, account: owner_account, provider: openai,
                                mcp_metadata: { "model_config" => { "model" => "gpt-4o" } })

      agent.mcp_metadata = { "model_config" => { "model" => "claude-sonnet-5" } }

      expect(agent).not_to be_valid
      expect(agent.errors[:base].join).to include("No active anthropic provider found")
    end
  end
end
