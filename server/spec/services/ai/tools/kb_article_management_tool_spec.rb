# frozen_string_literal: true

require "rails_helper"

# Tenant isolation for article writes. Reads stay override-aware (global +
# own, see kb_article_management_tool_global_spec.rb), but writes must not use
# that reach: an article this tool creates belongs to the caller's account, and
# a GLOBAL article (account_id nil) is platform content that only a
# system.admin holder may change.
RSpec.describe Ai::Tools::KbArticleManagementTool, "tenant isolation" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:category) { create(:kb_category) }
  let(:agent) { create(:ai_agent, account: account) }

  # Created first, so the owner-role bootstrap lands here and not on the
  # deliberately-scoped users below.
  let!(:owner) { create(:user, account: account) }

  # Holds every tenant-level KB permission, including admin.kb.manage, which
  # the account owner role also carries. None of them reaches global content.
  let(:kb_admin) do
    create(:user, account: account,
                  permissions: [ "kb.manage", "kb.update", "kb.publish", "admin.kb.manage" ])
  end
  let(:platform_admin) { create(:user, account: account, permissions: [ "system.admin" ]) }

  let(:agent_tool) { described_class.new(account: account, agent: agent) }
  let(:kb_admin_tool) { described_class.new(account: account, agent: agent, user: kb_admin) }
  let(:platform_admin_tool) { described_class.new(account: account, agent: agent, user: platform_admin) }

  describe "#create_article" do
    it "owns the new article by the caller's account, so other tenants cannot see it" do
      result = agent_tool.send(:create_article, title: "Tenant Note", content: "Body",
                                                category_slug: category.slug)

      expect(result).to include(success: true)
      article = KnowledgeBase::Article.find(result[:article_id])
      expect(article.account_id).to eq(account.id)
      expect(article).not_to be_global

      other_tool = described_class.new(account: other_account)
      slugs = other_tool.send(:list_articles, {})[:articles].map { |a| a[:slug] }
      expect(slugs).not_to include(article.slug)
    end
  end

  describe "#update_article on a GLOBAL article" do
    let!(:global_article) do
      create(:kb_article, category: category, account: nil, author: nil,
                          status: "draft", title: "Platform Article")
    end

    it "refuses an agent call and changes nothing" do
      result = nil

      expect {
        result = agent_tool.send(:update_article, article_id: global_article.id, title: "Hijacked")
      }.not_to change(KnowledgeBase::Workflow, :count)

      expect(result).to include(success: false)
      expect(result[:error]).to include("system.admin")
      expect(global_article.reload.title).to eq("Platform Article")
    end

    it "refuses a user holding every tenant-level KB permission" do
      result = kb_admin_tool.send(:update_article, article_id: global_article.id, title: "Hijacked")

      expect(result).to include(success: false)
      expect(result[:error]).to include("system.admin")
      expect(global_article.reload.title).to eq("Platform Article")
    end

    it "allows a system.admin holder" do
      result = platform_admin_tool.send(:update_article, article_id: global_article.id, title: "Platform Fix")

      expect(result).to include(success: true)
      expect(global_article.reload.title).to eq("Platform Fix")
    end

    it "still lets any caller read it" do
      result = agent_tool.send(:get_article, article_id: global_article.id)

      expect(result).to include(success: true)
      expect(result[:article][:id]).to eq(global_article.id)
    end
  end

  describe "#update_article on the account's own article" do
    it "needs no platform permission" do
      article = create(:kb_article, category: category, account: account, status: "draft")

      result = agent_tool.send(:update_article, article_id: article.id, title: "Own Edit")

      expect(result).to include(success: true)
      expect(article.reload.title).to eq("Own Edit")
    end
  end
end
