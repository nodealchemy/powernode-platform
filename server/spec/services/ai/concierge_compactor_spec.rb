# frozen_string_literal: true

require "rails_helper"

# M-5: threshold compaction replaces the sliding window. Past the budget, the
# history before the current turn is summarized once; later requests start with
# the summary plus the current turn and replay nothing earlier.
RSpec.describe Ai::ConciergeCompactor do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:ai_conversation, account: account, user: user, agent: agent, status: "active") }
  let(:history) { Ai::ConciergeHistory.new(conversation) }
  let(:llm) { instance_double(WorkerLlmClient) }

  def compactor(budget)
    described_class.new(history: history, llm_client: llm, model: "claude-opus-5",
                        system_prompt: -> { "core prompt" }, char_budget: budget)
  end

  before do
    conversation.add_user_message("first question", user: user)
    history.freeze_turn_context!("context one")
    conversation.add_assistant_message("first answer")
    conversation.add_user_message("second question", user: user)
    history.freeze_turn_context!("context two")
  end

  it "does nothing under the budget" do
    expect(compactor(1_000_000).compact_if_needed!).to be(false)
    expect(history.messages.first).to eq(role: "user", content: "first question")
  end

  context "past the budget" do
    before do
      allow(llm).to receive(:complete).and_return(
        Ai::Llm::Response.new(content: "<summary>asked first question; answered it</summary>")
      )
    end

    it "summarizes everything before the current turn, reusing the conversation's prefix" do
      compactor(10).compact_if_needed!

      expect(llm).to have_received(:complete) do |messages:, system_prompt:, **|
        expect(system_prompt).to eq("core prompt")
        expect(messages.first).to eq(role: "user", content: "first question")
        expect(messages.to_s).not_to include("second question")
        expect(messages.last[:content]).to include("<summary></summary>")
      end
    end

    it "starts later requests with the summary plus the current turn" do
      compactor(10).compact_if_needed!

      expect(history.messages).to eq([
        { role: "user", content: "<conversation-summary>\nasked first question; answered it\n</conversation-summary>" },
        { role: "user", content: "second question" },
        { role: "system", content: "context two", clear_at: "next_user_message" }
      ])
    end

    it "keeps the post-compaction history append-only on the next turn" do
      compactor(10).compact_if_needed!
      after_compaction = history.messages

      conversation.add_assistant_message("second answer")
      conversation.add_user_message("third question", user: user)
      history.freeze_turn_context!("context three")

      expect(history.messages.first(after_compaction.size)).to eq(after_compaction)
    end
  end

  it "skips compaction (and keeps the full history) when the summarizer fails" do
    allow(llm).to receive(:complete).and_raise(WorkerLlmClient::WorkerLlmError, "down")

    expect(compactor(10).compact_if_needed!).to be(false)
    expect(history.messages.first).to eq(role: "user", content: "first question")
  end

  it "sizes the budget from the model's context window, with a fixed fallback" do
    expect(described_class.char_budget_for("claude-opus-5")).to eq((1_000_000 * 0.6 * 4).to_i)
    expect(described_class.char_budget_for("gpt-4.1-mini")).to eq(described_class::FALLBACK_CHAR_BUDGET)
  end
end
