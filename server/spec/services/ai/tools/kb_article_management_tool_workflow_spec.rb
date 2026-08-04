# frozen_string_literal: true

require "rails_helper"

# Agent-driven article changes must leave the same audit trail as API-driven
# ones. This path is the harder half: BaseTool#user is nil for both agent and
# instance principals, and knowledge_base_workflows.user_id is NOT NULL, so the
# row has to name a principal without inventing one silently.
RSpec.describe Ai::Tools::KbArticleManagementTool, "workflow audit trail" do
  let(:account) { create(:account) }
  let(:category) { create(:kb_category) }
  let(:agent) { create(:ai_agent, account: account) }
  let!(:admin) { create(:user, account: account, email: "admin@powernode.org") }

  subject(:tool) { described_class.new(account: account, agent: agent) }

  # Crossing the `published` boundary needs kb.publish (IMP-3682545ccbe9), so
  # the two examples below that assert what a PUBLISHING transition records have
  # to be made by a principal allowed to make one. What they assert — the action
  # vocabulary a publish lands in the trail — is unchanged; only the caller is.
  let(:publisher) { create(:user, account: account, permissions: [ "kb.publish" ]) }
  let(:publishing_tool) { described_class.new(account: account, agent: agent, user: publisher) }

  def latest_workflow
    KnowledgeBase::Workflow.recent.first
  end

  describe "#create_article" do
    it "records a create row attributed to the agent that made the call" do
      expect {
        tool.send(:create_article, title: "Agent Article", content: "Body", category_slug: category.slug)
      }.to change(KnowledgeBase::Workflow, :count).by(1)

      expect(latest_workflow).to have_attributes(action: "create", from_status: nil, to_status: "draft")
      expect(latest_workflow.metadata).to include(
        "source" => "ai_tool",
        "tool" => "kb_article_management",
        "agent_id" => agent.id,
        "agent_name" => agent.name
      )
    end

    it "records the landing status when the caller creates an already-published article" do
      publishing_tool.send(:create_article, title: "Live", content: "Body", category_slug: category.slug, status: "published")

      expect(latest_workflow).to have_attributes(action: "create", to_status: "published")
    end

    it "writes no article and no row when the create is invalid" do
      expect(tool.send(:create_article, title: "", content: "", category_slug: category.slug))
        .to include(success: false)

      expect(KnowledgeBase::Workflow.count).to eq(0)
      expect(KnowledgeBase::Article.count).to eq(0)
    end
  end

  describe "#update_article" do
    let!(:article) { create(:kb_article, category: category, account: account, status: "draft") }

    it "records an edit naming the fields that changed" do
      tool.send(:update_article, article_id: article.id, title: "Agent Retitled")

      expect(latest_workflow).to have_attributes(
        action: "edit", from_status: "draft", to_status: "draft", comment: "Updated: title"
      )
    end

    it "records a publish when the caller moves the status" do
      publishing_tool.send(:update_article, article_id: article.id, status: "published")

      expect(latest_workflow).to have_attributes(
        action: "publish", from_status: "draft", to_status: "published"
      )
    end

    it "rolls the article change back when the row cannot be written" do
      allow(KnowledgeBase::Workflow).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(KnowledgeBase::Workflow.new))

      expect(tool.send(:update_article, article_id: article.id, title: "Never Lands"))
        .to include(success: false)

      expect(article.reload.title).not_to eq("Never Lands")
      expect(KnowledgeBase::Workflow.count).to eq(0)
    end
  end

  describe "naming a principal when there is no acting user" do
    it "uses the acting user when the tool was given one" do
      caller_user = create(:user, account: account)
      with_user = described_class.new(account: account, agent: agent, user: caller_user)
      article = create(:kb_article, category: category, account: account)

      with_user.send(:update_article, article_id: article.id, title: "By A Person")

      expect(latest_workflow.user_id).to eq(caller_user.id)
      expect(latest_workflow.metadata["attribution"]).to eq("acting_user")
    end

    it "falls back to the article's author for an agent call" do
      author = create(:user, account: account)
      article = create(:kb_article, category: category, account: account, author: author)

      tool.send(:update_article, article_id: article.id, title: "By An Agent")

      expect(latest_workflow.user_id).to eq(author.id)
      expect(latest_workflow.metadata["attribution"]).to eq("article_author")
    end

    # The seeded GLOBAL articles are deliberately authorless (db/seeds/kb/*.rb
    # sets author_id = nil on 53 of them), so this is the common shape in
    # production, not an edge case.
    it "falls back to the admin for an authorless global article, and says so" do
      article = create(:kb_article, category: category, account: nil, author: nil)

      tool.send(:update_article, article_id: article.id, title: "Global Edit")

      expect(latest_workflow.user_id).to eq(admin.id)
      expect(latest_workflow.metadata["attribution"]).to eq("fallback_admin")
      expect(latest_workflow.metadata["agent_id"]).to eq(agent.id)
    end
  end
end
