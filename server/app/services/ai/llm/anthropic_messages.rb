# frozen_string_literal: true

module Ai
  module Llm
    # Shapes an OpenAI-style message list (roles system/user/assistant/tool) into an
    # Anthropic request's top-level `system` text and `messages` array. It is
    # DUPLICATED verbatim in the server and the worker, with no shared lib across
    # the apps, like ModelCapabilities. Keep the two copies in sync.
    #
    # Only the LEADING run of system messages becomes top-level `system`, so that
    # field stays byte-identical across the turns of a conversation. The prompt
    # cache and preserved thinking are both bound to it. A system message later in
    # the history stays where it is:
    #   - as a native {role: "system"} message when the model accepts
    #     mid-conversation system messages
    #     (ModelCapabilities.mid_conversation_system?) and the placement is legal:
    #     directly after a user turn, and either last or followed by an assistant
    #     turn;
    #   - otherwise as a <system-reminder> text block appended to the user turn it
    #     follows, or as its own user message when it does not follow one.
    # Consecutive system messages form one run. The output depends only on the
    # message list, so an append-only history produces an append-only request.
    #
    # A run whose messages all carry `clear_at: "next_user_message"` is turn-scoped:
    # the native form keeps the field, so the message renders for its own turn and
    # then stays in the history cleared. It costs no input tokens and is never
    # deleted, which would be an edit. The reminder fallback has no such field; its
    # earlier copies simply stay in place. .beta_headers declares the beta the body
    # then needs.
    #
    # Within a tool loop, the assistant turn that called the tools is replayed with
    # its thinking blocks, verbatim and in order (.replay_blocks picks them out of a
    # response), so the model keeps its reasoning across tool rounds. .bind_thinking!
    # asks the API to drop a replayed block whose prefix no longer matches instead of
    # failing the request; its caller applies it only on the first-party API, since
    # the binding controls are per model on Bedrock and Vertex and absent on Foundry.
    module AnthropicMessages
      CLEAR_AT_BETA = "mid-conversation-system-clear-at-2026-08-21"
      THINKING_BINDING_BETA = "thinking-binding-controls-2026-08-01"
      THINKING_TYPES = %w[thinking redacted_thinking].freeze
      REPLAY_TYPES = (THINKING_TYPES + %w[text tool_use]).freeze

      module_function

      # The anthropic-beta header a request body needs. Each feature in the body
      # declares its own beta, so a caller cannot send one without the other.
      def beta_headers(body)
        messages = body[:messages] || body["messages"]
        betas = []
        betas << CLEAR_AT_BETA if Array(messages).any? { |m| m.is_a?(Hash) && clear_at_of(m) }
        thinking = body[:thinking] || body["thinking"]
        betas << THINKING_BINDING_BETA if thinking.is_a?(Hash) && (thinking[:block_binding] || thinking["block_binding"])
        betas.empty? ? {} : { "anthropic-beta" => betas.join(",") }
      end

      # An assistant turn's content blocks to replay verbatim, or nil when the turn
      # carries no thinking (rebuilding it from tool_calls is then equivalent).
      def replay_blocks(blocks)
        blocks = Array(blocks).select { |b| b.is_a?(Hash) && REPLAY_TYPES.include?(block_type(b)) }
        blocks.any? { |b| THINKING_TYPES.include?(block_type(b)) } ? blocks : nil
      end

      # Sets thinking.block_binding.prefix_mismatch_behavior "drop_block" when the
      # request replays a thinking block to an adaptive-only model; the thinking
      # config already in the body is kept. .beta_headers then adds the beta.
      def bind_thinking!(body, model)
        return body unless ModelCapabilities.thinking_mode(model) == :adaptive_only && replays_thinking?(body[:messages])

        body[:thinking] = (body[:thinking] || { type: "adaptive" })
                          .merge(block_binding: { prefix_mismatch_behavior: "drop_block" })
        body
      end

      def replays_thinking?(messages)
        Array(messages).any? do |m|
          content = m.is_a?(Hash) ? (m[:content] || m["content"]) : nil
          content.is_a?(Array) && content.any? { |b| b.is_a?(Hash) && THINKING_TYPES.include?(block_type(b)) }
        end
      end

      # @param normalize [Proc] maps each non-system message to Anthropic shape
      #   (tool results, tool_use blocks); identity when omitted.
      # @return [Array(String, Array<Hash>)] the top-level system text and the messages
      def split(messages, model, &normalize)
        normalize ||= ->(message) { message }
        messages = Array(messages)
        leading = messages.take_while { |m| system?(m) }
        system_text = leading.map { |m| text_of(m) }.reject(&:empty?).join("\n")
        native = ModelCapabilities.mid_conversation_system?(model)
        [ system_text, place(messages.drop(leading.size), native, normalize) ]
      end

      def place(messages, native, normalize)
        out = []
        i = 0
        while i < messages.size
          unless system?(messages[i])
            out << normalize.call(messages[i])
            i += 1
            next
          end

          run = []
          while i < messages.size && system?(messages[i])
            run << messages[i]
            i += 1
          end
          text = run.map { |m| text_of(m) }.reject(&:empty?).join("\n\n")
          next if text.empty?

          clear_at = run.map { |m| clear_at_of(m) }.uniq
          clear_at = clear_at.size == 1 ? clear_at.first : nil

          after_user = out.any? && role_of(out.last) == "user"
          upcoming = messages[i]
          if native && after_user && (upcoming.nil? || role_of(upcoming) == "assistant")
            out << { role: "system", content: text, clear_at: clear_at }.compact
          elsif after_user
            out[-1] = with_reminder(out.last, text)
          else
            out << { role: "user", content: [ reminder_block(text) ] }
          end
        end
        out
      end

      def with_reminder(message, text)
        content = message[:content] || message["content"]
        blocks = content.is_a?(Array) ? content.dup : []
        blocks << { type: "text", text: content.to_s } if !content.is_a?(Array) && content.to_s != ""
        blocks << reminder_block(text)
        { role: role_of(message), content: blocks }
      end

      def reminder_block(text)
        { type: "text", text: "<system-reminder>\n#{text}\n</system-reminder>" }
      end

      def system?(message) = role_of(message) == "system"

      def block_type(block) = (block[:type] || block["type"]).to_s

      def clear_at_of(message) = message[:clear_at] || message["clear_at"]

      def role_of(message) = (message[:role] || message["role"]).to_s

      def text_of(message)
        content = message[:content] || message["content"]
        return content.to_s unless content.is_a?(Array)

        content.filter_map { |block| block.is_a?(Hash) ? (block[:text] || block["text"]) : block.to_s }.join("\n")
      end
    end
  end
end
