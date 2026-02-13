# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::ProjectInitTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("create_gitea_repository")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:repo_name, :description)
    end

    it "marks repo_name as required" do
      expect(described_class.definition[:parameters][:repo_name][:required]).to be true
    end

    it "marks description as optional" do
      expect(described_class.definition[:parameters][:description][:required]).to be false
    end
  end

  describe ".permitted?" do
    it "requires ai.workflows.create permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.workflows.create")
    end
  end

  describe "#execute" do
    let(:init_service) { instance_double(Ai::ProjectInitializationService) }

    before do
      allow(Ai::ProjectInitializationService).to receive(:new).and_return(init_service)
    end

    it "delegates to ProjectInitializationService" do
      allow(init_service).to receive(:call).and_return({ success: true, repo_url: "https://git.example.com/test-repo" })

      result = tool.execute(params: { repo_name: "test-repo", description: "A test repo" })
      expect(result[:success]).to be true

      expect(Ai::ProjectInitializationService).to have_received(:new).with(
        account: account,
        repo_name: "test-repo",
        description: "A test repo"
      )
    end

    it "passes nil description when not provided" do
      allow(init_service).to receive(:call).and_return({ success: true })

      tool.execute(params: { repo_name: "my-repo" })
      expect(Ai::ProjectInitializationService).to have_received(:new).with(
        account: account,
        repo_name: "my-repo",
        description: nil
      )
    end

    it "propagates service errors" do
      allow(init_service).to receive(:call).and_raise(StandardError, "Gitea API failed")

      expect { tool.execute(params: { repo_name: "fail-repo" }) }.to raise_error(StandardError, "Gitea API failed")
    end

    context "parameter validation" do
      it "raises ArgumentError when repo_name is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: repo_name/)
      end
    end
  end
end
