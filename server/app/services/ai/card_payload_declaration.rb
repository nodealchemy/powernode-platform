# frozen_string_literal: true

module Ai
  # A per-tool declaration of what may be copied out of a tool result and into a
  # chat card.
  #
  # WHY THIS EXISTS (IMP-6af3dc79efb3). A chat card is not a transient view.
  # Ai::AgentToolBridgeService collects cards for every tool in its CARD_TOOLS
  # map and Ai::ConciergeService writes them straight into
  # ai_messages.content_metadata — a jsonb column, durable, never re-filtered on
  # read. Ai::SensitiveParams cannot intervene: the card payload is not routed
  # through #filter, and #filter returns non-Hash input unchanged anyway. Before
  # this class, `card_payload_from_result` returned `result[:data]` verbatim, so
  # adding one line to CARD_TOOLS silently enrolled a tool's ENTIRE result
  # payload into permanent at-rest storage. That is how a plaintext federation
  # acceptance token reached the column (IMP-c0687cfb3a05).
  #
  # THE MECHANISM IS PROJECTION, NOT PATTERN MATCHING. Nothing here inspects key
  # names for "token" / "secret" / "key". A key-name denylist was rejected as a
  # fix for exactly this class of leak (2026-08-15): it protects only against
  # material whose producer happened to name it honestly, and it fails silently
  # for everything else. Here the default is DENY — a key the author did not
  # write down does not reach the column, whatever it is called. Adding a
  # capability to a payload is therefore a visible edit to this declaration and
  # not an invisible consequence of a producer's change.
  #
  # DECLARATION GRAMMAR. `fields` is a non-empty array whose entries are either:
  #
  #   "phase"                        copy result[:data]["phase"] as-is
  #   { "plan" => %w[id dag cost] }  recurse: copy only those keys of the nested
  #                                  hash; if the value is an array, project
  #                                  every hash element and drop non-hashes
  #
  # A nested declaration is how a subtree gets bounded. A bare key asserts the
  # whole value is card-safe, so prefer the nested form whenever the value is a
  # structure a producer can grow.
  class CardPayloadDeclaration
    # Raised when CARD_TOOLS carries an entry that is not a valid declaration —
    # at class load, so a tool added without one cannot reach production, and
    # again at dispatch, so a runtime-substituted map cannot either.
    class UndeclaredCardPayload < StandardError; end

    # Hard ceiling on the serialized card payload. Projection already bounds
    # WHAT is stored; this bounds HOW MUCH, so a declared-but-growing collection
    # (a plan DAG, a volume list) cannot write an unbounded row. Over the limit
    # the card carries a marker instead of the payload.
    #
    # What the operator then sees depends on the kind, and none of it is good:
    # PlatformDeploymentWizardCard renders its "unrecognized payload" fallback,
    # the brief/plan kinds return null and the card disappears from the thread
    # entirely, and the status/adaptation kinds render their hardcoded default
    # strings — a card that looks normal but carries nothing. The marker exists
    # to bound the ROW, not to communicate; the warn line below is the signal.
    #
    # Per CARD, not per message: Ai::AgentToolBridgeService appends one card per
    # qualifying tool call across every loop iteration, so a single message can
    # still carry several of these.
    MAX_PAYLOAD_BYTES = 32.kilobytes

    attr_reader :kind, :fields

    # @param kind [String] frontend renderer selector (ChatCardKind)
    # @param fields [Array<String, Hash>] see DECLARATION GRAMMAR above
    def initialize(kind:, fields:)
      raise UndeclaredCardPayload, "card declaration needs a non-blank kind" if kind.to_s.strip.empty?

      unless fields.is_a?(Array) && fields.any?
        raise UndeclaredCardPayload,
              "card declaration for kind #{kind.inspect} must declare a non-empty `fields` allowlist — " \
              "the card payload is persisted to ai_messages.content_metadata, so there is no " \
              "safe default of 'send everything'"
      end

      @kind   = kind.to_s.freeze
      @fields = self.class.normalize_fields(fields, kind).freeze
      freeze
    end

    # Project a tool result's data hash down to the declared keys.
    # Returns nil when nothing was declared-and-present, so the caller emits no
    # card at all rather than an empty one.
    def project(data)
      return nil unless data.is_a?(Hash)

      projected = self.class.project_fields(data, @fields)
      return nil if projected.empty?

      bytes = projected.to_json.bytesize
      if bytes > MAX_PAYLOAD_BYTES
        Rails.logger.warn(
          "[CardPayloadDeclaration] #{@kind} payload #{bytes}B exceeds #{MAX_PAYLOAD_BYTES}B — omitting"
        )
        return { "card_payload_omitted" => true, "reason" => "payload_too_large", "bytes" => bytes }
      end

      projected
    end

    # Validate a whole CARD_TOOLS map. Called from the class body of
    # Ai::AgentToolBridgeService so an entry without a declaration raises during
    # eager load — the app refuses to boot rather than starting with a silent
    # sink. Public and map-taking so the guard can be exercised directly.
    def self.validate_map!(map)
      unless map.is_a?(Hash) && map.any?
        raise UndeclaredCardPayload, "CARD_TOOLS must be a non-empty Hash, got #{map.class}"
      end

      map.each do |tool_name, spec|
        next if spec.is_a?(self)

        raise UndeclaredCardPayload,
              "CARD_TOOLS entry #{tool_name.inspect} is a #{spec.class}, not an " \
              "#{name}. Every card tool must declare which keys of its result " \
              "payload are card-safe: the card is copied into " \
              "ai_messages.content_metadata and kept there in the clear. " \
              "Replace it with #{name}.new(kind: \"...\", fields: %w[...])."
      end

      map
    end

    # @api private
    #
    # Deep-freezes as it builds. A shallow freeze would leave the nested arrays
    # and hashes writable through the public #fields reader, which is the one
    # seam where "by construction" would have been skin-deep.
    def self.normalize_fields(fields, kind)
      seen = {}

      normalized = fields.map do |field|
        case field
        when String, Symbol
          claim_key!(seen, field.to_s, kind)
        when Hash
          if field.size != 1
            raise UndeclaredCardPayload,
                  "nested field declaration for kind #{kind.inspect} must be a single " \
                  "{ key => [subkeys] } pair, got #{field.inspect}"
          end
          key, subfields = field.first
          unless subfields.is_a?(Array) && subfields.any?
            raise UndeclaredCardPayload,
                  "nested field #{key.inspect} for kind #{kind.inspect} must declare a " \
                  "non-empty subkey allowlist"
          end
          { claim_key!(seen, key.to_s, kind) => normalize_fields(subfields, kind) }.freeze
        else
          raise UndeclaredCardPayload,
                "field declaration for kind #{kind.inspect} must be a key or a " \
                "{ key => [subkeys] } pair, got #{field.inspect}"
        end
      end

      normalized.freeze
    end

    # Declaring the same key twice is refused rather than resolved. #project_fields
    # assigns in order, so `[{ "gate" => %w[disposition] }, "gate"]` would let the
    # bare entry overwrite the nested one and copy the whole subtree — a
    # declaration that READS as bounded while behaving as "send everything". That
    # is the only way to defeat the projection without editing the projector.
    def self.claim_key!(seen, key, kind)
      if seen.key?(key)
        raise UndeclaredCardPayload,
              "field #{key.inspect} is declared twice at the same level for kind " \
              "#{kind.inspect}; the later declaration would silently overwrite the earlier"
      end

      seen[key] = true
      key
    end
    private_class_method :claim_key!

    # @api private
    def self.project_fields(data, fields)
      out = {}

      fields.each do |field|
        if field.is_a?(Hash)
          key, subfields = field.first
          value = fetch_key(data, key)
          next if value.nil?

          # A scalar under a key declared as a subtree is NOT waved through:
          # the declaration says "these subkeys of a structure", and a producer
          # that swapped the structure for something else has not been vouched
          # for. Dropped rather than copied.
          projected = project_value(value, subfields)
          next if projected.nil?

          out[key] = projected
        else
          next unless key?(data, field)

          out[field] = fetch_key(data, field)
        end
      end

      out
    end

    def self.project_value(value, subfields)
      case value
      when Hash  then project_fields(value, subfields)
      when Array then value.grep(Hash).map { |element| project_fields(element, subfields) }
      else nil
      end
    end
    private_class_method :project_value

    # Tool results arrive with symbol keys from Ruby producers and string keys
    # once they have round-tripped through JSON. Declarations are written once,
    # in strings.
    def self.key?(data, key)
      data.key?(key) || data.key?(key.to_sym)
    end
    private_class_method :key?

    def self.fetch_key(data, key)
      data.key?(key) ? data[key] : data[key.to_sym]
    end
    private_class_method :fetch_key
  end
end
