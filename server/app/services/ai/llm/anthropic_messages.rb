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
    module AnthropicMessages
      module_function

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
            run << text_of(messages[i])
            i += 1
          end
          text = run.reject(&:empty?).join("\n\n")
          next if text.empty?

          after_user = out.any? && role_of(out.last) == "user"
          upcoming = messages[i]
          if native && after_user && (upcoming.nil? || role_of(upcoming) == "assistant")
            out << { role: "system", content: text }
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

      def role_of(message) = (message[:role] || message["role"]).to_s

      def text_of(message)
        content = message[:content] || message["content"]
        return content.to_s unless content.is_a?(Array)

        content.filter_map { |block| block.is_a?(Hash) ? (block[:text] || block["text"]) : block.to_s }.join("\n")
      end
    end
  end
end
