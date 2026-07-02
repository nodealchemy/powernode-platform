# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Codebase::DeadCodeAnalysisService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, base_path: "/nonexistent") }

  let(:candidate) do
    { language: "ruby", kind: "method", symbol: "unused_helper", file: "server/app/models/foo.rb", line: 10 }
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
      it "returns candidates untriaged when no LLM credential is configured" do
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(nil)

        triaged, status = service.send(:run_triage, [candidate], model: nil)

        expect(triaged).to eq([candidate])
        expect(status).to eq("skipped (no LLM credential)")
      end

      it "merges LLM classifications back onto each candidate" do
        response = instance_double(Ai::Llm::Response, content:
          { results: [{ index: 0, category: "real_dead", reason: "no refs" }] }.to_json)
        client = instance_double(Ai::Llm::Client, complete: response)
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(client)

        triaged, status = service.send(:run_triage, [candidate], model: "test-model")

        expect(status).to eq("completed (test-model)")
        expect(triaged.first[:triage]).to eq("real_dead")
        expect(triaged.first[:triage_reason]).to eq("no refs")
      end

      it "falls back to untriaged candidates when a triage batch raises" do
        client = instance_double(Ai::Llm::Client)
        allow(client).to receive(:complete).and_raise(StandardError, "boom")
        allow(Ai::Llm::Client).to receive(:for_account).with(account).and_return(client)
        allow(Rails.logger).to receive(:warn)

        triaged, status = service.send(:run_triage, [candidate], model: "test-model")

        expect(triaged).to eq([candidate])
        expect(status).to eq("completed (test-model)")
        expect(Rails.logger).to have_received(:warn).with(/triage batch failed/)
      end
    end

    describe "#extract_results" do
      it "parses fenced JSON with surrounding prose" do
        content = "Sure:\n```json\n{\"results\":[{\"index\":0,\"category\":\"real_dead\"}]}\n```"
        expect(service.send(:extract_results, content)).to eq([{ "index" => 0, "category" => "real_dead" }])
      end

      it "returns [] for blank or non-JSON content" do
        expect(service.send(:extract_results, nil)).to eq([])
        expect(service.send(:extract_results, "no json here")).to eq([])
      end
    end
  end
end
