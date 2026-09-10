# frozen_string_literal: true

module Platform
  module Runbook
    # SIGNAL KIND → WHAT AN OPERATOR SHOULD READ (design §5.2).
    #
    # Two ways in, because there are two kinds of answer:
    #
    #   register_source(callable)   a CATALOG. The callable answers
    #                               `for(signal_kind)` and returns an entry hash
    #                               or nil. The system extension registers its
    #                               runbooks.yml catalog this way from
    #                               `to_prepare`; core never names it.
    #
    #   register(kind, entry)       ONE core-owned binding, for a kind core
    #                               itself owns and no extension catalog will
    #                               ever list — typically a GENERATOR
    #                               ({generator: "<executor class name>", args:})
    #                               rather than a document.
    #
    # ── RESOLUTION ORDER: SOURCES FIRST, THEN CORE ENTRIES ──────────────────
    # Sources are walked in registration order and the first non-nil entry
    # wins; only if every source declines does #for fall through to the
    # explicitly registered entries.
    #
    # That ordering follows ownership. The signal kinds belong to whoever
    # emits them, so whoever emits them also owns the mapping, and a catalog
    # that has an opinion about a kind is a more specific statement than
    # core's fallback. The inverse order would let a core default silently
    # shadow the extension's own answer for a kind core does not own — the
    # failure mode being that someone updates the YAML, nothing changes on the
    # screen, and the reason is invisible.
    #
    # ── "UNKNOWN" AND "DELIBERATELY UNDOCUMENTED" ARE DIFFERENT ANSWERS ─────
    # A catalog entry `{not_documented: true, reason: "..."}` means somebody
    # looked and decided there is nothing to point at. No entry at all means
    # nobody has decided. #render keeps them apart with `known:` — collapsing
    # them would turn a coverage gap into a closed question, which is exactly
    # the shape that lets an unwritten runbook look finished.
    module Registry
      MUTEX = Mutex.new
      private_constant :MUTEX

      # Every key an entry may carry, after normalization. An unrecognised key
      # is dropped rather than passed on: entries reach the operator drawer,
      # and a typo'd `not_documeted: true` must not travel as opaque payload
      # that some renderer later reads as truth.
      ENTRY_KEYS = %w[doc not_documented reason generator args].freeze

      DOC       = "doc"
      GENERATOR = "generator"
      NONE      = "none"

      class << self
        # @param source [#for] answers `for(signal_kind)` with an entry hash or nil
        def register_source(source)
          raise ArgumentError, "source must respond to #for" unless source.respond_to?(:for)

          MUTEX.synchronize do
            sources.delete(source)
            sources << source
          end
          source
        end

        def unregister_source(source)
          MUTEX.synchronize { sources.delete(source) }
        end

        def registered_sources
          MUTEX.synchronize { sources.dup.freeze }
        end

        # A core-owned binding for ONE kind.
        # @param entry [Hash] {generator:, args:} or {doc:} or
        #   {not_documented: true, reason:}
        def register(signal_kind, entry)
          key = normalize_kind(signal_kind)
          raise ArgumentError, "signal_kind must be present" if key.blank?

          normalized = normalize_entry(entry)
          raise ArgumentError, "entry must be a Hash with at least one of #{ENTRY_KEYS.join(', ')}" if normalized.blank?

          MUTEX.synchronize { entries[key] = normalized }
          normalized
        end

        def unregister(signal_kind)
          MUTEX.synchronize { entries.delete(normalize_kind(signal_kind)) }
        end

        def registered_entries
          MUTEX.synchronize { entries.dup.freeze }
        end

        # The raw normalized entry for a kind, or nil when nothing claims it.
        #
        # A source that RAISES is logged and skipped rather than allowed to
        # take down the front door: a runbook lookup is decoration on a
        # remediation report, and a catalog that fails to parse must not make
        # the component's status unreadable.
        def for(signal_kind)
          key = normalize_kind(signal_kind)
          return nil if key.blank?

          registered_sources.each do |source|
            entry = safe_source_lookup(source, key)
            return entry if entry.present?
          end

          registered_entries[key]
        end

        # `key?` rather than `.present?`, matching the extension catalog's own
        # `documented?`. The two are equivalent here because #normalize_entry
        # drops a blank `doc` before it can be stored — see the note there.
        def documented?(signal_kind)
          self.for(signal_kind)&.key?(DOC) || false
        end

        # WHAT THE DRAWER RENDERS. Always a Hash, always carrying `kind`.
        #
        #   {kind: "doc",       doc:, path:, anchor:}
        #   {kind: "generator", generator:, args:}
        #   {kind: "none",      known:, reason:}
        #
        # `path` and `anchor` are split from `doc` here so the renderer does
        # not each re-derive the split; `path` is left exactly as the catalog
        # wrote it (extension-relative), because core does not know which
        # checkout it belongs to and must not manufacture an absolute one.
        def render(signal_kind)
          entry = self.for(signal_kind)
          return { kind: NONE, known: false, reason: "NotRegistered" } if entry.nil?

          if entry[DOC].present?
            path, anchor = entry[DOC].to_s.split("#", 2)
            { kind: DOC, doc: entry[DOC].to_s, path: path, anchor: anchor }
          elsif entry[GENERATOR].present?
            { kind: GENERATOR, generator: entry[GENERATOR].to_s, args: entry["args"] || {} }
          else
            { kind: NONE, known: true, reason: entry["reason"].presence || "NotDocumented" }
          end
        end

        # Spec seam. Never call this from application code.
        def reset!
          MUTEX.synchronize do
            sources.clear
            entries.clear
          end
        end

        private

        def safe_source_lookup(source, key)
          normalize_entry(source.for(key))
        rescue StandardError => e
          Rails.logger.error(
            "[Platform::Runbook::Registry] source #{source.class} raised for #{key}: #{e.class}: #{e.message}"
          )
          nil
        end

        # String keys throughout, because half the entries arrive from YAML
        # (string-keyed) and half from Ruby call sites (symbol-keyed), and a
        # registry that answers differently depending on which is a registry
        # with two behaviours.
        # ONE RULE FOR A BLANK `doc`: it is not a doc entry, so the key does
        # not survive normalization.
        #
        # Without that rule the two readers disagreed. `documented?` asks
        # `key?("doc")` — mirroring the extension catalog's own predicate — and
        # `render` asks `entry["doc"].present?`, so an entry of
        # `{"doc" => nil}` reported documented while rendering as `none`. Worse,
        # such an entry is `.presence`-truthy, so `for` accepted it and STOPPED
        # WALKING, shadowing a later source that had a real path. Dropping the
        # key at the door makes both readers agree by construction and lets the
        # walk continue, rather than teaching each reader the same exception.
        def normalize_entry(entry)
          return nil unless entry.is_a?(Hash)

          entry.each_with_object({}) do |(k, v), out|
            key = k.to_s
            next unless ENTRY_KEYS.include?(key)
            next if key == DOC && v.blank?

            out[key] = v
          end.presence
        end

        def normalize_kind(signal_kind)
          signal_kind.to_s.strip
        end

        def sources
          @sources ||= []
        end

        def entries
          @entries ||= {}
        end
      end
    end
  end
end
