# frozen_string_literal: true

module Ai
  module DataSources
    # Incremental-sync cursor plumbing for the pull-based monitor loop (Phase 5).
    #
    # A data-source endpoint opts into incremental sync via its +incremental+ jsonb
    # config (Ai::DataSourceEndpoint#incremental?):
    #
    #   {
    #     "cursor_param" => "since",          # outbound query/body param carrying the cursor
    #     "cursor_path"  => "provenance.next" # dotted path to the NEXT cursor in the response
    #     "mode"         => "cursor"          # "cursor" | "timestamp" (advisory; both dig the path)
    #   }
    #
    # The flow, driven by Ai::DataSources::MonitorService#poll_subscription:
    #
    #   1. BEFORE the fetch: when the subscription already holds a sync_cursor,
    #      +apply_cursor+ stamps it onto the outbound params under cursor_param so
    #      the upstream only returns rows newer than the high-watermark.
    #   2. AFTER a successful fetch: +extract_cursor+ digs the next watermark out of
    #      the FetchEnvelope (provenance first, then the canonical records) via
    #      cursor_path; MonitorService persists it through record_poll!(cursor:).
    #
    # OFF by default: with a blank incremental config (or a blank cursor) both
    # helpers no-op (apply_cursor returns the params unchanged; extract_cursor
    # returns nil), so the non-incremental poll path is byte-for-byte unchanged.
    #
    # Pure/stateless — no network, no persistence, no Redis — so it stays trivially
    # unit-testable in isolation from the monitor loop.
    module IncrementalSync
      module_function

      # Stamp the high-watermark cursor onto the outbound fetch params.
      #
      #   apply_cursor(params, incremental_config, cursor) -> params (a copy)
      #
      # Returns a SHALLOW COPY of params with params[cursor_param] = cursor when
      # both an incremental config (with a cursor_param) and a non-blank cursor are
      # present; otherwise returns params unchanged (a copy, never the caller's
      # object mutated in place). String-keyed so it composes with the
      # string-keyed param maps QueryService/Paginator build.
      def apply_cursor(params, incremental_config, cursor)
        # .to_h returns SELF for a plain Hash, so .dup is required to honor the
        # documented "returns a copy, never the caller's object" contract on the
        # early-return (blank cursor / no cursor_param) paths — the merge path
        # below already yields a fresh object.
        base = (params || {}).to_h.dup
        return base if cursor.blank?

        cursor_param = cursor_param_for(incremental_config)
        return base if cursor_param.blank?

        base.merge(cursor_param => cursor)
      end

      # Pull the NEXT cursor out of a completed FetchEnvelope.
      #
      #   extract_cursor(envelope, incremental_config) -> next_cursor | nil
      #
      # Digs incremental_config["cursor_path"] (a dotted path RELATIVE to the
      # container — e.g. "paging.next" or "0.updated_at", NOT prefixed with
      # "provenance"/"data") first against the envelope provenance, then against
      # the envelope data (the canonical records). Returns
      # the first non-blank scalar found, or nil when nothing resolves. nil leaves
      # the existing watermark untouched downstream (record_poll! ignores a blank
      # cursor:), so a response that omits the cursor never clobbers progress.
      def extract_cursor(envelope, incremental_config)
        return nil unless envelope.is_a?(Hash)

        provenance = envelope[:provenance] || envelope["provenance"]
        # Prefer the upstream cursor QueryService already dug from the RAW response
        # body at fetch time (records_path unwrap discards top-level paging tokens
        # like meta.next_cursor, so they are unreachable from the records). See
        # cursor_from_body — QueryService stashes the result at "incremental_cursor".
        pre = dig_path(provenance, ["incremental_cursor"])
        return normalize_cursor(pre) if pre.present?

        path = cursor_path_for(incremental_config)
        return nil if path.blank?

        keys = split_path(path)
        return nil if keys.empty?

        # Fall back to the configured path: provenance first, then the canonical
        # records (a cursor carried inline on the data, e.g. last row's updated_at).
        from_provenance = dig_path(provenance, keys)
        return normalize_cursor(from_provenance) if from_provenance.present?

        data = envelope[:data] || envelope["data"]
        normalize_cursor(dig_path(data, keys))
      end

      # Extract the next cursor directly from the RAW (pre-records-unwrap) response
      # body. QueryService calls this at fetch time and stashes the result into
      # provenance["incremental_cursor"], because the JSON decoder's records_path
      # unwrap discards top-level paging tokens (e.g. {"meta":{"next":...},"items":[]})
      # that would otherwise never reach the FetchEnvelope. Returns nil for non-JSON
      # bodies / a missing path, so timestamp-mode (record-embedded) sources still
      # fall through to the records-based extract_cursor path unchanged.
      def cursor_from_body(raw_body, incremental_config)
        path = cursor_path_for(incremental_config)
        return nil if path.blank? || raw_body.blank?

        body =
          begin
            JSON.parse(raw_body)
          rescue StandardError
            nil
          end
        return nil unless body

        normalize_cursor(dig_path(body, split_path(path)))
      end

      # ----------------------------------------------------------------------
      # internals
      # ----------------------------------------------------------------------

      def cursor_param_for(config)
        cfg = config_hash(config)
        (cfg["cursor_param"] || cfg[:cursor_param]).to_s.strip.presence
      end
      private_class_method :cursor_param_for

      def cursor_path_for(config)
        cfg = config_hash(config)
        (cfg["cursor_path"] || cfg[:cursor_path]).to_s.strip.presence
      end
      private_class_method :cursor_path_for

      def config_hash(config)
        config.is_a?(Hash) ? config : {}
      end
      private_class_method :config_hash

      # Split a dotted path into segments. Blank segments (e.g. a trailing dot) are
      # dropped so "a..b" / "a." degrade gracefully rather than digging a "" key.
      def split_path(path)
        path.to_s.split(".").map(&:strip).reject(&:empty?)
      end
      private_class_method :split_path

      # Walk a nested Hash/Array by string OR symbol key (hashes) and by integer
      # index (arrays), tolerating either key flavor at each hop. Returns nil the
      # moment a hop cannot resolve, so a malformed path never raises.
      def dig_path(object, keys)
        keys.reduce(object) do |node, key|
          break nil if node.nil?

          case node
          when Hash
            if node.key?(key)
              node[key]
            elsif node.key?(key.to_sym)
              node[key.to_sym]
            else
              node[key.to_s]
            end
          when Array
            idx = array_index(key)
            idx.nil? ? nil : node[idx]
          else
            nil
          end
        end
      rescue StandardError
        nil
      end
      private_class_method :dig_path

      # Coerce a path segment to an Array index (supports negative indexes), or nil
      # when the segment is not an integer (so a non-numeric key against an Array
      # resolves to "no match" instead of raising).
      def array_index(key)
        Integer(key.to_s, 10)
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :array_index

      # A cursor must persist into a string column (sync_cursor). Pass scalars
      # through as-is (stringified); reject containers — a Hash/Array is never a
      # valid high-watermark token.
      def normalize_cursor(value)
        return nil if value.nil?
        return nil if value.is_a?(Hash) || value.is_a?(Array)

        str = value.to_s
        str.empty? ? nil : str
      end
      private_class_method :normalize_cursor
    end
  end
end
