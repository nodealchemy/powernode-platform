# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::ContentDrafts", type: :request do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account, slug: "provider-a") }
  let(:reader) { create(:user, account: account, permissions: [ "ai.content_drafts.read" ]) }
  let(:writer) { create(:user, account: account, permissions: [ "ai.content_drafts.read", "ai.content_drafts.manage" ]) }
  let(:reader_headers) { auth_headers_for(reader) }
  let(:writer_headers) { auth_headers_for(writer) }
  let!(:draft) { create(:ai_content_draft, account: account, data_source: data_source) }

  describe "GET /api/v1/ai/content_drafts" do
    it "lists drafts for a permitted reader" do
      get "/api/v1/ai/content_drafts", headers: reader_headers, as: :json

      expect_success_response
      expect(json_response_data["items"].map { |d| d["id"] }).to include(draft.id)
    end

    it "denies a user without ai.content_drafts.read" do
      no_access = create(:user, account: account, permissions: [])

      get "/api/v1/ai/content_drafts", headers: auth_headers_for(no_access), as: :json

      expect_error_response("Permission denied: ai.content_drafts.read", 403)
    end
  end

  describe "GET /api/v1/ai/content_drafts/:id" do
    it "shows a single draft" do
      get "/api/v1/ai/content_drafts/#{draft.id}", headers: reader_headers, as: :json

      expect_success_response
      expect(json_response_data["draft"]["id"]).to eq(draft.id)
    end
  end

  describe "POST /api/v1/ai/content_drafts" do
    it "denies a user without ai.content_drafts.manage" do
      post "/api/v1/ai/content_drafts",
           params: { data_source_id: data_source.slug, brief: "announce the launch" },
           headers: reader_headers, as: :json

      expect_error_response("Permission denied: ai.content_drafts.manage", 403)
    end

    it "creates a draft via ContentDraftingService for a permitted user" do
      drafting_service = instance_double(Ai::Growth::ContentDraftingService)
      allow(Ai::Growth::ContentDraftingService).to receive(:new).and_return(drafting_service)
      allow(drafting_service).to receive(:draft).and_return(draft)

      post "/api/v1/ai/content_drafts",
           params: { data_source_id: data_source.slug, brief: "announce the launch" },
           headers: writer_headers, as: :json

      expect_success_response
      expect(response).to have_http_status(:created)
      expect(json_response_data["draft"]["id"]).to eq(draft.id)
    end
  end

  describe "POST /api/v1/ai/content_drafts/:id/approve" do
    it "approves a draft status transition" do
      post "/api/v1/ai/content_drafts/#{draft.id}/approve", headers: writer_headers, as: :json

      expect_success_response
      expect(json_response_data["draft"]["status"]).to eq("approved")
      expect(draft.reload.status).to eq("approved")
    end

    it "rejects an invalid transition with 422" do
      draft.update!(status: "published")

      post "/api/v1/ai/content_drafts/#{draft.id}/approve", headers: writer_headers, as: :json

      expect_error_response(nil, 422)
    end
  end

  describe "POST /api/v1/ai/content_drafts/:id/reject" do
    it "rejects a draft" do
      post "/api/v1/ai/content_drafts/#{draft.id}/reject", params: { reason: "off-brand" }, headers: writer_headers, as: :json

      expect_success_response
      expect(draft.reload.status).to eq("rejected")
    end
  end

  describe "POST /api/v1/ai/content_drafts/:id/publish" do
    it "denies a user without ai.content_drafts.manage" do
      post "/api/v1/ai/content_drafts/#{draft.id}/publish", headers: reader_headers, as: :json

      expect_error_response("Permission denied: ai.content_drafts.manage", 403)
    end

    it "dispatches the publish for a permitted user" do
      publishing_service = instance_double(Ai::Growth::ContentPublishingService)
      allow(Ai::Growth::ContentPublishingService).to receive(:new).and_return(publishing_service)
      allow(publishing_service).to receive(:publish).and_return(
        { draft_id: draft.id, status: "published", thread: false, segment_count: 1,
          target_count: 1, published_count: 1, proposed_count: 0, failed_count: 0,
          fully_published: true, segments: [] }
      )

      post "/api/v1/ai/content_drafts/#{draft.id}/publish", headers: writer_headers, as: :json

      expect_success_response
      expect(json_response_data["published_count"]).to eq(1)
      expect(json_response_data["fully_published"]).to be(true)
    end
  end
end
