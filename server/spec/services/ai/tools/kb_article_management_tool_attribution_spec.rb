# frozen_string_literal: true

require "rails_helper"

# Attribution must not cross a tenant boundary.
#
# The tool resolved the identity it writes as KnowledgeBase::Article#author —
# and, through #workflow_principal, as the user on the KnowledgeBase::Workflow
# audit row — with `::User.find_by(email: "admin@powernode.org") || ::User.first`.
# Neither clause is scoped to `account`, in a method two lines above
# #find_article, which scopes correctly.
#
# The consequence is not a tidiness one. Since IMP-78ae82f1deda,
# KnowledgeBase::Workflow IS the article-transition audit trail, and its user_id
# is the column a reader trusts to answer "who moved this article". A row
# asserting that account A's user acted on a transition made in account B is
# worse than no row at all: it is a false statement in the record whose entire
# purpose is attribution.
#
# It is reachable on the ordinary path, not an edge case: BaseTool#user is nil
# for BOTH agent and instance principals, and the 53 seeded GLOBAL articles are
# deliberately authorless (db/seeds/kb/*.rb), so the fallback chain runs
# whenever an agent touches one.
RSpec.describe Ai::Tools::KbArticleManagementTool, "cross-account attribution" do
  # Creation ORDER is load-bearing in this file: `::User.first` carries no ORDER
  # BY, so it resolves to the earliest-inserted row. Account A's users are
  # therefore always created first, which is what makes an unscoped fallback
  # reach across the tenant boundary rather than merely being lucky.
  let!(:account_a) { create(:account) }
  let!(:account_b) { create(:account) }

  let(:category) { create(:kb_category) }
  let(:agent_b) { create(:ai_agent, account: account_b) }

  # No user: the agent principal the fallback chain exists for.
  subject(:tool_b) { described_class.new(account: account_b, agent: agent_b) }

  def latest_workflow
    KnowledgeBase::Workflow.recent.first
  end

  def account_a_user_ids
    account_a.users.pluck(:id)
  end

  context "when the hardcoded reference address exists in ANOTHER account" do
    # The literal the tool looked up. A self-hosted core-mode install need not
    # have it at all; a multi-tenant one can have it in a tenant that is not the
    # caller's. Both are answered by never naming an address in source.
    let!(:foreign_admin) { create(:user, account: account_a, email: "admin@powernode.org") }
    let!(:own_owner) { create(:user, account: account_b) }

    it "does not author account B's article with account A's admin" do
      result = tool_b.send(:create_article, title: "B Article", content: "Body", category_slug: category.slug)

      expect(result).to include(success: true)
      author = KnowledgeBase::Article.find(result[:article_id]).author
      expect(author.id).not_to eq(foreign_admin.id)
      expect(author.account_id).to eq(account_b.id)
    end

    it "does not name account A's admin on the audit row for account B's create" do
      tool_b.send(:create_article, title: "B Article", content: "Body", category_slug: category.slug)

      expect(latest_workflow.user_id).not_to eq(foreign_admin.id)
      expect(latest_workflow.user.account_id).to eq(account_b.id)
      expect(latest_workflow.metadata).to include("agent_id" => agent_b.id)
    end

    # Defensive: every shipped caller builds the tool with an account and a user
    # from the same context (ConciergeRouter, SkillRecipeRunner), so this is the
    # guard rather than a live path — but an unpinned guard is one a later
    # refactor drops silently.
    it "ignores an acting user that does not belong to the tool's account" do
      article = create(:kb_article, category: category, account: account_b, author: nil, status: "draft")

      described_class.new(account: account_b, agent: agent_b, user: foreign_admin)
        .send(:update_article, article_id: article.id, title: "By A Foreign User")

      expect(latest_workflow.user_id).not_to eq(foreign_admin.id)
      expect(latest_workflow.user.account_id).to eq(account_b.id)
    end

    it "resolves account B's own principal and says the row is a fallback" do
      article = create(:kb_article, category: category, account: account_b, author: nil, status: "draft")

      tool_b.send(:update_article, article_id: article.id, title: "Edited By An Agent")

      expect(latest_workflow.user_id).to eq(own_owner.id)
      expect(latest_workflow.metadata["attribution"]).to eq("fallback_account_principal")
    end
  end

  context "when the reference address exists in NO account" do
    # The `|| ::User.first` clause: a global, unordered pick that lands on
    # whichever user happens to be first in the table — the normal shape for any
    # install that is not the reference one.
    let!(:foreign_user) { create(:user, account: account_a) }
    let!(:own_owner) { create(:user, account: account_b) }

    it "authors account B's article inside account B" do
      result = tool_b.send(:create_article, title: "No Admin Here", content: "Body", category_slug: category.slug)

      expect(result).to include(success: true)
      expect(KnowledgeBase::Article.find(result[:article_id]).author.account_id).to eq(account_b.id)
    end

    it "names an account B principal on the audit row" do
      tool_b.send(:create_article, title: "No Admin Here", content: "Body", category_slug: category.slug)

      expect(account_a_user_ids).not_to include(latest_workflow.user_id)
      expect(latest_workflow.user.account_id).to eq(account_b.id)
    end

    # The other half of the same leak: the chain's `article.author` link is
    # unscoped too. A GLOBAL article (account_id nil) is visible to every tenant
    # through for_account, so its author is routinely someone else's user.
    it "does not name a GLOBAL article's foreign author as account B's actor" do
      global_article = create(:kb_article, category: category, account: nil,
                                           author: foreign_user, status: "draft")

      tool_b.send(:update_article, article_id: global_article.id, title: "Edited From B")

      expect(latest_workflow.user_id).not_to eq(foreign_user.id)
      expect(account_a_user_ids).not_to include(latest_workflow.user_id)
      expect(latest_workflow.user.account_id).to eq(account_b.id)
    end
  end

  # The in-account links must keep working: scoping is meant to remove foreign
  # identities, not to stop naming the right one.
  context "when a legitimate in-account identity exists" do
    let!(:foreign_admin) { create(:user, account: account_a, email: "admin@powernode.org") }
    let!(:own_owner) { create(:user, account: account_b) }

    it "prefers the acting user" do
      acting = create(:user, account: account_b)
      article = create(:kb_article, category: category, account: account_b, author: nil, status: "draft")

      described_class.new(account: account_b, agent: agent_b, user: acting)
        .send(:update_article, article_id: article.id, title: "By A Person In B")

      expect(latest_workflow.user_id).to eq(acting.id)
      expect(latest_workflow.metadata["attribution"]).to eq("acting_user")
    end

    it "prefers the article's author when that author is in the account" do
      author = create(:user, account: account_b)
      article = create(:kb_article, category: category, account: account_b, author: author, status: "draft")

      tool_b.send(:update_article, article_id: article.id, title: "By An Agent")

      expect(latest_workflow.user_id).to eq(author.id)
      expect(latest_workflow.metadata["attribution"]).to eq("article_author")
    end
  end

  # An account with no users at all cannot honestly name anyone. Reaching
  # outside it for a body to attribute the row to is the defect; refusing is the
  # only other option while knowledge_base_workflows.user_id is NOT NULL.
  #
  # The tool here carries NO agent on purpose — this is the instance-principal
  # shape (mTLS node cert, no User and no Agent), and it is also the only way to
  # reach a genuinely userless account in specs: the :ai_agent factory
  # materialises `creator { association :user, account: account }`, which would
  # quietly populate the account this context is about.
  context "when the account has no user the row could name" do
    let!(:foreign_admin) { create(:user, account: account_a, email: "admin@powernode.org") }

    subject(:userless_tool) { described_class.new(account: account_b) }

    it "refuses the create instead of attributing it to another account" do
      result = userless_tool.send(:create_article, title: "Unattributable", content: "Body",
                                                   category_slug: category.slug)

      expect(result).to include(success: false)
      # Pinned so the example cannot pass for an unrelated validation failure.
      expect(result[:error]).to include("cannot be resolved within this account")
      expect(KnowledgeBase::Article.where(title: "Unattributable")).to be_empty
      expect(KnowledgeBase::Workflow.count).to eq(0)
    end

    it "refuses the update, leaving the article untouched" do
      article = create(:kb_article, category: category, account: account_b, author: nil,
                                    status: "draft", title: "Original")

      result = userless_tool.send(:update_article, article_id: article.id, title: "Never Lands")

      expect(result).to include(success: false)
      expect(result[:error]).to include("cannot be resolved within this account")
      expect(article.reload.title).to eq("Original")
      expect(KnowledgeBase::Workflow.count).to eq(0)
    end
  end
end
