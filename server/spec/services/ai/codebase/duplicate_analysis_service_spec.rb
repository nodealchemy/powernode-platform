# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Codebase::DuplicateAnalysisService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, base_path: "/nonexistent") }

  let(:clone_group) do
    {
      format: "ruby", lines: 12,
      a: { file: "server/app/a.rb", start: 1, end: 12 },
      b: { file: "server/app/b.rb", start: 5, end: 16 },
      fragment: "def foo; end"
    }
  end

  describe "#detect" do
    it "fails fast when base_path does not exist" do
      result = service.detect
      expect(result[:success]).to be false
      expect(result[:error]).to match(/base_path does not exist/)
    end
  end

  describe "LLM triage plumbing" do
    describe "#run_triage" do
      it "returns items untriaged when no LLM credential is configured" do
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(nil)

        triaged, status = service.send(:run_triage, [clone_group], model: nil)

        expect(triaged).to eq([clone_group])
        expect(status).to eq("skipped (no LLM credential)")
      end

      it "merges LLM classifications back onto each clone group" do
        response = instance_double(Ai::Llm::Response, content:
          { results: [{ index: 0, category: "extract_candidate", reason: "same logic", action: "extract helper" }] }.to_json)
        client = instance_double(Ai::Llm::Client, complete_structured: response)
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(client)

        triaged, status = service.send(:run_triage, [clone_group], model: "test-model")

        expect(status).to eq("completed (test-model)")
        expect(triaged.first[:triage]).to eq("extract_candidate")
        expect(triaged.first[:triage_reason]).to eq("same logic")
        expect(triaged.first[:suggested_action]).to eq("extract helper")
      end

      it "falls back to untriaged items when a triage batch raises" do
        client = instance_double(Ai::Llm::Client)
        allow(client).to receive(:complete_structured).and_raise(StandardError, "boom")
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(client)
        allow(Rails.logger).to receive(:warn)

        triaged, status = service.send(:run_triage, [clone_group], model: "test-model")

        expect(triaged).to eq([clone_group])
        expect(status).to eq("completed (test-model)")
        expect(Rails.logger).to have_received(:warn).with(/triage batch failed/)
      end
    end

    # C8: the API enforces the schema, so the reply parses as-is. The schema is
    # strict (closed objects, every property required) for Anthropic
    # output_config.format and OpenAI strict json_schema.
    describe "structured output" do
      it "requests the triage schema and sends no JSON-forcing prose" do
        response = instance_double(Ai::Llm::Response, content: { results: [] }.to_json)
        client = instance_double(Ai::Llm::Client)
        allow(client).to receive(:complete_structured).and_return(response)
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(client)

        service.send(:run_triage, [ clone_group ], model: "test-model")

        expect(client).to have_received(:complete_structured) do |messages:, schema:, **|
          expect(schema).to eq(described_class::TRIAGE_SCHEMA)
          expect(messages.first[:content]).not_to match(/ONLY a JSON object|markdown fences/)
        end
        item = described_class::TRIAGE_SCHEMA.dig(:schema, :properties, :results, :items)
        expect(item[:additionalProperties]).to be(false)
        expect(item[:required]).to match_array(item[:properties].keys.map(&:to_s))
      end
    end
  end
end
