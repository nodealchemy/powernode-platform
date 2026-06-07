# frozen_string_literal: true

require "digest"

module Ai
  module DataSources
    # RAG INGESTION BRIDGE (Phase 4b-3) — pipe canonical data-source records into a
    # knowledge base so a fleet can SEMANTICALLY RETRIEVE and "interpret data over
    # time" rather than re-fetching+re-parsing on every question.
    #
    # PURPOSE
    #   The QueryService produces canonical, normalized, masked records from an
    #   external source. Those records are point-in-time. This bridge turns a batch
    #   of them into embedded Ai::Document rows in an Ai::KnowledgeBase, so the same
    #   data is queryable through the existing RAG retrieval path (vector search,
    #   hybrid search) long after the fetch. It is a one-directional PULL sink:
    #   records in -> embedded documents out. It NEVER fetches (that is QueryService)
    #   and NEVER reconciles across sources (that is the multi-source coordinator).
    #
    # REUSE (invents NO new model, NO new embedding path)
    #   * Ai::RagService#create_document(kb_id, params, user:) — builds the
    #     Ai::Document (source_type, content, metadata, name) + checksum.
    #   * Ai::RagService#process_document(kb_id, doc_id)       — chunks the content.
    #   * Ai::RagService#embed_chunks(kb_id, document_id:)     — embeds the chunks
    #     (process_document only chunks; embedding is a separate step, so we run it
    #     per-document here to make ingested records actually retrievable).
    #
    # SOURCE_TYPE
    #   Documents are stamped source_type "api" — the only Ai::Document source_type
    #   that fits an external-API-derived record (the allow-list is
    #   %w[upload url api database cloud_storage git]).
    #
    # INCREMENTAL RE-EMBED (when `key:` is given)
    #   Records are deduplicated by their canonical record_key (record[key]):
    #     * unchanged (same record_key AND same content_sha256) -> SKIP (no re-embed)
    #     * changed   (same record_key, different content_sha256) -> UPDATE
    #       (destroy the prior doc + re-create + re-embed)
    #     * brand new (no prior doc with this record_key)        -> CREATE
    #   This avoids re-embedding records that have not changed since the last run.
    #   Prior docs are located by the metadata record_key stamped on each Document
    #   (jsonb metadata->>'record_key'), scoped to THIS knowledge base.
    #
    # BOUNDED
    #   At most MAX_RECORDS_PER_CALL records are ingested per call; the remainder are
    #   reported as capped (and logged) so a single call can never trigger a runaway
    #   embedding storm over a huge fetched batch.
    #
    # RESILIENT
    #   A per-record failure is logged + counted under errors: and NEVER aborts the
    #   batch. Account-scoped: the knowledge base MUST belong to @account.
    #
    # CONTRACT
    #   Ai::DataSources::RagIngestionService
    #     .new(account:, user: nil)
    #     #ingest(data_source:, endpoint:, knowledge_base:, records:, key: nil)
    #       => {
    #            ingested:, updated:, skipped:, capped:, errors:, knowledge_base_id:
    #          }
    #
    # METADATA STAMPED ON EACH Document.metadata (string keys):
    #   "data_source_id", "endpoint_id", "data_source_slug",
    #   "record_key" (record[key] when key given, else nil), "content_sha256"
    class RagIngestionService
      # Hard cap on records ingested per call — bounds embedding cost so a huge
      # fetched batch cannot kick off a runaway embed. Overflow is reported (capped:)
      # and logged, never silently dropped.
      MAX_RECORDS_PER_CALL = 5_000

      # Ai::Document source_type for an external-API-derived record. Must be a member
      # of the Ai::Document inclusion allow-list %w[upload url api database
      # cloud_storage git].
      DOCUMENT_SOURCE_TYPE = "api"

      # How many characters of generated content we keep per document — a defensive
      # cap so a pathological single record cannot produce an enormous document body.
      MAX_CONTENT_CHARS = 100_000

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Ingest a batch of canonical records into `knowledge_base` as embedded
      # documents. Returns a tally Hash; never raises (every per-record failure is
      # rescued + counted under :errors).
      def ingest(data_source:, endpoint:, knowledge_base:, records:, key: nil)
        kb = resolve_knowledge_base(knowledge_base)
        return error_result(nil, "knowledge base not found for account") unless kb

        rows = Array(records).select { |r| r.is_a?(Hash) }
        capped = [rows.size - MAX_RECORDS_PER_CALL, 0].max
        if capped.positive?
          Rails.logger.warn(
            "[DataSources::RagIngestionService] capped ingest for kb=#{kb.id} " \
            "source=#{safe_slug(data_source)}: #{rows.size} records -> #{MAX_RECORDS_PER_CALL} (capped #{capped})"
          )
          rows = rows.first(MAX_RECORDS_PER_CALL)
        end

        key_field = normalize_key(key)

        tally = { ingested: 0, updated: 0, skipped: 0, capped: capped, errors: 0,
                  knowledge_base_id: kb.id }

        rows.each do |record|
          ingest_one(kb: kb, data_source: data_source, endpoint: endpoint,
                     record: record, key_field: key_field, tally: tally)
        end

        # Embed all newly-created chunks in ONE pass (embed_chunks with no document_id
        # embeds every chunk lacking an embedding) so the KB's complete_indexing!
        # fires ONCE for the whole batch instead of once per record.
        embed_batch(kb) if (tally[:ingested] + tally[:updated]).positive?

        tally
      rescue StandardError => e
        # Defense in depth: the per-record loop is already rescued; this guards
        # setup (kb resolution / array coercion) so the bridge never raises.
        Rails.logger.error(
          "[DataSources::RagIngestionService] ingest failed for source=#{safe_slug(data_source)}: #{e.class}: #{e.message}"
        )
        error_result(safe_kb_id(knowledge_base), redact(e.message))
      end

      private

      attr_reader :account, :user

      # Ingest a single record: dedup (when key given) -> create/update/skip ->
      # chunk -> embed. A failure here is logged + counted, never propagated.
      def ingest_one(kb:, data_source:, endpoint:, record:, key_field:, tally:)
        content = serialize_record(record)
        if content.blank?
          tally[:skipped] += 1
          return
        end

        content_sha = Digest::SHA256.hexdigest(content)
        record_key = key_field ? record_key_value(record, key_field) : nil

        # INCREMENTAL dedup is only meaningful when we have a stable record_key.
        if record_key.present?
          existing = find_existing_document(kb, data_source, endpoint, record_key)
          if existing
            if document_content_sha(existing) == content_sha
              tally[:skipped] += 1 # unchanged -> no re-embed
              return
            end
            # changed -> UPDATE via create-NEW-then-delete-OLD: if create/chunk raises,
            # the PRIOR document stays intact (never a window with zero docs for this
            # key). Then drop the stale doc(s) — scoped to this source+endpoint+key,
            # including any accumulated duplicates — EXCEPT the freshly created one.
            new_doc = create_and_chunk(kb: kb, data_source: data_source, endpoint: endpoint,
                                       record: record, content: content, content_sha: content_sha,
                                       record_key: record_key)
            existing_documents(kb, data_source, endpoint, record_key)
              .where.not(id: new_doc.id).destroy_all
            tally[:updated] += 1
            return
          end
        end

        # brand new (or no key -> always create).
        create_and_chunk(kb: kb, data_source: data_source, endpoint: endpoint,
                         record: record, content: content, content_sha: content_sha,
                         record_key: record_key)
        tally[:ingested] += 1
      rescue StandardError => e
        tally[:errors] += 1
        Rails.logger.warn(
          "[DataSources::RagIngestionService] record ingest failed for kb=#{kb&.id} " \
          "source=#{safe_slug(data_source)}: #{e.class}: #{e.message}"
        )
      end

      # Create the document via RagService + chunk it. Returns the created Ai::Document.
      # Embedding is DEFERRED to a single post-loop #embed_batch pass so the KB's
      # complete_indexing! fires once per ingest, not once per record.
      def create_and_chunk(kb:, data_source:, endpoint:, record:, content:, content_sha:, record_key:)
        document = rag_service.create_document(
          kb.id,
          {
            name: document_title(record, record_key),
            source_type: DOCUMENT_SOURCE_TYPE,
            content_type: "text/plain",
            content: content,
            metadata: build_metadata(
              data_source: data_source, endpoint: endpoint,
              record_key: record_key, content_sha: content_sha
            )
          },
          user: user
        )

        rag_service.process_document(kb.id, document.id)
        document
      end

      # Embed all un-embedded chunks across the KB in one pass (document_id: nil),
      # so complete_indexing! runs once for the batch. Best-effort.
      def embed_batch(kb)
        rag_service.embed_chunks(kb.id)
      rescue StandardError => e
        Rails.logger.warn(
          "[DataSources::RagIngestionService] batch embed failed for kb=#{kb&.id}: #{e.class}: #{e.message}"
        )
      end

      # --------------------------------------------------------------------------
      # Metadata + content
      # --------------------------------------------------------------------------

      # The metadata stamped on every ingested Document (string keys so the jsonb
      # round-trips cleanly and the record_key dedup query matches).
      def build_metadata(data_source:, endpoint:, record_key:, content_sha:)
        {
          "data_source_id" => data_source&.id,
          "endpoint_id" => endpoint&.id,
          "data_source_slug" => safe_slug(data_source),
          "record_key" => record_key,
          "content_sha256" => content_sha
        }
      end

      # Serialize a record into a human-readable document body. Prefer aligned
      # "key: value" lines (more chunk-friendly and embedding-friendly than raw
      # JSON); fall back to pretty JSON if the line rendering is empty. Bounded by
      # MAX_CONTENT_CHARS.
      def serialize_record(record)
        text = render_key_value_lines(record)
        # Fall back to JSON only when the record has SOME usable content but the
        # key:value rendering came up empty (e.g. rendering raised). A record with no
        # non-empty key is genuinely empty -> stays blank (skipped) rather than
        # emitting a meaningless {"": ""} document.
        text = safe_json(record) if text.blank? && record_has_content?(record)
        return "" if text.blank?

        text.length > MAX_CONTENT_CHARS ? text[0, MAX_CONTENT_CHARS] : text
      end

      # True when the record has at least one non-empty key with a non-nil value —
      # i.e. there is something worth a document. Guards the JSON fallback so an
      # all-empty-key record is treated as blank (skipped).
      def record_has_content?(record)
        return false unless record.is_a?(Hash)

        record.any? { |k, v| k.to_s.strip.present? && !v.nil? }
      end

      def render_key_value_lines(record)
        record.filter_map do |k, v|
          key = k.to_s.strip
          next if key.empty?

          "#{key}: #{stringify_value(v)}"
        end.join("\n")
      rescue StandardError
        ""
      end

      # Render a value as a readable scalar; nested structures become compact JSON.
      def stringify_value(value)
        case value
        when nil then ""
        when String then value
        when Hash, Array then safe_json(value)
        else value.to_s
        end
      end

      def safe_json(obj)
        JSON.pretty_generate(obj)
      rescue StandardError
        obj.to_s
      end

      # A human-readable title for the document: the record_key, else a common name
      # field, else a generated id derived from the content/record.
      def document_title(record, record_key)
        return record_key.to_s if record_key.present?

        name = NAME_FIELDS.lazy.filter_map do |field|
          value = fetch_field(record, field)
          value.to_s.strip.presence
        end.first
        return name if name

        "record-#{Digest::SHA256.hexdigest(safe_json(record))[0, 16]}"
      end

      # Field names commonly carrying a human-readable label, in priority order.
      NAME_FIELDS = %w[name title label display_name id uuid slug].freeze

      # Read a field from a record tolerating string OR symbol keys.
      def fetch_field(record, field)
        return record[field] if record.key?(field)

        record[field.to_sym] if record.respond_to?(:key?) && record.key?(field.to_sym)
      rescue StandardError
        nil
      end

      # The canonical record key VALUE for dedup — record[key], string/symbol
      # tolerant, stringified. nil/blank when absent so such records always create.
      def record_key_value(record, key_field)
        value = fetch_field(record, key_field)
        value = fetch_field(record, key_field.to_s) if value.nil? && key_field.is_a?(Symbol)
        return nil if value.nil?

        value.to_s.presence
      end

      def normalize_key(key)
        return nil if key.nil?

        key.to_s.strip.presence
      end

      # --------------------------------------------------------------------------
      # Incremental dedup lookups
      # --------------------------------------------------------------------------

      # All prior ingested documents in THIS kb for the same (source, endpoint,
      # record_key). Scoped to the source+endpoint — NOT just kb + record_key — so two
      # DIFFERENT sources that share a record_key value in the same KB cannot clobber
      # each other's documents.
      def existing_documents(kb, data_source, endpoint, record_key)
        rel = kb.documents.where("metadata->>'record_key' = ?", record_key.to_s)
        rel = rel.where("metadata->>'data_source_id' = ?", data_source.id.to_s) if data_source&.id
        rel = rel.where("metadata->>'endpoint_id' = ?", endpoint.id.to_s) if endpoint&.id
        rel
      end

      # The most-recent prior document for this (source, endpoint, record_key), or nil
      # — used to compare content_sha for the skip/update decision.
      def find_existing_document(kb, data_source, endpoint, record_key)
        existing_documents(kb, data_source, endpoint, record_key).order(created_at: :desc).first
      rescue StandardError => e
        # A lookup fault must not abort ingest — degrade to "treat as new" (create).
        Rails.logger.warn(
          "[DataSources::RagIngestionService] dedup lookup failed for kb=#{kb&.id}: #{e.class}: #{e.message}"
        )
        nil
      end

      # The content_sha256 stamped on a stored document's metadata (string/symbol
      # tolerant). nil when absent so a doc without a recorded sha is treated as
      # changed (forces a safe re-embed rather than a false skip).
      def document_content_sha(document)
        meta = document.metadata || {}
        meta["content_sha256"] || meta[:content_sha256]
      rescue StandardError
        nil
      end

      # --------------------------------------------------------------------------
      # Account scoping + helpers
      # --------------------------------------------------------------------------

      # Resolve the knowledge base to an account-scoped record. Accepts a model
      # instance, an id String, or anything responding to #id. Returns nil when it
      # does not belong to @account (account isolation).
      def resolve_knowledge_base(knowledge_base)
        return nil unless account

        id = if knowledge_base.is_a?(Ai::KnowledgeBase)
               knowledge_base.id
             elsif knowledge_base.respond_to?(:id) && !knowledge_base.is_a?(String)
               knowledge_base.id
             else
               knowledge_base
             end
        return nil if id.blank?

        Ai::KnowledgeBase.for_account(account.id).find_by(id: id)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::RagIngestionService] kb resolution failed: #{e.class}: #{e.message}")
        nil
      end

      def rag_service
        @rag_service ||= Ai::RagService.new(account)
      end

      def error_result(kb_id, message)
        { ingested: 0, updated: 0, skipped: 0, capped: 0, errors: 0,
          knowledge_base_id: kb_id, error: message }
      end

      def safe_kb_id(knowledge_base)
        knowledge_base.respond_to?(:id) ? knowledge_base.id : knowledge_base
      rescue StandardError
        nil
      end

      def safe_slug(data_source)
        data_source.respond_to?(:slug) ? data_source.slug : nil
      rescue StandardError
        nil
      end

      # Strip anything that looks like a token/secret out of an error message before
      # it reaches the log (defense in depth — we already avoid logging values).
      def redact(message)
        message.to_s.gsub(/(?i)(key|token|secret|password|authorization)=\S+/, '\1=[REDACTED]')
      rescue StandardError
        "error"
      end
    end
  end
end
