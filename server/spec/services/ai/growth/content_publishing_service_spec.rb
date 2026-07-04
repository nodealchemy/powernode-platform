# frozen_string_literal: true

require "rails_helper"

# Content drafting -> publish (D2): ContentPublishingService dispatches a
# reviewable Ai::ContentDraft (D1) through Ai::Growth::CrossPostService (G2) —
# the SAME choke point (Ai::Tools::DataSourceTool#guarded_fetch/propose_write)
# every other governed write already goes through (see
# cross_post_service_spec.rb and published_post_recorder_spec.rb) — so an
# agent lacking ai.data_sources.manage must get a proposal, NEVER a silent
# live post, and the draft must never flip to "published" without one.
RSpec.describe Ai::Growth::ContentPublishingService, type: :service do
  let(:account) { create(:account) }

  let!(:primary_source) { create(:ai_data_source, account: account, slug: "provider-a", name: "Provider A") }
  let!(:primary_endpoint) do
    create(:ai_data_source_endpoint, data_source: primary_source, slug: "create-post",
           name: "Create post", http_method: "POST", cache_ttl_seconds: 0,
           metadata: { "side_effecting" => true, "captures_published_post" => true })
  end

  let!(:secondary_source) { create(:ai_data_source, account: account, slug: "provider-b", name: "Provider B") }
  let!(:secondary_endpoint) do
    create(:ai_data_source_endpoint, data_source: secondary_source, slug: "create-status",
           name: "Create status", http_method: "POST", cache_ttl_seconds: 0,
           metadata: { "side_effecting" => true, "captures_published_post" => true })
  end

  let(:draft) { create(:ai_content_draft, account: account, data_source: primary_source) }

  def fake_envelope(id)
    { success: true, data: [ { "id" => id } ], provenance: {}, status: "success",
      duration_ms: 1, bytes: 0, error: nil }
  end

  # ---------------------------------------------------------------------
  # No agent context (a direct/human-authorized call — mirrors
  # CrossPostService's own "no agent context => already authorized upstream"
  # convention, exercised by Api::V1::Ai::ContentDraftsController#publish).
  # ---------------------------------------------------------------------
  context "with no agent context" do
    let(:service) { described_class.new(account: account) }

    it "publishes a single-segment draft, marks it published, and records provenance" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope("100"))
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = nil
      expect { result = service.publish(draft: draft) }.to change(Ai::PublishedPost, :count).by(1)

      expect(result[:fully_published]).to be(true)
      expect(result[:target_count]).to eq(1)
      expect(result[:published_count]).to eq(1)
      expect(result[:proposed_count]).to eq(0)
      expect(draft.reload.status).to eq("published")

      post = Ai::PublishedPost.last
      expect(post.data_source).to eq(primary_source)
      expect(post.external_id).to eq("100")
    end

    it "publishes every thread segment in sequence, reusing a single CrossPostService/DataSourceTool instance" do
      thread_draft = create(:ai_content_draft, :thread, account: account, data_source: primary_source)
      fake = instance_double(Ai::DataSources::QueryService)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)
      allow(fake).to receive(:call).and_return(fake_envelope("200"), fake_envelope("201"))
      expect(Ai::Growth::CrossPostService).to receive(:new).once.and_call_original
      expect(Ai::Tools::DataSourceTool).to receive(:new).once.and_call_original

      result = service.publish(draft: thread_draft)

      expect(Ai::DataSources::QueryService).to have_received(:new).twice
      expect(result[:thread]).to be(true)
      expect(result[:segment_count]).to eq(2)
      expect(result[:fully_published]).to be(true)
      expect(thread_draft.reload.status).to eq("published")
      expect(Ai::PublishedPost.where(ai_data_source_id: primary_source.id).count).to eq(2)
    end

    it "fans a non-thread draft out to additional_targets by reusing CrossPostService (no duplicated fan-out)" do
      fake = instance_double(Ai::DataSources::QueryService)
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)
      allow(fake).to receive(:call).and_return(fake_envelope("300"), fake_envelope("301"))

      result = service.publish(draft: draft, additional_targets: [ { data_source_id: "provider-b" } ])

      expect(result[:target_count]).to eq(2)
      expect(result[:published_count]).to eq(2)
      expect(result[:fully_published]).to be(true)
      expect(draft.reload.status).to eq("published")
      expect(Ai::PublishedPost.where(ai_data_source_id: secondary_source.id).count).to eq(1)
    end

    it "de-duplicates an additional_target that repeats the draft's own data source" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope("400"))
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = service.publish(draft: draft, additional_targets: [ { data_source_id: "provider-a" } ])

      expect(result[:target_count]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # Agent context: the write-endpoint gate applies per target — the
  # essential approval-gate-never-silent-publish guarantee.
  # ---------------------------------------------------------------------
  context "with an agent lacking ai.data_sources.manage" do
    let!(:unprivileged_user) { create(:user, account: account, permissions: [ "ai.data_sources.query" ]) }
    let(:agent) { create(:ai_agent, account: account, creator: unprivileged_user) }
    let(:service) { described_class.new(account: account, agent: agent, user: unprivileged_user) }

    it "never dispatches QueryService, files a proposal instead, and never marks the draft published" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      result = nil
      expect { result = service.publish(draft: draft) }.to change(Ai::AgentProposal, :count).by(1)
      expect(Ai::PublishedPost.count).to eq(0)

      expect(result[:published_count]).to eq(0)
      expect(result[:proposed_count]).to eq(1)
      expect(result[:fully_published]).to be(false)
      expect(draft.reload.status).to eq("pending_review")
    end
  end

  context "with an agent holding ai.data_sources.manage" do
    let!(:privileged_user) { create(:user, account: account, permissions: [ "ai.data_sources.query", "ai.data_sources.manage" ]) }
    let(:agent) { create(:ai_agent, account: account, creator: privileged_user) }
    let(:service) { described_class.new(account: account, agent: agent, user: privileged_user) }

    it "dispatches directly, with no proposal, and marks the draft published" do
      fake = instance_double(Ai::DataSources::QueryService, call: fake_envelope("500"))
      allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)

      result = nil
      expect { result = service.publish(draft: draft) }.not_to change(Ai::AgentProposal, :count)

      expect(result[:fully_published]).to be(true)
      expect(draft.reload.status).to eq("published")
    end
  end

  # ---------------------------------------------------------------------
  # validation / edge cases
  # ---------------------------------------------------------------------
  describe "validation" do
    let(:service) { described_class.new(account: account) }

    it "raises for a draft belonging to a different account" do
      other_account = create(:account)
      foreign_source = create(:ai_data_source, account: other_account)
      foreign_draft = create(:ai_content_draft, account: other_account, data_source: foreign_source)

      expect { service.publish(draft: foreign_draft) }
        .to raise_error(Ai::Growth::ContentPublishingError, /different account/)
    end

    it "raises for an already-published draft" do
      draft.update!(status: "published")

      expect { service.publish(draft: draft) }
        .to raise_error(Ai::Growth::ContentPublishingError, /cannot be published/)
    end

    it "raises for a rejected draft" do
      draft.update!(status: "rejected")

      expect { service.publish(draft: draft) }
        .to raise_error(Ai::Growth::ContentPublishingError, /cannot be published/)
    end
  end
end
