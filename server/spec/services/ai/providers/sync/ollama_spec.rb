# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Ollama do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :ollama, account: account, api_base_url: "http://localhost:11434") }
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "test-ollama-key-12345" })
  end

  let(:api_response_body) do
    {
      models: [
        {
          name: "llama2:latest",
          size: 3_825_819_519,
          digest: "sha256:abc123",
          modified_at: "2024-01-15T10:30:00Z",
          details: {
            family: "llama",
            parameter_size: "7B",
            quantization_level: "Q4_0",
            format: "gguf"
          }
        },
        {
          name: "codellama:latest",
          size: 3_791_730_688,
          digest: "sha256:def456",
          modified_at: "2024-01-14T08:00:00Z",
          details: {
            family: "llama",
            parameter_size: "7B",
            quantization_level: "Q4_0",
            format: "gguf"
          }
        }
      ]
    }
  end

  describe ".sync_ollama_models" do
    context "with standard endpoint responding successfully" do
      before do
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the standard endpoint" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(2)
      end

      it "formats model names by capitalizing the base name" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        llama = provider.supported_models.find { |m| m["id"] == "llama2:latest" }
        expect(llama["name"]).to eq("Llama2")
      end

      it "preserves the full model id including tag" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        model_ids = provider.supported_models.map { |m| m["id"] }
        expect(model_ids).to include("llama2:latest", "codellama:latest")
      end

      it "includes model size information" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        llama = provider.supported_models.find { |m| m["id"] == "llama2:latest" }
        expect(llama["size_bytes"]).to eq(3_825_819_519)
        expect(llama["description"]).to include("Size:")
      end

      it "includes model details metadata" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        llama = provider.supported_models.find { |m| m["id"] == "llama2:latest" }
        expect(llama["family"]).to eq("llama")
        expect(llama["parameter_size"]).to eq("7B")
        expect(llama["quantization_level"]).to eq("Q4_0")
        expect(llama["format"]).to eq("gguf")
        expect(llama["digest"]).to eq("sha256:abc123")
      end

      it "sets zero cost for local models" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        llama = provider.supported_models.find { |m| m["id"] == "llama2:latest" }
        expect(llama["cost_per_1k_tokens"]).to eq({ "input" => 0, "output" => 0 })
      end
    end

    context "with base_url ending in /api" do
      let(:provider) { create(:ai_provider, :ollama, account: account, api_base_url: "http://localhost:11434/api") }

      before do
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "uses the correct endpoint" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(2)
      end
    end

    context "with standard endpoint failing, fallback to authenticated endpoint" do
      before do
        credential

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 404, body: "Not Found")

        stub_request(:get, "http://localhost:11434/ollama/api/tags")
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "falls back to the Open WebUI endpoint" do
        Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(2)
      end
    end

    context "with HTML response (not JSON)" do
      before do
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: "<html><body>Login</body></html>")

        stub_request(:get, "http://localhost:11434/ollama/api/tags")
          .to_return(status: 200, body: "<html><body>Login</body></html>")

        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: "<html><body>Login</body></html>")
      end

      it "rejects HTML responses and calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        }.to raise_error(StandardError, /Could not connect to Ollama API/)
      end
    end

    context "when all endpoints are unreachable" do
      before do
        stub_request(:get, /localhost:11434/).to_raise(HTTP::ConnectionError.new("Connection refused"))
      end

      it "calls handle_sync_failure with connection error" do
        expect {
          Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        }.to raise_error(StandardError, /Could not connect to Ollama API/)
      end
    end

    context "with empty models list" do
      before do
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200, body: { models: [] }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "does not raise an error" do
        expect {
          Ai::ProviderManagementService.send(:sync_ollama_models, provider)
        }.not_to raise_error
      end
    end
  end
end
