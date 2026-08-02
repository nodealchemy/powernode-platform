# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CodeDiscoveryTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("code_discovery")
      expect(defn[:parameters]).to include(:action, :repository_id, :query)
    end
  end

  # Live symptom on the fleet control plane 2026-08-02: with the repository
  # correctly registered, semantic_search still failed with "Repository
  # 'powernode-platform' has no local_path in metadata". It queries
  # knowledge-graph rows and never touches the filesystem — it discards the
  # base_path it was forcing to resolve — so requiring a working copy to exist
  # on the server made pure vector search impossible on any node not hosting a
  # checkout.
  describe "#execute action=semantic_search without a repository local_path" do
    let!(:repository) do
      create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform", metadata: {})
    end

    it "does not demand a filesystem path it never uses" do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(Array.new(1536) { 0.01 })

      result = tool.execute(params: {
        action: "semantic_search", query: "hostname envelope",
        repository_id: "nodealchemy/powernode-platform"
      })

      expect(result[:error].to_s).not_to include("local_path")
      expect(result[:success]).to be true
    end
  end

  describe "#execute action=semantic_search" do
    it "requires a query" do
      result = tool.execute(params: { action: "semantic_search", repository_id: "whatever" })
      expect(result).to eq({ success: false, error: "query is required" })
    end

    it "requires a repository_id" do
      result = tool.execute(params: { action: "semantic_search", query: "find the thing" })
      expect(result).to eq({ success: false, error: "repository_id is required" })
    end

    context "when repository_id does not match any repository for the account" do
      it "surfaces a self-correcting error listing the account's available repositories" do
        create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform")
        create(:git_repository, account: account, full_name: "nodealchemy/other-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).to include("repository not found: powernode")
        expect(result[:error]).to include("nodealchemy/powernode-platform")
        expect(result[:error]).to include("nodealchemy/other-repo")
      end

      it "never leaks another account's repositories" do
        other_account = create(:account)
        create(:git_repository, account: other_account, full_name: "other/secret-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).not_to include("secret-repo")
        expect(result[:error]).to include("no git repositories")
      end
    end
  end
end
