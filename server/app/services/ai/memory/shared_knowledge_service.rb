# frozen_string_literal: true

module Ai
  module Memory
    # Shared Knowledge Service - Manages SharedKnowledge entries with semantic search
    # and ACL-based access control. Uses pgvector for similarity search and deduplication.
    #
    # Unlike StorageService shared learning methods (which use MemoryPool), this service operates
    # directly on the Ai::SharedKnowledge model with vector embeddings.
    class SharedKnowledgeService
      SIMILARITY_THRESHOLD = 0.3
      DEDUP_THRESHOLD = 0.92
      MAX_RESULTS = 20
      CHARS_PER_TOKEN = 4
      ACCESS_LEVEL_HIERARCHY = %w[private team account global].freeze

      # The hard ceiling on #archive_by_predicate! and #hard_delete_archived!
      # lives on Ai::BulkPredicateMutation::MAX_BULK_PER_CALL, not here — see
      # that module for the reasoning. Deliberately NOT aliased to a local
      # constant: a copy taken at class-load time would be a frozen Integer,
      # not a live reference, so `stub_const` on a local alias would silently
      # stop affecting the ceiling #call actually enforces. Stub
      # Ai::BulkPredicateMutation::MAX_BULK_PER_CALL directly.

      # Kill switch for the nightly producer (04:30 UTC,
      # AiSharedKnowledgeMaintenanceJob -> shared_maintenance ->
      # #import_from_learnings). SiteSetting, not Flipper — operator-facing,
      # admin-settings-editable, matching Ai::Learning::EvaluationService's
      # ai.evaluation.enabled shape.
      #
      # DEFAULTS TO ON, deliberately, per operator direction: an absent row
      # means the producer KEEPS RUNNING (seeds do not re-run after first
      # boot, so this is never seeded — see EvaluationService's identical
      # note). Getting this default backwards would silently stop the
      # platform learning anything, which the operator named as worse than
      # the archive-tooling gap this task exists to close.
      #
      # THE POLARITY IS INVERTED FROM EvaluationService.enabled? ON PURPOSE.
      # That switch treats an unparseable value as OFF (fails toward "don't
      # spend money on the judge" — the safe direction for a paid call).
      # Here OFF is the DANGEROUS direction — it silently stops the platform
      # learning anything and nobody would trace a later "why is knowledge
      # not growing" question back to a typo'd SiteSetting value. So a
      # garbage value here fails toward ON (with a logged warning), not OFF.
      # Copying EvaluationService's shape into a fourth switch without
      # re-deriving which direction is safe for THAT switch is exactly the
      # mistake this comment exists to prevent.
      KNOWLEDGE_PURGE_IMPORT_ENABLED_SETTING = "ai.knowledge_purge.import_from_learnings_enabled"

      # IMP-3c9a6dc8f0a9 review round (blocker 4) — reads the setting's raw
      # STORED value directly (SiteSetting#value, a string column) rather
      # than through ::SiteSetting.get, which type-casts per setting_type
      # BEFORE we ever see it. For a "boolean"-typed row, .get does
      # `value.to_s.downcase.in?(%w[true 1 yes])` — so a typo'd value like
      # "ture" is already collapsed to Ruby `false` by the time it reaches
      # us, indistinguishable from a deliberate false. Our own "garbage
      # fails toward ON" parsing below then never runs on the actual
      # garbage string — it runs on `false.to_s == "false"`, which matches
      # the `when "false"` branch cleanly and silently, with no warning.
      # The fail-toward-ON property this switch exists to guarantee only
      # held for a "string"-typed row, where .get returns the raw string
      # unmodified. Reading .value directly makes the property hold
      # regardless of which setting_type an operator (or a future seed)
      # gives this row — see "creates the row with setting_type: boolean
      # and a garbage value" in the spec for the case this fixes.
      #
      # IMP-3c9a6dc8f0a9 review round — REGRESSION FIX. The above fix's
      # first draft accepted only "true"/"false", a narrower set than what
      # ::SiteSetting.get's OWN cast accepts (`value.to_s.downcase.in?(%w[true
      # 1 yes])`). An operator who had already typed "0"/"no"/"off" into a
      # boolean-typed row — which worked correctly before this switch even
      # existed, via that cast — got OFF before this file's fix and
      # (wrongly) ON after: "0" matched neither "true" nor "false", hit the
      # garbage branch, and the switch designed to fail toward the SAFE
      # direction on garbage instead flipped a deliberate, working OFF into
      # an accidental ON. The parser here MUST be a superset of what
      # SiteSetting's own cast already accepted, because that is what an
      # operator may already have typed into an existing row.
      def self.import_from_learnings_enabled?
        setting = ::SiteSetting.find_by(key: KNOWLEDGE_PURGE_IMPORT_ENABLED_SETTING)
        return true if setting.nil?

        case setting.value.to_s.strip.downcase
        when "true", "1", "yes" then true
        when "false", "0", "no", "off" then false
        else
          Rails.logger.warn(
            "[SharedKnowledge] #{KNOWLEDGE_PURGE_IMPORT_ENABLED_SETTING}=#{setting.value.inspect} is not " \
            "true/false; treating it as ON — OFF is the dangerous direction for this switch " \
            "(silently stops the platform learning), so a garbage value fails toward ON, not OFF"
          )
          true
        end
      end

      def initialize(account:)
        @account = account
        @embedding_service = EmbeddingService.new(account: account)
      end

      # Create a new shared knowledge entry with deduplication
      def create(title:, content:, content_type: "text", access_level: "team",
                 tags: [], metadata: {}, agent: nil, team: nil, source_type: "manual")
        validate_content_type!(content_type)
        validate_access_level!(access_level)

        embedding = @embedding_service.generate(content)

        # Check for near-duplicates via semantic search.
        #
        # IMP-3c9a6dc8f0a9 — `.not_archived` on BOTH the `exists?` guard and
        # the `nearest_neighbors` scope. An archived row's embedding is still
        # live (archiving is a provenance flag, not a delete — see
        # SharedKnowledge#not_archived and the class-level note on the
        # embedding index), so without this an archived row could refuse a
        # brand-new, legitimate create as a "duplicate" AND — worse —
        # `touch_usage!` the archived row first, silently resurrecting the
        # usage stats of something already archived. Harmless at a handful of
        # archived rows; a landmine at the scale this task's bulk-archive
        # tooling produces (~6,250 rows in one pass).
        if embedding && Ai::SharedKnowledge.where(account: @account).not_archived.with_embedding.exists?
          duplicates = Ai::SharedKnowledge
            .where(account: @account)
            .not_archived
            .nearest_neighbors(:embedding, embedding, distance: "cosine")
            .first(3)

          if duplicates.any? && duplicates.first.neighbor_distance <= (1.0 - DEDUP_THRESHOLD)
            existing = duplicates.first
            existing.touch_usage!
            Rails.logger.info("[SharedKnowledge] Duplicate detected for '#{title}', existing entry: #{existing.id}")
            return {
              success: false,
              error: "Duplicate knowledge entry detected",
              existing_entry_id: existing.id,
              similarity: (1.0 - existing.neighbor_distance).round(4)
            }
          end
        end

        entry = Ai::SharedKnowledge.create!(
          account: @account,
          title: title,
          content: content,
          content_type: content_type,
          access_level: access_level,
          tags: tags,
          provenance: (metadata || {}).merge("source_type" => source_type),
          source_type: source_type,
          embedding: embedding,
          quality_score: calculate_quality_score(content, tags, metadata),
          usage_count: 0
        )

        entry.compute_integrity_hash!
        entry.touch_event_processed!

        Rails.logger.info("[SharedKnowledge] Created entry '#{title}' (#{entry.id}) [#{access_level}/#{content_type}]")
        { success: true, entry: serialize_entry(entry) }
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SharedKnowledge] Create failed: #{e.message}")
        { success: false, error: e.message }
      rescue ArgumentError
        raise
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Create failed: #{e.class} - #{e.message}")
        { success: false, error: "Failed to create knowledge entry" }
      end

      # Semantic search with ACL filtering
      def search(query:, access_level: nil, content_type: nil, team: nil,
                 tags: nil, limit: MAX_RESULTS)
        query_embedding = @embedding_service.generate_or_nil(query, context: "SharedKnowledgeService#search")

        scope = Ai::SharedKnowledge.where(account: @account).not_archived

        # Apply ACL filtering
        scope = scope.accessible_by(access_level) if access_level.present?

        # Apply content type filter
        scope = scope.by_content_type(content_type) if content_type.present?

        # Apply tag filter
        scope = scope.with_any_tags(tags) if tags.present? && tags.is_a?(Array) && tags.any?

        results = if query_embedding && scope.with_embedding.exists?
          scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .select { |e| e.neighbor_distance <= (1.0 - SIMILARITY_THRESHOLD) }
        else
          # Fallback to keyword search
          keyword_search(query, scope, limit)
        end

        entries = results.map do |entry|
          entry.touch_usage!
          serialized = serialize_entry(entry)
          serialized[:similarity] = (1.0 - entry.neighbor_distance).round(4) if entry.respond_to?(:neighbor_distance) && entry.neighbor_distance
          serialized[:freshness] = freshness_indicator(entry.updated_at)
          serialized
        end

        Rails.logger.info("[SharedKnowledge] Search for '#{query.truncate(50)}' returned #{entries.size} results")
        response = { success: true, entries: entries, count: entries.size }

        # IMP-eddcbe102619: a zero-result answer is ambiguous between "no
        # guidance on this topic" and "this store's knowledge corpus was
        # never seeded" — both return success:true with an empty array,
        # which is what let two dev-loop executors run with silently no
        # guidance on a bare-fixture MCP instance. For a guidance-tagged
        # recall, report which store answered and how many guidance-* rows
        # it holds IN TOTAL via one cheap COUNT aggregate (never walk rows)
        # so the caller can tell the two apart itself: "0 of 0" is a bare
        # store, "0 of 47" is a genuine miss.
        if guidance_tag_search?(tags)
          response[:store] = store_identifier
          response[:guidance_corpus_size] = guidance_corpus_size
        end

        response
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Search failed: #{e.message}")
        { success: false, error: "Search failed: #{e.message}", entries: [], count: 0 }
      end

      # Update an existing entry
      def update(entry_id:, title: nil, content: nil, metadata: nil, tags: nil,
                 content_type: nil, access_level: nil)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        validate_content_type!(content_type) if content_type
        validate_access_level!(access_level) if access_level

        attrs = {}
        attrs[:title] = title if title.present?
        attrs[:content_type] = content_type if content_type.present?
        attrs[:access_level] = access_level if access_level.present?
        attrs[:tags] = tags if tags
        attrs[:provenance] = entry.provenance.merge(metadata) if metadata.is_a?(Hash)

        content_changed = content.present? && content != entry.content
        if content_changed
          attrs[:content] = content
          attrs[:embedding] = @embedding_service.generate(content)
          attrs[:quality_score] = calculate_quality_score(
            content,
            tags || entry.tags,
            metadata || entry.provenance
          )
        end

        entry.update!(attrs) if attrs.any?
        entry.compute_integrity_hash! if content_changed

        Rails.logger.info("[SharedKnowledge] Updated entry #{entry_id}#{content_changed ? ' (content+embedding regenerated)' : ''}")
        { success: true, entry: serialize_entry(entry.reload) }
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SharedKnowledge] Update failed for #{entry_id}: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Update failed: #{e.class} - #{e.message}")
        { success: false, error: "Failed to update knowledge entry" }
      end

      # Archive an entry (soft delete via metadata flag)
      def archive(entry_id:)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        entry.update!(
          provenance: entry.provenance.merge(
            "archived" => true,
            "archived_at" => Time.current.iso8601
          )
        )

        Rails.logger.info("[SharedKnowledge] Archived entry #{entry_id}")
        { success: true, entry_id: entry_id }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Archive failed for #{entry_id}: #{e.message}")
        { success: false, error: "Failed to archive knowledge entry" }
      end

      # Promote entry access level (private → team → account → global)
      def promote(entry_id:, new_access_level:)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        validate_access_level!(new_access_level)

        current_index = ACCESS_LEVEL_HIERARCHY.index(entry.access_level)
        new_index = ACCESS_LEVEL_HIERARCHY.index(new_access_level)

        if new_index.nil? || current_index.nil?
          return { success: false, error: "Invalid access level" }
        end

        if new_index <= current_index
          return {
            success: false,
            error: "Cannot demote access level from '#{entry.access_level}' to '#{new_access_level}'"
          }
        end

        old_level = entry.access_level
        entry.update!(
          access_level: new_access_level,
          provenance: entry.provenance.merge(
            "promoted_at" => Time.current.iso8601,
            "promoted_from" => old_level
          )
        )

        Rails.logger.info("[SharedKnowledge] Promoted entry #{entry_id}: #{old_level} → #{new_access_level}")
        { success: true, entry: serialize_entry(entry.reload) }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Promote failed for #{entry_id}: #{e.message}")
        { success: false, error: "Failed to promote knowledge entry" }
      end

      # Import high-importance CompoundLearning entries as SharedKnowledge.
      # Caps per-call work via `max_per_run` so the worker's HTTP timeout
      # (120s default) doesn't kill mid-batch — caller chains follow-up
      # invocations until `remaining` reaches 0. Each processed learning
      # (imported OR skipped as duplicate) is stamped `last_event_processed_at`
      # and excluded from the scope for 24h, so the batch cursor genuinely
      # advances across chained runs instead of re-embedding the same
      # head-of-scope batch forever (the failure mode that stalled the
      # shared-knowledge feedback pipeline).
      def import_from_learnings(team: nil, min_importance: 0.7, max_per_run: 100)
        unless self.class.import_from_learnings_enabled?
          Rails.logger.info(
            "[SharedKnowledge] Import from learnings skipped — kill switch " \
            "#{KNOWLEDGE_PURGE_IMPORT_ENABLED_SETTING} is OFF"
          )
          return { success: true, imported: 0, skipped: 0, remaining: 0, skipped_reason: "kill_switch" }
        end

        scope = Ai::CompoundLearning
          .active
          .for_account(@account.id)
          .where("importance_score >= ?", min_importance)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)

        scope = scope.for_team(team.id) if team

        imported = 0
        skipped = 0

        # `find_each` ignores .limit, so materialize a bounded batch first.
        # Order by id (UUIDv7-sortable) to make checkpoint resumption stable.
        batch = scope.order(:id).limit(max_per_run).to_a
        batch.each do |learning|
          # Map compound learning category to shared knowledge content type
          content_type = map_learning_to_content_type(learning.category)

          result = create(
            title: learning.title || learning.content.truncate(100),
            content: learning.content,
            content_type: content_type,
            access_level: learning.scope == "global" ? "account" : "team",
            tags: learning.tags || [],
            metadata: {
              "source_type" => "import",
              "imported_from" => "compound_learning",
              "source_learning_id" => learning.id,
              "source_category" => learning.category,
              "original_importance" => learning.importance_score
            }.freeze,
            source_type: "import"
          )

          if result[:success]
            imported += 1
          else
            skipped += 1
          end

          # Advance the cursor for skipped learnings too — a duplicate means the
          # content already exists in shared knowledge, so re-processing it on
          # every run only burns embedding calls and blocks the backlog.
          learning.touch_event_processed!
        end

        # Processed learnings just left the scope (last_event_processed_at is
        # now current), so the recomputed count IS the remaining backlog.
        remaining = scope.count
        Rails.logger.info("[SharedKnowledge] Import: #{imported} imported, #{skipped} skipped (duplicates), #{[ remaining, 0 ].max} remaining")
        { success: true, imported: imported, skipped: skipped, remaining: [ remaining, 0 ].max }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Import from learnings failed: #{e.message}")
        { success: false, error: "Import failed", imported: 0, skipped: 0, remaining: 0 }
      end

      # Get knowledge statistics
      def stats(team: nil)
        scope = Ai::SharedKnowledge.where(account: @account).not_archived

        by_access_level = scope.group(:access_level).count
        by_content_type = scope.group(:content_type).count
        total = scope.count
        avg_quality = scope.average(:quality_score)&.to_f&.round(4) || 0
        total_usage = scope.sum(:usage_count)
        with_embeddings = scope.with_embedding.count

        most_used = scope
          .where("usage_count > 0")
          .order(usage_count: :desc)
          .limit(5)
          .map { |e| serialize_entry(e) }

        recently_added = scope
          .order(created_at: :desc)
          .limit(10)
          .map { |e| serialize_entry(e) }

        {
          success: true,
          stats: {
            total: total,
            by_access_level: by_access_level,
            by_content_type: by_content_type,
            avg_quality_score: avg_quality,
            total_usage: total_usage,
            with_embeddings: with_embeddings,
            embedding_coverage: total.positive? ? (with_embeddings.to_f / total * 100).round(1) : 0,
            most_used: most_used,
            recently_added: recently_added
          }
        }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Stats failed: #{e.message}")
        { success: false, error: "Failed to compute stats", stats: {} }
      end

      # Batch recalculate quality scores for entries not recalculated in 24h.
      # Caps per-call work via `max_per_run` (default 200) so the worker's
      # HTTP timeout (120s) can't kill us mid-batch. Returns `remaining` so
      # the caller can decide whether to chain follow-up invocations.
      def recalculate_all_quality(batch_size: 100, max_per_run: 200)
        scope = Ai::SharedKnowledge.where(account: @account)
          .not_archived
          .where("last_quality_recalc_at < ? OR last_quality_recalc_at IS NULL", 24.hours.ago)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)

        recalculated = 0
        skipped = Ai::SharedKnowledge.where(account: @account)
          .not_archived
          .where("last_event_processed_at >= ?", 24.hours.ago)
          .count

        # `find_each` ignores .limit, so materialize the bounded batch.
        # Oldest-first by `last_quality_recalc_at` so the most-stale rows
        # get attention first across runs.
        batch = scope.order(Arel.sql("last_quality_recalc_at NULLS FIRST"))
                     .limit(max_per_run)
                     .to_a
        batch.each_slice(batch_size) do |slice|
          slice.each do |entry|
            entry.recalculate_quality_score!
            recalculated += 1
          end
        end

        # `recalculate_quality_score!` stamps both `last_quality_recalc_at` and
        # `last_event_processed_at`, so processed rows have already left the
        # scope — the recomputed count IS the remaining backlog. Subtracting
        # batch.size again would under-report (often to 0) and prematurely stop
        # the worker's chained drain passes.
        remaining = scope.count
        Rails.logger.info("[SharedKnowledge] Batch quality recalc: #{recalculated} updated, #{skipped} skipped by event-driven, #{[ remaining, 0 ].max} remaining")
        { success: true, recalculated: recalculated, skipped_by_event: skipped, remaining: [ remaining, 0 ].max }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Batch quality recalc failed: #{e.message}")
        { success: false, error: e.message, recalculated: 0, remaining: 0 }
      end

      # Backfill vector embeddings for entries stored without one. `create` and
      # `update` generate embeddings synchronously via the worker, but if the
      # worker embedding service was unavailable at the time (or the row was
      # imported through a path that skipped it) the entry is persisted with
      # embedding: nil and is then permanently invisible to `semantic_search`
      # (which requires `with_embedding`). Nothing else ever fixes it. This
      # idempotent, batched, capped backfill is invoked by the daily shared
      # maintenance job so coverage self-heals. Oldest rows recover first.
      def backfill_embeddings(batch_size: 50, max_per_run: 200)
        scope = Ai::SharedKnowledge.where(account: @account)
          .where(embedding: nil)
          .not_archived

        pending = scope.count
        return { success: true, embedded: 0, failed: 0, remaining: 0 } if pending.zero?

        # `find_each` ignores .limit, so materialize the bounded batch.
        batch = scope.order(:created_at).limit(max_per_run).to_a
        embedded = 0
        failed = 0

        batch.each_slice(batch_size) do |slice|
          texts = slice.map { |entry| [ entry.title, entry.content ].compact_blank.join("\n\n") }
          vectors = @embedding_service.generate_batch(texts)

          slice.each_with_index do |entry, i|
            vector = vectors[i]
            if vector
              entry.update_columns(embedding: vector, last_event_processed_at: Time.current)
              embedded += 1
            else
              failed += 1
            end
          end
        end

        remaining = [ pending - embedded, 0 ].max
        Rails.logger.info("[SharedKnowledge] Embedding backfill: #{embedded} embedded, #{failed} failed, #{remaining} remaining")
        { success: true, embedded: embedded, failed: failed, remaining: remaining }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Embedding backfill failed: #{e.message}")
        { success: false, error: e.message, embedded: 0, failed: 0, remaining: 0 }
      end

      # Build LLM context from relevant shared knowledge within a token budget
      def build_context(query:, agent: nil, token_budget: 2000)
        char_budget = token_budget * CHARS_PER_TOKEN

        search_result = search(
          query: query,
          access_level: agent ? "team" : "account",
          limit: MAX_RESULTS
        )

        return { success: true, context: nil, token_estimate: 0, entry_ids: [] } unless search_result[:success] && search_result[:entries].any?

        lines = ["## Shared Knowledge"]
        used_chars = lines.first.length + 2
        entry_ids = []

        search_result[:entries].each do |entry|
          label = "[#{entry[:content_type]}]"
          similarity_note = entry[:similarity] ? " (#{(entry[:similarity] * 100).round}% match)" : ""
          line = "- #{label}#{similarity_note} #{entry[:title]}: #{entry[:content].truncate(200)}"

          break if used_chars + line.length > char_budget

          lines << line
          used_chars += line.length + 1
          entry_ids << entry[:id]
        end

        if lines.size == 1
          return { success: true, context: nil, token_estimate: 0, entry_ids: [] }
        end

        context = lines.join("\n")

        {
          success: true,
          context: context,
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          entry_ids: entry_ids
        }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Context build failed: #{e.message}")
        { success: false, context: nil, token_estimate: 0, entry_ids: [] }
      end

      # ==================================================
      # Predicate-scoped bulk archive / hard-delete (IMP-3c9a6dc8f0a9)
      # ==================================================
      #
      # Prerequisite for the platform-memory purge (report-platform.md §8/§10):
      # `delete_knowledge` takes one id per call; this is the predicate-scoped
      # path. TWO SEPARATE STEPS, deliberately, never one call that both finds
      # and hard-deletes: #archive_by_predicate! only ever touches NOT-yet-
      # archived rows (soft, reversible — unset the provenance flag to undo);
      # #hard_delete_archived! only ever touches rows THAT ARE ALREADY
      # archived (irreversible), and its own predicate can only narrow that
      # fixed base, never widen past it. This mirrors §10's own recommended
      # order (archive first, hard-delete only what is already archived as a
      # distinct later step) and means the irreversible half of this tool
      # only ever needs a much narrower, already-reviewed predicate.
      #
      # DRY-RUN IS THE DEFAULT ON BOTH. To actually mutate, the caller must
      # pass `dry_run: false` explicitly — one deliberate, named boolean flip,
      # not a flag a copy-pasted invocation forgets. A dry run never touches
      # the DB; it returns the same shape a real run would (count + sample),
      # minus `archived`/`deleted`.
      #
      # Archives (or hard-deletes) MAX_BULK_PER_CALL rows in the single call;
      # a predicate matching more REFUSES outright (see the constant comment)
      # rather than truncating.
      #
      # @param predicate [Hash] :tags, :content_type, :access_level,
      #   :source_type, :imported_from (provenance->>'imported_from'),
      #   :created_before, :ids — all optional, ANDed together. An empty
      #   predicate matches every not-yet-archived row in the account, which
      #   is a real thing an operator might want (and the count/ceiling still
      #   apply), not a mistake this method guards against on its own.
      # @param dry_run [Boolean] default true — see above.
      # @param actor [User, nil] attributed on the audit log entry when a real
      #   run mutates anything. nil for a rake/cron-driven run.
      def archive_by_predicate!(predicate: {}, dry_run: true, actor: nil)
        scope = build_knowledge_predicate_scope(predicate).not_archived

        Ai::BulkPredicateMutation.call(
          account: @account, scope: scope, dry_run: dry_run, actor: actor,
          action: "ai.knowledge.bulk_archive", predicate: predicate,
          serializer: ->(e) { { id: e.id, title: e.title } }, log_tag: "[SharedKnowledge]"
        ) do |entry|
          archive(entry_id: entry.id)[:success]
        end
      end

      # See the shared header comment above #archive_by_predicate! for why
      # this method's base scope (archived rows only) is NOT part of the
      # caller-supplied predicate and cannot be widened past it.
      #
      # @param predicate [Hash] the same optional keys as
      #   #archive_by_predicate!, plus :archived_before (compares against the
      #   provenance->>'archived_at' timestamp, not created_at) — all narrow
      #   the mandatory archived-only base further; none can remove it.
      def hard_delete_archived!(predicate: {}, dry_run: true, actor: nil)
        scope = build_knowledge_predicate_scope(predicate)
          .where("provenance @> ?", { archived: true }.to_json)

        if predicate[:archived_before].present?
          scope = scope.where(
            "(provenance->>'archived_at')::timestamptz < ?", predicate[:archived_before]
          )
        end

        Ai::BulkPredicateMutation.call(
          account: @account, scope: scope, dry_run: dry_run, actor: actor,
          action: "ai.knowledge.bulk_hard_delete", predicate: predicate,
          serializer: ->(e) { { id: e.id, title: e.title } }, log_tag: "[SharedKnowledge]"
        ) do |entry|
          entry.destroy!
          true
        end
      end

      private

      # ANDs every present predicate key. An absent/blank key is simply not
      # applied — this is the seam #archive_by_predicate! and
      # #hard_delete_archived! both extend, so a new predicate key is added
      # here once rather than in each caller.
      # IMP-3c9a6dc8f0a9 review round (blocker 3) — the keys this predicate
      # builder actually implements, PLUS :archived_before — applied by
      # #hard_delete_archived! itself, after this builder returns, never
      # inside it (see there) — included here so it validates as known
      # rather than raising on the one call site that legitimately uses it;
      # #archive_by_predicate! simply never reads it back out, so accepting
      # it there too is inert, not a widening. Anything else raises via
      # Ai::BulkPredicateMutation.validate_predicate! rather than being
      # silently ignored — see that method's header comment.
      KNOWLEDGE_PREDICATE_KEYS = %i[source_type content_type access_level tags imported_from created_before ids archived_before].freeze

      def build_knowledge_predicate_scope(predicate)
        Ai::BulkPredicateMutation.validate_predicate!(predicate, allowed_keys: KNOWLEDGE_PREDICATE_KEYS)

        scope = Ai::SharedKnowledge.where(account: @account)
        scope = scope.where(source_type: predicate[:source_type]) if predicate.key?(:source_type)
        scope = scope.where(content_type: predicate[:content_type]) if predicate.key?(:content_type)
        scope = scope.where(access_level: predicate[:access_level]) if predicate.key?(:access_level)
        if predicate.key?(:tags)
          # validate_predicate! only catches BLANK values — a wrong-typed
          # non-blank value (a String instead of an Array) passed that check
          # and then failed `.is_a?(Array)` silently, dropping the filter
          # entirely (the same widening blocker 3 exists to close). Checked
          # explicitly here instead.
          unless predicate[:tags].is_a?(Array)
            raise ArgumentError, "predicate[:tags] must be an Array, got #{predicate[:tags].class}: #{predicate[:tags].inspect}"
          end

          scope = scope.with_any_tags(predicate[:tags])
        end
        if predicate.key?(:imported_from)
          scope = scope.where("provenance->>'imported_from' = ?", predicate[:imported_from])
        end
        scope = scope.where("created_at < ?", predicate[:created_before]) if predicate.key?(:created_before)
        scope = scope.where(id: predicate[:ids]) if predicate.key?(:ids)
        scope
      end

      def find_entry!(entry_id)
        Ai::SharedKnowledge.find_by(id: entry_id, account: @account)
      end

      def entry_not_found(entry_id)
        { success: false, error: "Knowledge entry not found: #{entry_id}" }
      end

      def validate_content_type!(content_type)
        return if Ai::SharedKnowledge::CONTENT_TYPES.include?(content_type)

        raise ArgumentError, "Invalid content_type '#{content_type}'. Must be one of: #{Ai::SharedKnowledge::CONTENT_TYPES.join(', ')}"
      end

      def validate_access_level!(access_level)
        return if Ai::SharedKnowledge::ACCESS_LEVELS.include?(access_level)

        raise ArgumentError, "Invalid access_level '#{access_level}'. Must be one of: #{Ai::SharedKnowledge::ACCESS_LEVELS.join(', ')}"
      end

      def calculate_quality_score(content, tags, metadata)
        score = 0.5

        # Longer, more detailed content scores higher
        score += [content.to_s.length / 2000.0, 0.15].min

        # Having tags indicates well-organized content
        score += [tags.to_a.length * 0.03, 0.1].min

        # Having metadata indicates rich context
        score += [metadata.to_h.keys.length * 0.02, 0.1].min

        # Content with structure (headers, lists, code blocks) scores higher
        score += 0.05 if content.to_s.match?(/^#+\s/m)
        score += 0.05 if content.to_s.match?(/^[-*]\s/m)
        score += 0.05 if content.to_s.match?(/```/)

        [score.round(4), 1.0].min
      end

      # IMP-eddcbe102619: a search scoped to a "guidance-*" tag is the
      # MCP-first mandatory recall path (CLAUDE.md), where a silent empty
      # result is indistinguishable from "no guidance exists on this topic".
      def guidance_tag_search?(tags)
        Array(tags).any? { |t| t.to_s.start_with?("guidance") }
      end

      # ONE cheap COUNT aggregate on the canonical "guidance" tag every
      # GuidanceKnowledgeSeeder-created entry carries — never walk rows.
      def guidance_corpus_size
        Ai::SharedKnowledge.where(account: @account).not_archived.with_any_tags(["guidance"]).count
      end

      # Which physical knowledge store answered — distinguishes a bare/local
      # fixture DB from the production corpus without adding new config.
      def store_identifier
        ActiveRecord::Base.connection_db_config.database
      rescue StandardError
        "unknown"
      end

      def keyword_search(query, scope, limit)
        return scope.none if query.blank?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
        return scope.recent.limit(limit) if keywords.empty?

        where_clauses = []
        bind_values = []
        keywords.each do |kw|
          sanitized = Ai::SharedKnowledge.sanitize_sql_like(kw)
          where_clauses << "(LOWER(title) LIKE ? OR LOWER(content) LIKE ?)"
          bind_values.push("%#{sanitized}%", "%#{sanitized}%")
        end

        scope.where(where_clauses.join(" OR "), *bind_values).recent.limit(limit)
      end

      def map_learning_to_content_type(category)
        case category
        when "pattern", "anti_pattern", "best_practice"
          "procedure"
        when "fact", "discovery"
          "fact"
        when "failure_mode"
          "snippet"
        when "performance_insight"
          "text"
        else
          "text"
        end
      end

      def freshness_indicator(updated_at)
        return "stale" unless updated_at

        age_days = (Time.current - updated_at) / 1.day
        if age_days < 7
          "fresh"
        elsif age_days < 30
          "aging"
        else
          "stale"
        end
      end

      def serialize_entry(entry)
        {
          id: entry.id,
          title: entry.title,
          content: entry.content,
          content_type: entry.content_type,
          access_level: entry.access_level,
          tags: entry.tags,
          provenance: entry.provenance,
          source_type: entry.source_type,
          quality_score: entry.quality_score,
          usage_count: entry.usage_count,
          last_used_at: entry.last_used_at&.iso8601,
          integrity_verified: entry.verify_integrity!,
          created_at: entry.created_at&.iso8601,
          updated_at: entry.updated_at&.iso8601
        }
      end
    end
  end
end
