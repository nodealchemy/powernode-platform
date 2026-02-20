# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::NativeResourceProvider, type: :model do
  let(:account) { create(:account) }
  let(:provider) { described_class.new(account: account) }

  # ===========================================================================
  # #list_resources
  # ===========================================================================
  describe "#list_resources" do
    it "returns empty resources when no data exists" do
      result = provider.list_resources
      expect(result[:resources]).to be_an(Array)
      expect(result[:resources]).to be_empty
    end

    context "with KB articles" do
      let(:category) { create(:kb_category) }
      let!(:article) { create(:kb_article, :published, category: category) }

      it "includes published KB articles" do
        result = provider.list_resources
        uris = result[:resources].map { |r| r[:uri] }
        expect(uris).to include("powernode://kb/articles/#{article.slug}")
      end

      it "excludes draft KB articles" do
        create(:kb_article, :draft, category: category)
        result = provider.list_resources
        published_uris = result[:resources].select { |r| r[:uri].start_with?("powernode://kb/articles/") }
        expect(published_uris.length).to eq(1)
      end
    end

    context "with AI agents" do
      let!(:agent) { create(:ai_agent, account: account, status: "active") }

      it "includes active AI agents" do
        result = provider.list_resources
        uris = result[:resources].map { |r| r[:uri] }
        expect(uris).to include("powernode://ai/agents/#{agent.id}")
      end

      it "excludes inactive AI agents" do
        create(:ai_agent, :inactive, account: account)
        result = provider.list_resources
        agent_resources = result[:resources].select { |r| r[:uri].start_with?("powernode://ai/agents/") }
        expect(agent_resources.length).to eq(1)
      end
    end

    context "with AI workflows" do
      let!(:workflow) { create(:ai_workflow, :active, account: account) }

      it "includes active AI workflows" do
        result = provider.list_resources
        uris = result[:resources].map { |r| r[:uri] }
        expect(uris).to include("powernode://ai/workflows/#{workflow.id}")
      end

      it "excludes non-active AI workflows" do
        create(:ai_workflow, account: account, status: "draft")
        result = provider.list_resources
        workflow_resources = result[:resources].select { |r| r[:uri].start_with?("powernode://ai/workflows/") }
        expect(workflow_resources.length).to eq(1)
      end
    end

    context "with prompt templates" do
      let!(:template) { create(:shared_prompt_template, account: account) }

      it "includes active prompt templates" do
        result = provider.list_resources
        uris = result[:resources].map { |r| r[:uri] }
        expect(uris).to include("powernode://ai/prompts/#{template.slug}")
      end

      it "excludes inactive prompt templates" do
        create(:shared_prompt_template, :inactive, account: account)
        result = provider.list_resources
        prompt_resources = result[:resources].select { |r| r[:uri].start_with?("powernode://ai/prompts/") }
        expect(prompt_resources.length).to eq(1)
      end
    end

    it "resources have uri, name, description, mimeType" do
      create(:kb_article, :published, category: create(:kb_category))
      result = provider.list_resources
      resource = result[:resources].first

      expect(resource).to include(:uri, :name, :description, :mimeType)
    end

    it "URI format follows powernode://type/identifier pattern" do
      create(:ai_agent, account: account, status: "active")
      result = provider.list_resources
      agent_resource = result[:resources].find { |r| r[:uri].start_with?("powernode://ai/agents/") }

      expect(agent_resource[:uri]).to match(%r{\Apowernode://ai/agents/.+\z})
    end
  end

  # ===========================================================================
  # #read_resource
  # ===========================================================================
  describe "#read_resource" do
    context "KB articles" do
      let(:category) { create(:kb_category) }
      let!(:article) { create(:kb_article, :published, category: category) }

      it "reads KB article by slug URI" do
        result = provider.read_resource(uri: "powernode://kb/articles/#{article.slug}")
        expect(result[:contents]).to be_an(Array)
        expect(result[:contents].first[:text]).to eq(article.content)
      end

      it "returns contents array with uri, mimeType, text" do
        result = provider.read_resource(uri: "powernode://kb/articles/#{article.slug}")
        content = result[:contents].first

        expect(content[:uri]).to eq("powernode://kb/articles/#{article.slug}")
        expect(content[:mimeType]).to eq("text/plain")
        expect(content[:text]).to be_present
      end
    end

    context "AI agents" do
      let!(:agent) { create(:ai_agent, account: account, status: "active") }

      it "reads AI agent by id URI" do
        result = provider.read_resource(uri: "powernode://ai/agents/#{agent.id}")
        content = result[:contents].first

        expect(content[:mimeType]).to eq("application/json")
        parsed = JSON.parse(content[:text])
        expect(parsed["name"]).to eq(agent.name)
        expect(parsed["id"]).to eq(agent.id)
      end
    end

    context "AI workflows" do
      let!(:workflow) { create(:ai_workflow, :active, account: account) }

      it "reads AI workflow by id URI" do
        result = provider.read_resource(uri: "powernode://ai/workflows/#{workflow.id}")
        content = result[:contents].first

        expect(content[:mimeType]).to eq("application/json")
        parsed = JSON.parse(content[:text])
        expect(parsed["name"]).to eq(workflow.name)
        expect(parsed["id"]).to eq(workflow.id)
      end
    end

    context "prompt templates" do
      let!(:template) { create(:shared_prompt_template, account: account) }

      it "reads prompt template by slug URI" do
        result = provider.read_resource(uri: "powernode://ai/prompts/#{template.slug}")
        content = result[:contents].first

        expect(content[:mimeType]).to eq("text/plain")
        expect(content[:text]).to eq(template.content)
      end
    end

    it "raises ArgumentError for unknown URI scheme" do
      expect {
        provider.read_resource(uri: "powernode://unknown/type/thing")
      }.to raise_error(ArgumentError, /Invalid resource URI/)
    end

    it "raises ArgumentError for non-existent resource" do
      expect {
        provider.read_resource(uri: "powernode://kb/articles/does-not-exist")
      }.to raise_error(ArgumentError, /Resource not found/)
    end

    it "raises ArgumentError for invalid URI format" do
      expect {
        provider.read_resource(uri: "not-a-valid-uri")
      }.to raise_error(ArgumentError, /Invalid resource URI/)
    end

    it "raises ArgumentError for nil URI" do
      expect {
        provider.read_resource(uri: nil)
      }.to raise_error(ArgumentError, /Invalid resource URI/)
    end
  end
end
