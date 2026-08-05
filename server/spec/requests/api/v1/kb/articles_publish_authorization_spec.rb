# frozen_string_literal: true

require "rails_helper"

# IMP-e32f500cdd88 — the publish bypass on the HUMAN path, and the audit hole
# beside it. Two halves of one defect in the same ~27 lines.
#
# (1) PERMISSION. #publish/#unpublish are gated by authorize_kb_publish
#     (kb.publish or kb.manage). But article_params and bulk_update_params BOTH
#     permit :status, and #update/#bulk_update are gated only by
#     authorize_kb_edit (kb.update or kb.manage). So a principal holding only
#     kb.update could publish by writing the attribute directly, never touching
#     the gated endpoints — the same bypass IMP-3682545ccbe9 (7f9123e44) closed
#     on the agent path.
#
# (2) AUDIT. #update records a KnowledgeBase::Workflow transition;
#     #bulk_update recorded none. Since IMP-78ae82f1deda that table IS the
#     answer to "who moved this article", so a bulk status move left the
#     question unanswerable.
#
# The gated set mirrors the agent path exactly (KbArticleManagementTool
# #crosses_publication_boundary?): both directions across `published` only.
# draft -> review, review -> draft and draft -> archived change nobody's
# visibility and stay open, so the human path does not become stricter than the
# agent path it mirrors.
RSpec.describe "Api::V1::Kb::Articles publish authorization", type: :request do
  let(:account) { create(:account) }

  # kb.update only — can edit, must not be able to publish. The principal this
  # whole spec is about.
  let(:editor) { create(:user, account: account, permissions: %w[kb.update]) }
  # kb.update + kb.publish — the legitimate publisher on the human path.
  let(:publisher) { create(:user, account: account, permissions: %w[kb.update kb.publish]) }
  # kb.update + kb.manage — can_publish_kb? accepts kb.manage, and #publish/
  # #unpublish already honour it. Pinned so this fix does not silently narrow
  # the existing human-path definition of publish authorization.
  let(:manager) { create(:user, account: account, permissions: %w[kb.update kb.manage]) }

  let(:editor_headers) { auth_headers_for(editor) }
  let(:publisher_headers) { auth_headers_for(publisher) }
  let(:manager_headers) { auth_headers_for(manager) }

  let!(:category) do
    KnowledgeBase::Category.create!(name: "Cat", slug: "cat", is_public: true)
  end

  def article!(status:, slug:, author: editor)
    KnowledgeBase::Article.create!(
      title: "A #{slug}", slug: slug, content: "Body", status: status,
      category: category, author: author, account_id: account.id,
      published_at: (status == "published" ? Time.current : nil)
    )
  end

  def workflows_for(article)
    KnowledgeBase::Workflow.for_article(article.id).chronological
  end

  # ── HALF 1: kb.update alone must not publish ─────────────────────────────
  describe "PATCH /api/v1/kb/articles/:id" do
    context "when the caller holds only kb.update" do
      it "refuses to publish a draft" do
        draft = article!(status: "draft", slug: "d1")

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { status: "published" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        # Refused before the transaction opens: no article change, no audit row.
        expect(draft.reload.status).to eq("draft")
        expect(workflows_for(draft)).to be_empty
      end

      it "refuses to unpublish a published article" do
        live = article!(status: "published", slug: "p1")

        patch "/api/v1/kb/articles/#{live.id}",
              params: { article: { status: "draft" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(live.reload.status).to eq("published")
        expect(workflows_for(live)).to be_empty
      end

      it "refuses to archive a published article (an unpublish by another name)" do
        live = article!(status: "published", slug: "p2")

        patch "/api/v1/kb/articles/#{live.id}",
              params: { article: { status: "archived" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(live.reload.status).to eq("published")
      end

      it "refuses a publish smuggled alongside an ordinary field edit" do
        draft = article!(status: "draft", slug: "d2")

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { title: "New Title", status: "published" } },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        # The whole request is refused — the title edit must not land either,
        # or the refusal would be a partial write.
        expect(draft.reload.title).to eq("A d2")
        expect(draft.status).to eq("draft")
      end

      # Must NOT over-block: everything that does not cross the boundary is
      # still an ordinary edit for a kb.update holder.
      it "still allows edits that do not cross the published boundary" do
        draft = article!(status: "draft", slug: "d3")

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { title: "Edited", status: "review" } },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(draft.reload.status).to eq("review")
        expect(draft.title).to eq("Edited")
      end

      it "still allows draft -> archived" do
        draft = article!(status: "draft", slug: "d4")

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { status: "archived" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(draft.reload.status).to eq("archived")
      end

      it "still allows an edit that omits status entirely" do
        live = article!(status: "published", slug: "p3")

        patch "/api/v1/kb/articles/#{live.id}",
              params: { article: { title: "Retitled" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(live.reload.title).to eq("Retitled")
        expect(live.status).to eq("published")
      end

      # A no-op status write does not cross anything.
      it "still allows re-sending the status an article already has" do
        live = article!(status: "published", slug: "p4")

        patch "/api/v1/kb/articles/#{live.id}",
              params: { article: { status: "published" } }, headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(live.reload.status).to eq("published")
      end
    end

    context "when the caller holds kb.publish" do
      it "publishes and records the transition" do
        draft = article!(status: "draft", slug: "d5", author: publisher)

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { status: "published" } }, headers: publisher_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(draft.reload.status).to eq("published")
        expect(workflows_for(draft).last).to have_attributes(
          action: "publish", from_status: "draft", to_status: "published", user_id: publisher.id
        )
      end
    end

    # kb.manage is accepted by can_publish_kb? and by #publish/#unpublish
    # already. The agent path excludes kb.manage only because it is that tool's
    # own REQUIRED_PERMISSION (which would make its check vacuous) — reasoning
    # that does not carry here, where the edit gate is kb.update.
    context "when the caller holds kb.manage" do
      it "publishes, matching what #publish already grants it" do
        draft = article!(status: "draft", slug: "d6", author: manager)

        patch "/api/v1/kb/articles/#{draft.id}",
              params: { article: { status: "published" } }, headers: manager_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(draft.reload.status).to eq("published")
      end
    end
  end

  describe "PATCH /api/v1/kb/articles/bulk" do
    let!(:one) { article!(status: "draft", slug: "b1") }
    let!(:two) { article!(status: "draft", slug: "b2") }

    context "when the caller holds only kb.update" do
      it "refuses a bulk publish" do
        patch "/api/v1/kb/articles/bulk",
              params: { article_ids: [ one.id, two.id ], status: "published" },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(one.reload.status).to eq("draft")
        expect(two.reload.status).to eq("draft")
        expect(KnowledgeBase::Workflow.count).to eq(0)
      end

      # All-or-nothing, matching the existing "Access denied for some articles"
      # shape: one boundary-crossing article refuses the whole batch rather
      # than publishing the rest.
      it "refuses the whole batch when only one article would cross the boundary" do
        live = article!(status: "published", slug: "b3")

        patch "/api/v1/kb/articles/bulk",
              params: { article_ids: [ one.id, live.id ], status: "draft" },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(live.reload.status).to eq("published")
        expect(one.reload.status).to eq("draft")
      end

      it "still allows a bulk update that does not touch status" do
        patch "/api/v1/kb/articles/bulk",
              params: { article_ids: [ one.id, two.id ], is_featured: true },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(one.reload.is_featured).to be true
        expect(two.reload.is_featured).to be true
      end

      it "still allows a bulk status move that does not cross the boundary" do
        patch "/api/v1/kb/articles/bulk",
              params: { article_ids: [ one.id, two.id ], status: "review" },
              headers: editor_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(one.reload.status).to eq("review")
        expect(two.reload.status).to eq("review")
      end
    end

    context "when the caller holds kb.publish" do
      it "publishes the batch" do
        patch "/api/v1/kb/articles/bulk",
              params: { article_ids: [ one.id, two.id ], status: "published" },
              headers: publisher_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(one.reload.status).to eq("published")
        expect(two.reload.status).to eq("published")
      end
    end
  end

  # ── HALF 2: a bulk status move must leave an audit trail ─────────────────
  describe "bulk_update audit trail" do
    let!(:one) { article!(status: "draft", slug: "a1", author: publisher) }
    let!(:two) { article!(status: "review", slug: "a2", author: publisher) }

    it "records one transition row per article, with the right from/to" do
      patch "/api/v1/kb/articles/bulk",
            params: { article_ids: [ one.id, two.id ], status: "published" },
            headers: publisher_headers, as: :json

      expect(response).to have_http_status(:ok)

      expect(workflows_for(one).last).to have_attributes(
        action: "publish", from_status: "draft", to_status: "published"
      )
      # Each row carries its OWN from_status — a batch is not one transition.
      expect(workflows_for(two).last).to have_attributes(
        action: "publish", from_status: "review", to_status: "published"
      )
    end

    it "attributes every row to the acting user, via the same helper #update uses" do
      patch "/api/v1/kb/articles/bulk",
            params: { article_ids: [ one.id, two.id ], status: "published" },
            headers: publisher_headers, as: :json

      rows = KnowledgeBase::Workflow.where(article_id: [ one.id, two.id ])
      expect(rows.count).to eq(2)
      expect(rows.map(&:user_id).uniq).to eq([ publisher.id ])
      # source: "api" is what record_article_workflow! stamps; a second, looser
      # emission path would not carry it.
      expect(rows.map { |r| r.metadata["source"] }.uniq).to eq([ "api" ])
    end

    it "names an unpublish correctly when the batch leaves published" do
      live = article!(status: "published", slug: "a3", author: publisher)

      patch "/api/v1/kb/articles/bulk",
            params: { article_ids: [ live.id ], status: "draft" },
            headers: publisher_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(workflows_for(live).last).to have_attributes(
        action: "unpublish", from_status: "published", to_status: "draft"
      )
    end

    it "records an edit row for a bulk change that does not move status" do
      patch "/api/v1/kb/articles/bulk",
            params: { article_ids: [ one.id ], is_featured: true },
            headers: publisher_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(workflows_for(one).last).to have_attributes(
        action: "edit", from_status: "draft", to_status: "draft"
      )
    end
  end
end
