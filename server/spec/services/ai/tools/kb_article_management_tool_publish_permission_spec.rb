# frozen_string_literal: true

require "rails_helper"

# Publishing an article is a permissioned act on the human path:
# Api::V1::Kb::ArticlesController gates #publish/#unpublish behind kb.publish,
# deliberately separating them from ordinary editing. It matters because
# publishing is what makes content visible to OTHER agents —
# Mcp::NativeResourceProvider serves `.published` articles as MCP resources by
# slug (native_resource_provider.rb:88, :105, :176). A tool that treats status
# as an ordinary attribute therefore lets an agent promote its own writing into
# the corpus the rest of the fleet reads as context.
#
# The gate is on crossing the `published` boundary in EITHER direction, matching
# the controller pairing publish with unpublish. Transitions that never touch
# `published` (draft -> review, draft -> archived) stay open, so an agent's safe
# move — parking work in `review` for a human — is not collateral damage.
RSpec.describe Ai::Tools::KbArticleManagementTool, "publication permission" do
  let(:account) { create(:account) }
  let(:category) { create(:kb_category) }
  let(:agent) { create(:ai_agent, account: account) }

  # Created first, so the owner-role bootstrap lands here and not on the
  # deliberately-scoped users below. Also the tool's authorless fallback author.
  let!(:admin) { create(:user, account: account, email: "admin@powernode.org") }

  # kb.manage is the tool's own REQUIRED_PERMISSION, so this user can reach
  # every line of it. It is the principal the defect was about.
  let(:manager) { create(:user, account: account, permissions: [ "kb.manage" ]) }
  let(:publisher) { create(:user, account: account, permissions: [ "kb.manage", "kb.publish" ]) }

  # An agent call carries NO user at all (BaseTool#user is nil for agent and
  # instance principals alike), which is how the bypass was reachable without
  # holding any permission directly.
  subject(:agent_tool) { described_class.new(account: account, agent: agent) }

  let(:manager_tool) { described_class.new(account: account, agent: agent, user: manager) }
  let(:publisher_tool) { described_class.new(account: account, agent: agent, user: publisher) }

  def publish_rows
    KnowledgeBase::Workflow.by_action("publish")
  end

  describe "#create_article landing straight in published" do
    it "refuses an agent call, leaving no article and no workflow row" do
      result = nil

      expect {
        result = agent_tool.send(:create_article, title: "Self Promoted", content: "Body",
                                                  category_slug: category.slug, status: "published")
      }.not_to change(KnowledgeBase::Workflow, :count)

      expect(result).to include(success: false)
      expect(result[:error]).to include("kb.publish")
      expect(KnowledgeBase::Article.where(title: "Self Promoted")).to be_empty
    end

    it "refuses a kb.manage-only user, so the tool's own permission is not self-satisfying" do
      result = manager_tool.send(:create_article, title: "Manager Promoted", content: "Body",
                                                  category_slug: category.slug, status: "published")

      expect(result).to include(success: false)
      expect(result[:error]).to include("kb.publish")
      expect(KnowledgeBase::Article.where(title: "Manager Promoted")).to be_empty
      expect(publish_rows).to be_empty
    end

    it "allows a caller holding kb.publish and records the landing status" do
      result = publisher_tool.send(:create_article, title: "Properly Published", content: "Body",
                                                     category_slug: category.slug, status: "published")

      expect(result).to include(success: true)
      expect(KnowledgeBase::Article.find(result[:article_id]).status).to eq("published")
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(action: "create", to_status: "published")
    end

    it "still lets an agent create a draft" do
      result = agent_tool.send(:create_article, title: "Honest Draft", content: "Body",
                                                 category_slug: category.slug)

      expect(result).to include(success: true)
      expect(KnowledgeBase::Article.find(result[:article_id]).status).to eq("draft")
    end
  end

  describe "#update_article moving an article INTO published" do
    let!(:article) { create(:kb_article, category: category, account: account, status: "draft") }

    it "refuses an agent call, leaving the status and the trail untouched" do
      result = nil

      expect {
        result = agent_tool.send(:update_article, article_id: article.id, status: "published")
      }.not_to change(KnowledgeBase::Workflow, :count)

      expect(result).to include(success: false)
      expect(result[:error]).to include("kb.publish")
      expect(article.reload.status).to eq("draft")
      expect(publish_rows).to be_empty
    end

    it "refuses even when the publish rides along with a legitimate edit, discarding both" do
      result = agent_tool.send(:update_article, article_id: article.id,
                                                 title: "Smuggled", status: "published")

      expect(result).to include(success: false)
      expect(article.reload).to have_attributes(status: "draft")
      expect(article.title).not_to eq("Smuggled")
      expect(KnowledgeBase::Workflow.count).to eq(0)
    end

    it "allows a caller holding kb.publish and records the publish" do
      publisher_tool.send(:update_article, article_id: article.id, status: "published")

      expect(article.reload.status).to eq("published")
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(
        action: "publish", from_status: "draft", to_status: "published"
      )
    end
  end

  describe "#update_article moving an article OUT of published" do
    let!(:article) { create(:kb_article, :published, category: category, account: account) }

    it "refuses an agent unpublish, so an agent cannot pull an article the fleet reads" do
      result = agent_tool.send(:update_article, article_id: article.id, status: "draft")

      expect(result).to include(success: false)
      expect(result[:error]).to include("kb.publish")
      expect(article.reload.status).to eq("published")
      expect(KnowledgeBase::Workflow.count).to eq(0)
    end

    it "refuses an agent archiving a published article — that is an unpublish by another name" do
      result = agent_tool.send(:update_article, article_id: article.id, status: "archived")

      expect(result).to include(success: false)
      expect(article.reload.status).to eq("published")
      expect(KnowledgeBase::Workflow.by_action("archive")).to be_empty
    end

    it "allows a caller holding kb.publish to unpublish" do
      publisher_tool.send(:update_article, article_id: article.id, status: "draft")

      expect(article.reload.status).to eq("draft")
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(
        action: "unpublish", from_status: "published", to_status: "draft"
      )
    end

    it "leaves an ordinary edit of a published article alone" do
      result = agent_tool.send(:update_article, article_id: article.id, title: "Typo Fixed")

      expect(result).to include(success: true)
      expect(article.reload.title).to eq("Typo Fixed")
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(action: "edit", to_status: "published")
    end

    it "leaves a no-op restatement of the current status alone" do
      result = agent_tool.send(:update_article, article_id: article.id, status: "published")

      expect(result).to include(success: true)
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(action: "edit")
    end
  end

  describe "transitions that never touch published" do
    let!(:article) { create(:kb_article, category: category, account: account, status: "draft") }

    it "lets an agent park a draft in review" do
      expect(agent_tool.send(:update_article, article_id: article.id, status: "review"))
        .to include(success: true)
      expect(article.reload.status).to eq("review")
    end

    it "lets an agent archive a draft" do
      expect(agent_tool.send(:update_article, article_id: article.id, status: "archived"))
        .to include(success: true)
      expect(article.reload.status).to eq("archived")
    end
  end

  describe "non-user principals that are authorized EXPLICITLY" do
    let!(:article) { create(:kb_article, category: category, account: account, status: "draft") }

    it "allows an in-process internal caller" do
      internal_tool = described_class.new(account: account, agent: agent, internal: true)

      expect(internal_tool.send(:update_article, article_id: article.id, status: "published"))
        .to include(success: true)
      expect(article.reload.status).to eq("published")
    end

    it "allows an instance principal that already cleared the per-tool grant gate" do
      instance_tool = described_class.new(account: account)
      instance_tool.instance_authorized = true

      expect(instance_tool.send(:update_article, article_id: article.id, status: "published"))
        .to include(success: true)
      expect(article.reload.status).to eq("published")
    end
  end
end
