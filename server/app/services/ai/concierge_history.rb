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
  # The context rides as a turn-scoped system message (clear_at:
  # "next_user_message") directly after its user turn. It is only true for that
  # turn, so once a later user message exists it stays in the history cleared: it
  # costs no input tokens and is never deleted. The LLM builders place it natively,
  # with the beta the field needs, where the model supports mid-conversation system
  # messages. Elsewhere it becomes a reminder on that user turn, and earlier copies
  # stay in place.
  #
  # A long conversation is compacted, not windowed: a sliding window dropped the
  # oldest message every turn, an edit that never let the cached prefix survive.
  # Ai::ConciergeCompactor summarizes everything before the current turn once a
  # threshold is crossed. From then on a request starts with that summary and
  # replays only the messages after the boundary.
  class ConciergeHistory
    TURN_CONTEXT_KEY = "turn_context"
    COMPACTION_KEY = "compaction"

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

    # The request history: the compaction summary (if any), then every message
    # after the compaction boundary, each user turn followed by its frozen context.
    def messages
      summary_messages + render(rows_after_boundary)
    end

    # What a compaction summarizes: the summary so far plus every message before
    # the current turn. Compaction runs only at a turn boundary, so the current
    # user turn stays out of it and is replayed verbatim after the summary.
    def messages_before_current_turn
      rows = rows_after_boundary
      current = rows.rindex { |row| row.role == "user" }
      summary_messages + render(current ? rows.first(current) : rows)
    end

    # Records a compaction through the message just before the current user turn.
    # update_columns: request bookkeeping, not a user-visible conversation edit.
    def record_compaction!(summary)
      rows = rows_after_boundary
      current = rows.rindex { |row| row.role == "user" }
      through = current ? rows[current - 1] : rows.last
      return if through.nil? || current&.zero?

      metadata = (@conversation.metadata || {}).merge(
        COMPACTION_KEY => { "summary" => summary, "through_message_id" => through.id, "compacted_at" => Time.current.iso8601 }
      )
      @conversation.update_columns(metadata: metadata)
    end

    private

    def compaction = (@conversation.metadata || {})[COMPACTION_KEY]

    def summary_messages
      summary = compaction&.dig("summary")
      return [] if summary.blank?

      [ { role: "user", content: "<conversation-summary>\n#{summary}\n</conversation-summary>" } ]
    end

    def rows_after_boundary
      rows = @conversation.messages.not_deleted.ordered.to_a
      through = compaction&.dig("through_message_id")
      index = through && rows.index { |row| row.id == through }
      index ? rows.drop(index + 1) : rows
    end

    def render(rows)
      rows.flat_map do |row|
        entry = { role: row.role, content: row.content }
        context = row.role == "user" ? row.processing_metadata&.dig(TURN_CONTEXT_KEY) : nil
        context.present? ? [ entry, { role: "system", content: context, clear_at: "next_user_message" } ] : [ entry ]
      end
    end

    def latest_user_message
      @conversation.messages.not_deleted.where(role: "user").ordered.last
    end
  end
end
