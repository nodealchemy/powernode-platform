# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Agents::CanonicalContentRefresh do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:old_description) { "Scores and reranks RAG search results." }
  let(:new_description) { "Scores and reranks RAG search results. Use when retrieved chunks need ordering." }
  let(:agent) do
    create(:ai_agent, account: account, creator: user, description: old_description,
                      mcp_metadata: { "system_prompt" => "old prompt", "other" => "kept" })
  end

  def stamp(agent, field)
    agent.reload.mcp_metadata.dig(described_class::STAMP_KEY, field)
  end

  describe ".apply!" do
    it "writes a field that still holds a listed previous value, stamps it, and keeps the replaced text" do
      outcome = described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })

      expect(outcome.written).to eq([ "description" ])
      expect(agent.reload.description).to eq(new_description)
      expect(stamp(agent, "description")).to eq("digest" => described_class.digest(new_description),
                                                 "replaced" => old_description)
      expect(agent.mcp_metadata["other"]).to eq("kept")
    end

    it "writes a field that still holds what the last run stamped" do
      described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })
      newer = "#{new_description} Second wave."

      outcome = described_class.apply!(agent.reload, { description: newer })

      expect(outcome.written).to eq([ "description" ])
      expect(agent.reload.description).to eq(newer)
    end

    it "fills a blank field" do
      agent.update_columns(description: nil)

      outcome = described_class.apply!(agent.reload, { description: new_description })

      expect(outcome.written).to eq([ "description" ])
      expect(agent.reload.description).to eq(new_description)
    end

    it "writes system_prompt into mcp_metadata, where Ai::Agent#system_prompt reads it" do
      outcome = described_class.apply!(agent, { system_prompt: "new prompt" }, previous: { system_prompt: [ "old prompt" ] })

      expect(outcome.written).to eq([ "system_prompt" ])
      expect(agent.reload.mcp_metadata["system_prompt"]).to eq("new prompt")
    end

    it "stamps without writing when the row already holds the seeded value" do
      outcome = described_class.apply!(agent, { description: old_description })

      expect(outcome.unchanged).to eq([ "description" ])
      expect(stamp(agent, "description")).to eq("digest" => described_class.digest(old_description))
    end

    context "when an operator edited the field (the fixture the guard exists for)" do
      let(:operator_text) { "Our team's own reranker description." }

      it "skips and reports an unstamped row whose text is not a listed previous value" do
        agent.update!(description: operator_text)

        outcome = described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })

        expect(outcome.skipped).to eq([ "description" ])
        expect(outcome).to be_skipped
        expect(agent.reload.description).to eq(operator_text)
      end

      it "skips and reports a stamped row edited after the stamp" do
        described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })
        agent.reload.update!(description: operator_text)

        outcome = described_class.apply!(agent.reload, { description: "#{new_description} Second wave." })

        expect(outcome.skipped).to eq([ "description" ])
        expect(agent.reload.description).to eq(operator_text)
      end

      it "still writes the untouched field on the same row" do
        agent.update!(description: operator_text)

        outcome = described_class.apply!(agent, { description: new_description, system_prompt: "new prompt" },
                                         previous: { description: [ old_description ], system_prompt: [ "old prompt" ] })

        expect(outcome.skipped).to eq([ "description" ])
        expect(outcome.written).to eq([ "system_prompt" ])
        expect(agent.reload.mcp_metadata["system_prompt"]).to eq("new prompt")
      end
    end

    it "rejects a field it does not manage" do
      expect { described_class.apply!(agent, { name: "x" }) }.to raise_error(ArgumentError, /unknown canonical field/)
    end
  end

  describe ".revert!" do
    it "restores the replaced value when the field still holds the wave's value" do
      described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })

      described_class.revert!(agent.reload, { description: new_description })

      expect(agent.reload.description).to eq(old_description)
      expect(stamp(agent, "description")).to eq("digest" => described_class.digest(old_description))
    end

    it "leaves a field an operator changed after the wave" do
      described_class.apply!(agent, { description: new_description }, previous: { description: [ old_description ] })
      agent.reload.update!(description: "operator text")

      described_class.revert!(agent.reload, { description: new_description })

      expect(agent.reload.description).to eq("operator text")
    end
  end
end
