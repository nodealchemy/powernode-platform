# frozen_string_literal: true

module Ai
  module DataSources
    # Deterministic, stateless multi-source RECONCILIATION over canonical records.
    #
    # PURPOSE
    #   The QueryService fetch path returns a FetchEnvelope per (data_source,
    #   endpoint). When the SAME logical entity is served by several endpoints or
    #   several sources (a primary + mirrors, or complementary feeds), a caller
    #   ends up with N independent Array<Hash> record sets that overlap on a shared
    #   canonical KEY. This service collapses those sets into ONE list by exact key
    #   match, per a fixed merge strategy. It is the deterministic "canonical-key
    #   merge" half of the multi-source long-tail.
    #
    # HARD NON-GOALS (intentionally NOT done here)
    #   * NO cross-source SQL / join engine — this is an in-memory key group/collapse,
    #     not a relational join. No predicate pushdown, no query plan.
    #   * NO query-plan IR.
    #   * NO probabilistic / fuzzy entity resolution — records are matched ONLY by an
    #     EXACT (string-coerced) value of the canonical key field. Two records with
    #     "Acme" and "ACME" are DIFFERENT keys; we never guess they are the same.
    #   * NO migration FSM.
    #   Reconciliation == deterministic canonical-key merge, nothing more.
    #
    # STRATEGIES (how a group of same-key records collapses to one)
    #   * "first_wins"  — keep the FIRST record seen for the key (earliest set,
    #                     earliest index). Later duplicates are discarded.
    #   * "last_wins"   — keep the LAST record seen for the key. Each later duplicate
    #                     wholly REPLACES the prior winner. (DEFAULT.)
    #   * "merge"       — shallow field-merge: start from the first record, then for
    #                     each later same-key record overlay its NON-NIL fields on top
    #                     (later non-nil wins per field; earlier values survive where
    #                     the later record is nil/absent). One level deep only — nested
    #                     Hashes are replaced wholesale, never deep-merged.
    #
    # KEY SEMANTICS
    #   * The key field name is supplied at construction (e.g. "id", "isbn", "key").
    #   * Lookups are string/symbol tolerant: a record may carry the key under a
    #     String or Symbol key; the GROUPING value is the key field's value coerced
    #     to a String so 1 (Integer) and "1" (String) reconcile together — exact
    #     match on the canonical string form, never fuzzy.
    #   * Records MISSING the key entirely (no String and no Symbol key field, or a
    #     nil value) are NOT dropped: they pass through UNMERGED in first-appearance
    #     order, each flagged via UNRECONCILED_FLAG so a caller can tell a passed-
    #     through record from a reconciled one. They never collide with each other.
    #
    # ORDER & BOUNDS
    #   * Output order is STABLE: the FIRST appearance of each distinct key fixes its
    #     slot, regardless of strategy (so "last_wins" keeps the winner in the key's
    #     original position, it does not move to the end). Keyless pass-throughs hold
    #     their own first-appearance slots interleaved with keyed groups.
    #   * Bounded: at most MAX_OUTPUT records are emitted; once the cap is hit we stop
    #     admitting NEW distinct keys / new keyless rows (updates to already-admitted
    #     keys still apply) and log once that the result was capped.
    #
    # PURITY
    #   Pure and stateless: #reconcile does not mutate its inputs (winners are shallow-
    #   duped before in-place merge), touches no DB, no network, no Redis, no clock.
    #   The same inputs always yield the same output. Safe to call inline on a request.
    #
    # CONTRACT
    #   Ai::DataSources::ReconciliationService
    #     .new(key:, strategy: "last_wins")
    #     #reconcile(record_sets) => Array<Hash>     # record_sets : Array<Array<Hash>>
    class ReconciliationService
      FIRST_WINS = "first_wins"
      LAST_WINS  = "last_wins"
      MERGE      = "merge"
      STRATEGIES = [FIRST_WINS, LAST_WINS, MERGE].freeze
      DEFAULT_STRATEGY = LAST_WINS

      # Hard ceiling on emitted records so a pathological fan-in (many large sets)
      # cannot blow up memory. The merge stays correct for already-admitted keys;
      # only NEW distinct keys / keyless rows beyond the cap are dropped.
      MAX_OUTPUT = 100_000

      # Marker injected onto a record that lacked the canonical key and was therefore
      # passed through without participating in any merge group.
      UNRECONCILED_FLAG = "_unreconciled"

      # @param key [String, Symbol] the canonical key field name shared across sets.
      # @param strategy [String] one of STRATEGIES; anything else falls back to
      #   DEFAULT_STRATEGY ("last_wins") rather than raising, so a bad config degrades.
      def initialize(key:, strategy: DEFAULT_STRATEGY)
        @key = key.to_s
        requested = strategy.to_s.strip.downcase
        @strategy = STRATEGIES.include?(requested) ? requested : DEFAULT_STRATEGY
        if requested != @strategy
          Rails.logger.warn(
            "[DataSources::ReconciliationService] unknown strategy #{strategy.inspect}, " \
            "falling back to #{DEFAULT_STRATEGY}"
          )
        end
      end

      # Collapse Array<Array<Hash>> into a single Array<Hash> by exact canonical key.
      #
      # Walks every set in order, every record in order, and:
      #   * keyless records -> appended as flagged pass-throughs (first-appearance order)
      #   * keyed records   -> grouped by string-coerced key value; the FIRST sighting
      #     fixes the output slot, subsequent sightings update the winner per strategy.
      #
      # Returns a NEW Array of NEW/duped Hashes — inputs are never mutated. Never
      # raises on a malformed element (non-Hash entries are skipped defensively).
      def reconcile(record_sets)
        return [] if record_sets.blank?

        # Insertion-ordered registry of keyed winners: canonical_key => slot index in
        # `slots`. `slots` holds either a winning Hash (keyed) or a flagged keyless
        # Hash, preserving global first-appearance order across both kinds.
        keyed_slot_index = {}
        slots = []
        capped = false

        each_record(record_sets) do |record|
          key_value = canonical_key_value(record)

          if key_value.nil?
            # Keyless: pass through, flagged, in first-appearance order. Subject to
            # the same output cap as new keys.
            if slots.size >= MAX_OUTPUT
              capped = true
              next
            end
            slots << flag_unreconciled(record)
            next
          end

          if (idx = keyed_slot_index[key_value])
            # Seen this key before: collapse the existing winner with this record.
            # Updates to an ALREADY-ADMITTED key are always honored (no cap check) so
            # the cap never produces a partially-merged winner.
            slots[idx] = collapse(slots[idx], record)
          else
            # First sighting of this key: admit it (subject to the cap) and remember
            # its slot so later duplicates land in the same position.
            if slots.size >= MAX_OUTPUT
              capped = true
              next
            end
            slots << seed_winner(record)
            keyed_slot_index[key_value] = slots.size - 1
          end
        end

        if capped
          Rails.logger.warn(
            "[DataSources::ReconciliationService] output capped at #{MAX_OUTPUT} records " \
            "(key=#{@key}, strategy=#{@strategy})"
          )
        end

        slots
      rescue StandardError => e
        # Resilient: a reconciliation fault must not break the caller's request. Log
        # the class (never record contents) and degrade to a flat, de-nested pass-
        # through of all input records so the caller still gets data.
        Rails.logger.error(
          "[DataSources::ReconciliationService] reconcile error (#{e.class}); passing records through"
        )
        flatten_passthrough(record_sets)
      end

      private

      attr_reader :key, :strategy

      # Iterate every Hash record across every set, in set-then-index order. Non-Array
      # sets and non-Hash records are skipped defensively (a malformed element must
      # not abort the whole reconcile).
      def each_record(record_sets)
        Array(record_sets).each do |set|
          next unless set.is_a?(Array)

          set.each do |record|
            next unless record.is_a?(Hash)

            yield record
          end
        end
      end

      # The canonical grouping value for a record: the key field's value (String OR
      # Symbol key tolerated) coerced to a String. Returns nil when the field is
      # absent or nil, marking the record as keyless (pass-through). An empty-string
      # value is a REAL key (""), distinct from absent — only nil/absent is keyless.
      def canonical_key_value(record)
        raw =
          if record.key?(@key)
            record[@key]
          elsif record.key?(@key.to_sym)
            record[@key.to_sym]
          end
        return nil if raw.nil?

        raw.to_s
      end

      # Produce the initial winner for a key's first sighting. For "merge" we dup so
      # later in-place overlays never mutate the caller's Hash; for first/last wins we
      # also dup so the returned winner is independent of the input (purity).
      def seed_winner(record)
        record.dup
      end

      # Collapse an existing winner with a newly-seen same-key record per strategy.
      #   first_wins -> keep the existing winner unchanged.
      #   last_wins  -> the new record (duped) wholly replaces the winner.
      #   merge      -> overlay the new record's NON-NIL fields onto a dup of the winner.
      def collapse(winner, incoming)
        case @strategy
        when FIRST_WINS
          winner
        when LAST_WINS
          incoming.dup
        when MERGE
          shallow_merge_non_nil(winner, incoming)
        else
          incoming.dup
        end
      end

      # Shallow merge: start from a dup of the winner and overlay every NON-NIL field
      # from `incoming`. Later non-nil values win per field; the winner's value
      # survives where incoming is nil or absent. One level deep — a nested Hash/Array
      # value is replaced wholesale (NOT deep-merged), which keeps the merge
      # deterministic and avoids any structural ambiguity.
      #
      # Key-spelling note: `incoming` may carry fields under String or Symbol keys
      # depending on the source. We overlay using each incoming field's OWN key
      # spelling, so we do not silently rewrite the winner's key types; a field
      # present under both spellings is preserved as the source emitted it.
      def shallow_merge_non_nil(winner, incoming)
        # Stringify both sides' keys so a field present under different spellings
        # ("x" from one source, :x from another) overlays onto ONE key instead of
        # producing duplicate entries in the merged Hash.
        merged = stringify_keys(winner)
        stringify_keys(incoming).each do |field, value|
          next if value.nil?

          merged[field] = value
        end
        merged
      end

      def stringify_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      end

      # Tag a keyless record as an unreconciled pass-through (on a dup, never the
      # original). Tolerates a record that already uses Symbol keys by matching the
      # dominant key style so the flag is readable alongside the record's own fields.
      def flag_unreconciled(record)
        tagged = record.dup
        if symbol_keyed?(record)
          tagged[UNRECONCILED_FLAG.to_sym] = true
        else
          tagged[UNRECONCILED_FLAG] = true
        end
        tagged
      end

      # Heuristic: treat a record as symbol-keyed when it has at least one Symbol key
      # and no String keys, so the flag matches the record's convention. Mixed/Empty
      # records default to a String flag (the jsonb-canonical form).
      def symbol_keyed?(record)
        keys = record.keys
        return false if keys.empty?

        keys.any? { |k| k.is_a?(Symbol) } && keys.none? { |k| k.is_a?(String) }
      end

      # Degraded fallback used only when #reconcile itself raises: flatten all sets
      # into a single bounded Array of the (Hash) records, untouched and unflagged, so
      # the caller still receives every record we were handed.
      def flatten_passthrough(record_sets)
        out = []
        Array(record_sets).each do |set|
          next unless set.is_a?(Array)

          set.each do |record|
            next unless record.is_a?(Hash)
            break if out.size >= MAX_OUTPUT

            out << record
          end
          break if out.size >= MAX_OUTPUT
        end
        out
      rescue StandardError
        []
      end
    end
  end
end
