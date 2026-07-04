# frozen_string_literal: true

require "rails_helper"

# Content drafting (D1): Ai::Growth::ContentDraftingService generates a
# reviewable Ai::ContentDraft from knowledge-base content + a brand-voice
# profile, for one connected provider, via the platform LLM. The LLM call
# itself is stubbed (Ai::Llm::Client) so these specs stay deterministic and
# network-free; KB retrieval uses the DEFAULT "keyword" search mode, which is
# plain Postgres full-text search and needs no embedding provider either.
RSpec.describe Ai::Growth::ContentDraftingService, type: :service do
  let(:account) { create(:account) }

  let!(:knowledge_base) { create(:ai_knowledge_base, account: account) }
  let!(:document) { create(:ai_document, knowledge_base: knowledge_base, content: "Powernode governance overview") }
  let!(:chunk) do
    create(:ai_document_chunk, document: document, knowledge_base: knowledge_base,
           content: "Powernode ships a governed, approval-gated data-source layer for connected providers.")
  end

  let(:llm_provider) { create(:ai_provider) }
  let(:llm_credential) { create(:ai_provider_credential, provider: llm_provider) }

  let(:drafting_agent) do
    agent = create(:ai_agent, account: account, agent_type: "content_generator")
    allow(agent).to receive(:using_account).and_return(agent)
    allow(agent).to receive(:resolved_provider).and_return(llm_provider)
    allow(agent).to receive(:resolved_credential).and_return(llm_credential)
    allow(agent).to receive(:resolved_model).and_return("stub-model")
    agent
  end

  # Captures the messages/model passed to Ai::Llm::Client#complete and returns
  # +text+ as the (stubbed) generated draft.
  def stub_llm(text, success: true, finish_reason: "stop")
    response = instance_double(Ai::Llm::Response, success?: success, content: success ? text : nil, finish_reason: finish_reason)
    fake_client = instance_double(Ai::Llm::Client, complete: response)
    allow(Ai::Llm::Client).to receive(:new).and_return(fake_client)
    fake_client
  end

  def create_x_com_source
    source = create(:ai_data_source, account: account, slug: "x-com", source_type: "x_com")
    create(:ai_data_source_endpoint, data_source: source, slug: "create-post", http_method: "POST",
           metadata: { "side_effecting" => true, "max_content_length" => 280, "thread_splittable" => true })
    source
  end

  def create_linkedin_source
    source = create(:ai_data_source, account: account, slug: "linkedin", source_type: "linkedin")
    create(:ai_data_source_endpoint, data_source: source, slug: "create-post", http_method: "POST",
           metadata: { "side_effecting" => true, "max_content_length" => 3000, "thread_splittable" => false })
    source
  end

  describe "#draft" do
    context "with a KB fixture + brand voice" do
      let!(:data_source) { create_x_com_source }

      it "persists a reviewable draft built from the KB context and brand voice" do
        fake_client = stub_llm("A short, on-brand draft about governed data sources.")

        # The brief IS the keyword-search query (DEFAULT_SEARCH_MODE), and
        # Postgres to_tsquery ANDs every term together — reuse the chunk's own
        # wording so the match is deterministic regardless of stemming.
        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "x-com",
          brief: "governed approval-gated data-source layer providers",
          brand_voice: { tone: "confident", style: "concise" }
        )

        expect(draft).to be_a(Ai::ContentDraft)
        expect(draft).to be_persisted
        expect(draft.status).to eq("draft")
        expect(draft.account_id).to eq(account.id)
        expect(draft.ai_data_source_id).to eq(data_source.id)
        expect(draft.ai_knowledge_base_id).to eq(knowledge_base.id)
        expect(draft.requesting_agent_id).to eq(drafting_agent.id)
        expect(draft.source_type).to eq("x_com")
        expect(draft.content).to eq("A short, on-brand draft about governed data sources.")
        expect(draft.segments).to eq([ draft.content ])
        expect(draft.brand_voice).to eq("tone" => "confident", "style" => "concise")
        expect(draft.metadata["kb_chunk_ids"]).to include(chunk.id)

        # The KB content + brand voice actually reached the LLM prompt.
        messages = nil
        expect(fake_client).to have_received(:complete) { |args| messages = args[:messages] }
        combined = messages.map { |m| m[:content] }.join("\n")
        expect(combined).to include("governed, approval-gated data-source layer")
        expect(combined).to include("confident")
      end

      it "never auto-publishes — the record is only ever created with status draft" do
        stub_llm("Some draft text")

        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "x-com", brief: "Announce something"
        )

        expect(draft.status).to eq("draft")
        expect(Ai::PublishedPost.count).to eq(0)
      end

      it "raises when the brief is blank" do
        expect do
          described_class.new(account: account, agent: drafting_agent).draft(data_source_id: "x-com", brief: "")
        end.to raise_error(ArgumentError, /brief/)
      end

      it "defaults brand_voice from account.settings when none is given" do
        account.update!(settings: { "content_drafting" => { "brand_voice" => { "tone" => "playful" } } })
        stub_llm("Some draft text")

        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "x-com", brief: "Announce something"
        )

        expect(draft.brand_voice).to eq("tone" => "playful")
      end

      it "defaults to the account's active content_generator agent when none is given" do
        stub_llm("Some draft text")
        # drafting_agent is already an active content_generator on this account,
        # but auto-resolution re-queries it from the DB (a distinct object), so
        # the resolved_* stubs are applied class-wide for this one example.
        drafting_agent
        allow_any_instance_of(Ai::Agent).to receive(:resolved_provider).and_return(llm_provider)
        allow_any_instance_of(Ai::Agent).to receive(:resolved_credential).and_return(llm_credential)
        allow_any_instance_of(Ai::Agent).to receive(:resolved_model).and_return("stub-model")

        draft = described_class.new(account: account).draft(data_source_id: "x-com", brief: "Announce something")

        expect(draft.requesting_agent_id).to eq(drafting_agent.id)
      end

      it "raises when no content_generator agent is available" do
        expect do
          described_class.new(account: account).draft(data_source_id: "x-com", brief: "Announce something")
        end.to raise_error(Ai::Growth::ContentDraftingError, /no active content_generator agent/)
      end
    end

    context "X.com thread-splitting (>280 chars)" do
      let!(:data_source) { create_x_com_source }

      it "splits an over-length draft into a numbered thread, each segment within the limit" do
        long_text = (Faker::Lorem.words(number: 120).join(" "))
        stub_llm(long_text)

        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "x-com", brief: "A long announcement"
        )

        expect(draft.thread?).to be(true)
        expect(draft.segments.size).to be > 1
        expect(draft.segments).to all(satisfy { |s| s.length <= 280 })
        expect(draft.segments.last).to match(%r{\(\d+/\d+\)\z})
        expect(draft.content).to eq(draft.segments.first)
        expect(draft.metadata["truncated"]).to be(false)
      end

      it "leaves a within-limit draft as a single, unsplit segment" do
        stub_llm("Short enough to fit in one post.")

        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "x-com", brief: "A short announcement"
        )

        expect(draft.thread?).to be(false)
        expect(draft.segments).to eq([ "Short enough to fit in one post." ])
      end
    end

    context "a non-splittable provider (LinkedIn) over its limit" do
      let!(:data_source) { create_linkedin_source }

      it "truncates rather than threading" do
        long_text = "x" * 3100
        stub_llm(long_text)

        draft = described_class.new(account: account, agent: drafting_agent).draft(
          data_source_id: "linkedin", brief: "A very long post"
        )

        expect(draft.segments.size).to eq(1)
        expect(draft.content.length).to eq(3000)
        expect(draft.content).to end_with("…")
        expect(draft.metadata["truncated"]).to be(true)
      end
    end

    context "retired/misconfigured sources" do
      it "excludes a retired (inactive) source" do
        create(:ai_data_source, :inactive, account: account, slug: "retired")

        expect do
          described_class.new(account: account, agent: drafting_agent).draft(data_source_id: "retired", brief: "hi")
        end.to raise_error(Ai::Growth::ContentDraftingError, /not found or retired/)
      end

      it "excludes a source with no publish endpoint configured" do
        source = create(:ai_data_source, account: account, slug: "read-only")
        create(:ai_data_source_endpoint, data_source: source, slug: "list", http_method: "GET")

        expect do
          described_class.new(account: account, agent: drafting_agent).draft(data_source_id: "read-only", brief: "hi")
        end.to raise_error(Ai::Growth::ContentDraftingError, /no publish endpoint/)
      end

      it "excludes a source that requires auth but has no attached credential" do
        source = create(:ai_data_source, :requires_auth, account: account, slug: "needs-auth")
        create(:ai_data_source_endpoint, data_source: source, slug: "create-post", http_method: "POST",
               metadata: { "side_effecting" => true })

        expect do
          described_class.new(account: account, agent: drafting_agent).draft(data_source_id: "needs-auth", brief: "hi")
        end.to raise_error(Ai::Growth::ContentDraftingError, /no active credential/)
      end
    end
  end
end
