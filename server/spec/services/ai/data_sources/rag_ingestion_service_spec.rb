# frozen_string_literal: true

require "rails_helper"

# Phase 4b-3c — RAG ingestion bridge. Pipes canonical data-source records into a
# knowledge base as embedded Ai::Document rows so a fleet can semantically
# retrieve them later (instead of re-fetching).
#
# These specs exercise the REAL dedup/account-scoping DB queries
# (metadata->>'record_key', KnowledgeBase.for_account) against real Ai::Document
# rows, while stubbing the embedding-bearing collaborator (Ai::RagService) so no
# network/embedding work happens. The Ai::RagService double's #create_document is
# made to persist a real Ai::Document into kb.documents (mirroring the parts of
# the real implementation the dedup lookups depend on: name, source_type "api",
# content, metadata with record_key/content_sha256/data_source_id/endpoint_id),
# so the create-NEW-then-delete-OLD update path and the cross-source scoping all
# hit the database exactly as in production.
RSpec.describe Ai::DataSources::RagIngestionService, type: :service do
  let(:account) { create(:account) }
  let(:knowledge_base) { create(:ai_knowledge_base, account: account) }
  let(:data_source) { create(:ai_data_source, account: account) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

  let(:service) { described_class.new(account: account) }

  # ---------------------------------------------------------------------------
  # Ai::RagService double.
  #
  # create_document -> persists a REAL Ai::Document into the target kb so the
  #   incremental dedup query (metadata->>'record_key') and the cross-source
  #   scoping (metadata->>'data_source_id') resolve against actual rows.
  # process_document -> no-op (chunking is irrelevant to the dedup/embed-batch
  #   assertions; stubbing it keeps the specs free of DocumentChunk churn).
  # embed_chunks     -> spy (we assert it runs ONCE per batch, never per record).
  # ---------------------------------------------------------------------------
  let(:rag_service) { instance_double(Ai::RagService) }

  # Default create_document behaviour: persist a real Ai::Document into the kb.
  # Individual examples re-stub rag_service.create_document to raise (the
  # failure-isolation / failed-update paths) and delegate the success case here.
  let(:create_document_impl) do
    lambda do |kb_id, params, **_kwargs|
      kb = Ai::KnowledgeBase.find(kb_id)
      kb.documents.create!(
        name: params[:name],
        source_type: params[:source_type],
        content_type: params[:content_type],
        content: params[:content],
        content_size_bytes: params[:content]&.bytesize,
        metadata: params[:metadata] || {},
        status: "pending"
      )
    end
  end

  before do
    allow(Ai::RagService).to receive(:new).with(account).and_return(rag_service)
    allow(rag_service).to receive(:create_document) { |*args, **kwargs| create_document_impl.call(*args, **kwargs) }
    allow(rag_service).to receive(:process_document)
    allow(rag_service).to receive(:embed_chunks)
  end

  # Convenience: ingest with the common collaborators wired in.
  def ingest(records:, key: nil, kb: knowledge_base, ds: data_source, ep: endpoint)
    service.ingest(data_source: ds, endpoint: ep, knowledge_base: kb, records: records, key: key)
  end

  # All documents this source+endpoint stamped for a given record_key in the kb.
  def docs_for(record_key, kb: knowledge_base, ds: data_source)
    kb.documents
      .where("metadata->>'record_key' = ?", record_key.to_s)
      .where("metadata->>'data_source_id' = ?", ds.id.to_s)
  end

  describe "#ingest result shape" do
    it "returns the full tally hash with the knowledge_base_id" do
      result = ingest(records: [{ "id" => "r1", "city" => "Boston" }], key: "id")

      expect(result).to include(
        ingested: 1, updated: 0, skipped: 0, capped: 0, errors: 0,
        knowledge_base_id: knowledge_base.id
      )
      expect(result).not_to have_key(:error)
    end

    it "never raises and returns a tally even on an empty batch" do
      expect { ingest(records: []) }.not_to raise_error
      expect(ingest(records: [])).to include(ingested: 0, updated: 0, skipped: 0, errors: 0)
    end

    it "does not embed when there is nothing to ingest (empty batch)" do
      ingest(records: [])
      expect(rag_service).not_to have_received(:embed_chunks)
    end
  end

  describe "brand-new records (no prior doc for the record_key)" do
    it "creates a document and increments :ingested" do
      expect { ingest(records: [{ "id" => "r1", "city" => "Boston" }], key: "id") }
        .to change { knowledge_base.documents.count }.by(1)
    end

    it "reports ingested: 1 and creates+chunks the doc" do
      result = ingest(records: [{ "id" => "r1", "city" => "Boston" }], key: "id")

      expect(result).to include(ingested: 1, updated: 0, skipped: 0)
      expect(rag_service).to have_received(:create_document).once
      expect(rag_service).to have_received(:process_document).once
    end

    it "stamps source_type 'api' and the dedup metadata on the created document" do
      ingest(records: [{ "id" => "r1", "city" => "Boston" }], key: "id")

      doc = knowledge_base.documents.last
      expect(doc.source_type).to eq("api")
      expect(doc.metadata["record_key"]).to eq("r1")
      expect(doc.metadata["data_source_id"]).to eq(data_source.id)
      expect(doc.metadata["endpoint_id"]).to eq(endpoint.id)
      expect(doc.metadata["content_sha256"]).to be_present
    end

    it "ingests several distinct records in one batch" do
      records = [
        { "id" => "a", "v" => "1" },
        { "id" => "b", "v" => "2" },
        { "id" => "c", "v" => "3" }
      ]
      result = ingest(records: records, key: "id")

      expect(result).to include(ingested: 3, updated: 0, skipped: 0)
      expect(knowledge_base.documents.count).to eq(3)
    end

    it "creates (does not dedup) when no key is supplied" do
      result = ingest(records: [{ "id" => "r1" }, { "id" => "r1" }], key: nil)

      # No record_key -> dedup is skipped -> both rows create.
      expect(result).to include(ingested: 2, updated: 0, skipped: 0)
      expect(knowledge_base.documents.count).to eq(2)
    end

    it "skips a record that serializes to blank content (no doc created)" do
      result = ingest(records: [{ "" => "" }], key: "id")

      expect(result).to include(ingested: 0, skipped: 1)
      expect(knowledge_base.documents.count).to eq(0)
    end
  end

  describe "unchanged records (same record_key + same content_sha256)" do
    let(:record) { { "id" => "r1", "city" => "Boston", "temp" => "70" } }

    before { ingest(records: [record], key: "id") }

    it "SKIPS on re-ingest and does NOT create a second document" do
      expect { ingest(records: [record], key: "id") }
        .not_to change { knowledge_base.documents.count }
    end

    it "reports skipped: 1 (and ingested: 0) on the no-op re-ingest" do
      result = ingest(records: [record], key: "id")
      expect(result).to include(ingested: 0, updated: 0, skipped: 1)
    end

    it "calls create_document only on the first ingest, not on the unchanged re-ingest" do
      # Ingest the same record twice in one example: create_document fires for the
      # initial create, then the SKIP path means it is NOT invoked the second time.
      # (The before-block ingest already counts as the first call.)
      ingest(records: [record], key: "id")
      expect(rag_service).to have_received(:create_document).once
    end
  end

  # Self-contained (no shared `before` ingest) so the embed spy's call history
  # reflects ONLY the re-ingest — an unchanged-skip batch must not embed.
  describe "no embed on an all-skip batch" do
    it "does not call embed_chunks when every record is an unchanged skip" do
      record = { "id" => "r1", "city" => "Boston", "temp" => "70" }
      ingest(records: [record], key: "id")          # initial create (embeds once)

      # New double instance with a clean history for the assertion window.
      fresh = instance_double(Ai::RagService)
      allow(Ai::RagService).to receive(:new).with(account).and_return(fresh)
      allow(fresh).to receive(:create_document) { |*a, **k| create_document_impl.call(*a, **k) }
      allow(fresh).to receive(:process_document)
      allow(fresh).to receive(:embed_chunks)

      result = described_class.new(account: account)
               .ingest(data_source: data_source, endpoint: endpoint,
                       knowledge_base: knowledge_base, records: [record], key: "id")

      expect(result).to include(skipped: 1, ingested: 0)
      expect(fresh).not_to have_received(:embed_chunks)
    end
  end

  describe "changed records (same record_key, new content_sha256) -> UPDATE" do
    let(:original) { { "id" => "r1", "city" => "Boston", "temp" => "70" } }
    let(:changed)  { { "id" => "r1", "city" => "Boston", "temp" => "85" } }

    before { ingest(records: [original], key: "id") }

    it "creates the NEW doc and removes the OLD one (net document count unchanged)" do
      old_doc_id = docs_for("r1").first.id

      result = ingest(records: [changed], key: "id")

      expect(result).to include(updated: 1, ingested: 0, skipped: 0)
      remaining = docs_for("r1").to_a
      expect(remaining.size).to eq(1)
      expect(remaining.first.id).not_to eq(old_doc_id)        # NEW doc exists
      expect(Ai::Document.where(id: old_doc_id)).to be_empty  # OLD doc is gone
    end

    it "the surviving doc carries the NEW content_sha256" do
      ingest(records: [changed], key: "id")

      surviving = docs_for("r1").first
      expected_sha = Digest::SHA256.hexdigest(surviving.content)
      expect(surviving.metadata["content_sha256"]).to eq(expected_sha)
    end

    it "embeds once after an update batch" do
      # Swap in a fresh double for the assertion window so the before-block create's
      # embed is not counted; the update path must embed exactly once for this batch.
      fresh = instance_double(Ai::RagService)
      allow(Ai::RagService).to receive(:new).with(account).and_return(fresh)
      allow(fresh).to receive(:create_document) { |*a, **k| create_document_impl.call(*a, **k) }
      allow(fresh).to receive(:process_document)
      allow(fresh).to receive(:embed_chunks)

      described_class.new(account: account)
                     .ingest(data_source: data_source, endpoint: endpoint,
                             knowledge_base: knowledge_base, records: [changed], key: "id")

      expect(fresh).to have_received(:embed_chunks).once
    end
  end

  describe "create FAILURE on the UPDATE path leaves the OLD doc intact" do
    let(:original) { { "id" => "r1", "city" => "Boston", "temp" => "70" } }
    let(:changed)  { { "id" => "r1", "city" => "Boston", "temp" => "85" } }

    before { ingest(records: [original], key: "id") }

    it "keeps the prior document and counts the failure under :errors" do
      old_doc_id = docs_for("r1").first.id

      # On the update path, create_document raises BEFORE the old doc is deleted
      # (create-NEW-then-delete-OLD ordering), so the prior doc must survive.
      allow(rag_service).to receive(:create_document).and_raise(Ai::RagServiceError, "embed backend down")

      result = ingest(records: [changed], key: "id")

      expect(result).to include(errors: 1, updated: 0, ingested: 0)
      expect(Ai::Document.where(id: old_doc_id)).to be_present
      expect(docs_for("r1").to_a.map(&:id)).to eq([old_doc_id])
    end

    it "never destroys the old doc when the replacement create fails" do
      allow(rag_service).to receive(:create_document).and_raise(StandardError, "boom")

      expect { ingest(records: [changed], key: "id") }
        .not_to change { docs_for("r1").count }
    end
  end

  describe "CROSS-SOURCE dedup scoping (same record_key, same KB, DIFFERENT sources)" do
    let(:other_source) { create(:ai_data_source, account: account) }
    let(:other_endpoint) { create(:ai_data_source_endpoint, data_source: other_source) }

    it "does NOT clobber: both sources' docs survive for the shared record_key" do
      ingest(records: [{ "id" => "shared", "v" => "from-A" }], key: "id",
             ds: data_source, ep: endpoint)
      ingest(records: [{ "id" => "shared", "v" => "from-B" }], key: "id",
             ds: other_source, ep: other_endpoint)

      expect(docs_for("shared", ds: data_source).count).to eq(1)
      expect(docs_for("shared", ds: other_source).count).to eq(1)
      expect(knowledge_base.documents.count).to eq(2)
    end

    it "treats the second source's record as brand-new (ingested, not updated)" do
      ingest(records: [{ "id" => "shared", "v" => "from-A" }], key: "id",
             ds: data_source, ep: endpoint)

      result = ingest(records: [{ "id" => "shared", "v" => "from-B" }], key: "id",
                      ds: other_source, ep: other_endpoint)

      expect(result).to include(ingested: 1, updated: 0, skipped: 0)
    end

    it "an UPDATE on source B does not touch source A's doc for the same key" do
      ingest(records: [{ "id" => "shared", "v" => "A-v1" }], key: "id",
             ds: data_source, ep: endpoint)
      ingest(records: [{ "id" => "shared", "v" => "B-v1" }], key: "id",
             ds: other_source, ep: other_endpoint)
      a_doc_id = docs_for("shared", ds: data_source).first.id

      ingest(records: [{ "id" => "shared", "v" => "B-v2" }], key: "id",
             ds: other_source, ep: other_endpoint)

      expect(Ai::Document.where(id: a_doc_id)).to be_present
      expect(docs_for("shared", ds: data_source).map(&:id)).to eq([a_doc_id])
      expect(docs_for("shared", ds: other_source).count).to eq(1)
    end
  end

  describe "batch embedding runs ONCE per call (not per record)" do
    it "calls embed_chunks exactly once for a multi-record create batch" do
      allow(rag_service).to receive(:embed_chunks)

      ingest(records: [
        { "id" => "a", "v" => "1" },
        { "id" => "b", "v" => "2" },
        { "id" => "c", "v" => "3" }
      ], key: "id")

      expect(rag_service).to have_received(:embed_chunks).once
    end

    it "calls embed_chunks with the kb id and NO document_id (whole-batch pass)" do
      allow(rag_service).to receive(:embed_chunks)

      ingest(records: [{ "id" => "a", "v" => "1" }, { "id" => "b", "v" => "2" }], key: "id")

      # The batch pass embeds every un-embedded chunk: kb.id positionally, no
      # document_id keyword. embed_chunks(kb_id) — never embed_chunks(kb_id, document_id: ...).
      expect(rag_service).to have_received(:embed_chunks).with(knowledge_base.id).once
      expect(rag_service).not_to have_received(:embed_chunks).with(anything, hash_including(:document_id))
    end

    it "a batch-embed failure does not raise and the docs still exist" do
      allow(rag_service).to receive(:embed_chunks).and_raise(StandardError, "embed pool exhausted")

      result = nil
      expect { result = ingest(records: [{ "id" => "a", "v" => "1" }], key: "id") }.not_to raise_error
      expect(result).to include(ingested: 1)
      expect(knowledge_base.documents.count).to eq(1)
    end
  end

  describe "MAX_RECORDS_PER_CALL cap" do
    before { stub_const("Ai::DataSources::RagIngestionService::MAX_RECORDS_PER_CALL", 2) }

    it "reports the overflow under :capped and ingests only the cap" do
      records = [
        { "id" => "a", "v" => "1" },
        { "id" => "b", "v" => "2" },
        { "id" => "c", "v" => "3" },
        { "id" => "d", "v" => "4" }
      ]
      result = ingest(records: records, key: "id")

      expect(result[:capped]).to eq(2)        # 4 records - cap 2
      expect(result[:ingested]).to eq(2)
      expect(knowledge_base.documents.count).to eq(2)
    end

    it "reports capped: 0 when the batch is within the cap" do
      result = ingest(records: [{ "id" => "a", "v" => "1" }], key: "id")
      expect(result[:capped]).to eq(0)
    end
  end

  describe "account-scoped knowledge base" do
    it "returns a not-found error when the KB belongs to another account" do
      other_account = create(:account)
      foreign_kb = create(:ai_knowledge_base, account: other_account)

      result = ingest(records: [{ "id" => "r1" }], key: "id", kb: foreign_kb)

      expect(result[:error]).to match(/knowledge base not found/i)
      expect(result).to include(ingested: 0, updated: 0, skipped: 0, errors: 0)
    end

    it "does not create any document or embed for a foreign KB" do
      other_account = create(:account)
      foreign_kb = create(:ai_knowledge_base, account: other_account)

      expect { ingest(records: [{ "id" => "r1" }], key: "id", kb: foreign_kb) }
        .not_to change { Ai::Document.count }
      expect(rag_service).not_to have_received(:create_document)
      expect(rag_service).not_to have_received(:embed_chunks)
    end

    it "resolves a KB passed by id String (account-scoped)" do
      result = ingest(records: [{ "id" => "r1" }], key: "id", kb: knowledge_base.id)
      expect(result).to include(ingested: 1, knowledge_base_id: knowledge_base.id)
    end

    it "returns a not-found error for a non-existent KB id" do
      result = ingest(records: [{ "id" => "r1" }], key: "id", kb: "00000000-0000-0000-0000-000000000000")
      expect(result[:error]).to match(/knowledge base not found/i)
    end
  end

  describe "per-record failure isolation" do
    it "isolates a single bad record without aborting the rest of the batch" do
      # Make create_document raise ONLY for the middle record; the others persist.
      allow(rag_service).to receive(:create_document) do |kb_id, params, **kwargs|
        raise StandardError, "transient create failure" if params[:metadata]["record_key"] == "bad"

        create_document_impl.call(kb_id, params, **kwargs)
      end

      result = ingest(records: [
        { "id" => "good1", "v" => "1" },
        { "id" => "bad",   "v" => "x" },
        { "id" => "good2", "v" => "2" }
      ], key: "id")

      expect(result).to include(ingested: 2, errors: 1)
      expect(knowledge_base.documents.count).to eq(2)
      expect(docs_for("bad").count).to eq(0)
      expect(docs_for("good1").count).to eq(1)
      expect(docs_for("good2").count).to eq(1)
    end

    it "still embeds the batch when at least one record succeeded despite a failure" do
      allow(rag_service).to receive(:embed_chunks)
      allow(rag_service).to receive(:create_document) do |kb_id, params, **kwargs|
        raise StandardError, "boom" if params[:metadata]["record_key"] == "bad"

        create_document_impl.call(kb_id, params, **kwargs)
      end

      ingest(records: [{ "id" => "ok", "v" => "1" }, { "id" => "bad", "v" => "x" }], key: "id")

      expect(rag_service).to have_received(:embed_chunks).once
    end

    it "does not embed when EVERY record in the batch failed" do
      allow(rag_service).to receive(:embed_chunks)
      allow(rag_service).to receive(:create_document).and_raise(StandardError, "all down")

      result = ingest(records: [{ "id" => "a" }, { "id" => "b" }], key: "id")

      expect(result).to include(ingested: 0, errors: 2)
      expect(rag_service).not_to have_received(:embed_chunks)
    end

    it "ignores non-Hash entries in the records array" do
      result = ingest(records: [{ "id" => "r1", "v" => "1" }, "not-a-hash", nil, 42], key: "id")

      expect(result).to include(ingested: 1)
      expect(knowledge_base.documents.count).to eq(1)
    end
  end

  describe "string / symbol key tolerance for the dedup key field" do
    it "dedups symbol-keyed records on re-ingest (skips the unchanged one)" do
      rec = { id: "sym1", city: "Austin" }
      ingest(records: [rec], key: :id)

      result = ingest(records: [rec], key: :id)
      expect(result).to include(skipped: 1, ingested: 0)
      expect(knowledge_base.documents.count).to eq(1)
    end
  end
end
