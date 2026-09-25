# frozen_string_literal: true

module Ai
  # Append-only request history for a concierge conversation.
  #
  # A turn's live context covers missions, repos, teams, workspace members, and
  # the router's override for that one question. It is FROZEN onto the user
  # message it was first sent with (processing_metadata["turn_context"]) and
  # replayed from there on every later request. It is never rebuilt from current
  # state. An earlier turn therefore renders byte-identically on every request,
  # which keeps the prompt cache warm and leaves intact the prefix that preserved
  # thinking is bound to.
  #
  # The context rides as a system message directly after its user turn. The LLM
  # builders place it: natively where the model supports mid-conversation system
  # messages, otherwise as a reminder on that user turn.
  class ConciergeHistory
    TURN_CONTEXT_KEY = "turn_context"

    def initialize(conversation)
      @conversation = conversation
    end

    # Freezes the context for the latest user message. Write-once: a turn that
    # already carries context keeps it, so a retry replays the same bytes.
    # update_columns keeps this out of the message's broadcast/versioning
    # callbacks, since it is request bookkeeping and not a user-visible edit.
    def freeze_turn_context!(text)
      message = latest_user_message
      return if message.nil? || text.blank?
      return if (message.processing_metadata || {}).key?(TURN_CONTEXT_KEY)

      message.update_columns(processing_metadata: (message.processing_metadata || {}).merge(TURN_CONTEXT_KEY => text))
    end

    # The frozen context of the latest user turn, or nil.
    def current_turn_context
      latest_user_message&.processing_metadata&.dig(TURN_CONTEXT_KEY)
    end

    # The persisted history as request messages, each user turn followed by its
    # frozen context.
    def messages(limit: nil)
      rows = @conversation.messages.not_deleted.ordered
      rows = rows.last(limit) if limit
      rows.flat_map do |row|
        entry = { role: row.role, content: row.content }
        context = row.role == "user" ? row.processing_metadata&.dig(TURN_CONTEXT_KEY) : nil
        context.present? ? [ entry, { role: "system", content: context } ] : [ entry ]
      end
    end

    private

    def latest_user_message
      @conversation.messages.not_deleted.where(role: "user").ordered.last
    end
  end
end
