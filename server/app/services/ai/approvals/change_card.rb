# frozen_string_literal: true

module Ai
  module Approvals
    # The structured "what exactly am I approving" block on a parked tool-call
    # request's card: the exact tool and action, the target, the NEW value and,
    # where the tool can show it to this viewer, the CURRENT value. Read from the
    # request's REDACTED request_data (Ai::SensitiveParams), never from the
    # operation's own params and never rendered into the free-text description,
    # which is where a value would escape the redaction.
    #
    # The tool answers for itself (Ai::Tools::BaseTool.approval_change_card,
    # nil by default), so this names no tool. The class it resolves is bounded to
    # the chokepoint's own hierarchy, as Ai::Executors::DeferredToolCall bounds
    # its replay: a name off a JSONB column is looked up, never called.
    #
    # THE DIGEST (IMP-1765f6f09458). A card that carries the current value also
    # carries `digest`: a versioned SHA-256 over exactly (tool, action, key, new
    # value, whether the setting is set, current value) as rendered. The approve
    # door recomputes it for the decider's own session at decide time and
    # refuses on a mismatch, so a decision binds to what the person SAW — a
    # setting that changed, or was unset, between viewing and approving is never
    # approved blind. The client echoes the digest the server rendered and never
    # computes one; the server's recomputation is the only one that counts. It
    # is not an authenticator (a client that recomputes it from freshly fetched
    # values has, by construction, viewed those values), so it carries no key.
    #
    # NO digest on a card whose viewer is not shown the current value: a digest
    # over a withheld boolean is a two-guess oracle for it, and the decision
    # door treats such a card as undecidable from that session instead.
    module ChangeCard
      DIGEST_VERSION = "v1"
      DIGEST_FIELDS = %i[tool action key new_value current_value_set current_value].freeze

      module_function

      # nil for anything that is not a pending parked tool call whose tool offers a card.
      def for(request, viewer:)
        return nil unless request.pending?
        return nil unless request.request_data.to_h.with_indifferent_access[:executor_class].to_s == ::Ai::Executors::DeferredToolCall.name

        params = ::Ai::SensitiveParams.filter(request.request_data.to_h).with_indifferent_access[:params]
        return nil unless params.is_a?(Hash)

        klass = params[:tool_class].to_s.safe_constantize
        return nil unless klass.is_a?(Class) && klass < ::Ai::Tools::BaseTool

        card = klass.approval_change_card(action: params[:action].to_s, tool_params: params[:tool_params], viewer: viewer)
        return card unless card.is_a?(Hash) && card.key?(:current_value_set)

        card.merge(digest: digest(card))
      end

      # The canonical form is a fixed-order JSON array of the card's own values:
      # deterministic for equal values, no hash-key order involved. A
      # presenter's rendering is NOT part of it (it describes the values; it is
      # not what gets written).
      def digest(card)
        canonical = JSON.generate([ DIGEST_VERSION, *DIGEST_FIELDS.map { |field| card[field] } ])
        "#{DIGEST_VERSION}:#{Digest::SHA256.hexdigest(canonical)}"
      end

      # Constant-time. A card without a digest (its viewer is not shown the
      # current value) matches nothing; a non-string claim matches nothing.
      def digest_matches?(card, claimed)
        expected = card.is_a?(Hash) ? card[:digest] : nil
        return false unless expected.is_a?(String) && claimed.is_a?(String)

        ::ActiveSupport::SecurityUtils.secure_compare(expected, claimed)
      end
    end
  end
end
