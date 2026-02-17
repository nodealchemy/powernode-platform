# frozen_string_literal: true

module Ai
  module ToolCallExtraction
    extend ActiveSupport::Concern

    # Extract tool calls from provider response, normalized to common format
    # @param response [Hash] The provider response
    # @param provider_type [String] "anthropic", "openai", or "ollama"
    # @return [Array<Hash>] Array of { id:, name:, arguments: }
    def extract_tool_calls(response, provider_type)
      case provider_type
      when "anthropic"
        content = response[:content]
        return [] unless content.is_a?(Array)

        content.select { |c| c[:type] == "tool_use" }.map do |tc|
          { id: tc[:id], name: tc[:name], arguments: tc[:input] || {} }
        end
      else
        # OpenAI / Ollama format
        tool_calls = response.dig(:choices, 0, :message, :tool_calls)
        return [] unless tool_calls.is_a?(Array)

        tool_calls.map do |tc|
          args = tc.dig(:function, :arguments)
          parsed_args = args.is_a?(String) ? (JSON.parse(args) rescue {}) : (args || {})
          { id: tc[:id], name: tc.dig(:function, :name), arguments: parsed_args }
        end
      end
    end

    # Build provider-specific tool result messages
    # @param results [Array<Hash>] Array of { tool_call_id:, content: }
    # @param provider_type [String]
    # @return [Array<Hash>] Messages to append to conversation
    def build_tool_result_messages(results, provider_type)
      case provider_type
      when "anthropic"
        content_blocks = results.map do |r|
          { type: "tool_result", tool_use_id: r[:tool_call_id], content: r[:content] }
        end
        [{ role: "user", content: content_blocks }]
      else
        # OpenAI / Ollama format
        results.map do |r|
          { role: "tool", tool_call_id: r[:tool_call_id], content: r[:content] }
        end
      end
    end

    # Extract text content from multi-block responses
    # @param response [Hash] The provider response
    # @param provider_type [String]
    # @return [String]
    def extract_text_content(response, provider_type)
      case provider_type
      when "anthropic"
        content = response[:content]
        return "" unless content.is_a?(Array)

        content.select { |c| c[:type] == "text" }.map { |c| c[:text] }.join
      else
        response.dig(:choices, 0, :message, :content) || ""
      end
    end

    # Build provider-specific assistant message for tool calls (to append before results)
    # @param response [Hash] The raw provider response
    # @param provider_type [String]
    # @return [Hash] Assistant message to append to conversation
    def build_assistant_tool_message(response, provider_type)
      case provider_type
      when "anthropic"
        { role: "assistant", content: response[:content] }
      else
        msg = response.dig(:choices, 0, :message) || {}
        { role: "assistant", content: msg[:content], tool_calls: msg[:tool_calls] }
      end
    end
  end
end
