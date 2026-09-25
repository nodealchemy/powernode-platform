# frozen_string_literal: true

module Ai
  # Threshold compaction for a concierge conversation ("simple compaction").
  #
  # When the replayed history outgrows the budget, the whole visible history
  # before the current turn is summarized into one message. Later requests start
  # with that summary plus the current turn and replay nothing earlier. This is
  # the client-side compaction shape that stays valid under preserved thinking:
  # no earlier turn is edited or snipped, and nothing carried over is tied to the
  # old transcript. It runs only at a turn boundary.
  #
  # Client-side rather than the API's server-side compaction because the
  # concierge is multi-provider (often OpenAI-served), and this needs no
  # compaction blocks round-tripped through the worker.
  class ConciergeCompactor
    CHARS_PER_TOKEN = 4
    CONTEXT_SHARE = 0.6
    # Used when the model's context window is unknown (non-Claude models): about
    # 60K tokens, which fits a 128K-context model with room for the reply.
    FALLBACK_CHAR_BUDGET = 240_000

    # Retention instructions for client-side compaction (the summarization prompt
    # Anthropic recommends for simple compaction).
    SUMMARY_PROMPT = <<~PROMPT.squish
      Summarize the transcript inside <summary></summary> tags. Include relevant information in the
      summary such that this conversation will be continued by a new context window without needing
      to redo work or be reprovided with relevant constraints or context. Be sure to preserve: (1) any
      difficulties or problems that came up, and how they were handled or resolved; (2) any
      possibilities, options, or approaches that were raised, tried, or set aside, and why; (3)
      anything that was asked for, decided, agreed, ruled out, or established as a preference,
      constraint, or boundary - stated exactly; (4) exactly where things stand now - what has been
      covered, settled, or completed so far; (5) anything still open, unresolved, promised, or
      expected to happen next; (6) specific details that would be hard to reconstruct - names,
      numbers, dates, exact wording, links or references - kept exactly. Be complete on these even at
      the cost of length; keep everything else concise. Weight the two voices differently: keep what
      the user said, asked for, shared, or established carefully and close to their own words; your
      own explanations and reasoning can be condensed much further, to what they concluded or
      produced - as long as nothing in the six items above is dropped. Do not call any tools while
      writing this summary; respond with text only.
    PROMPT

    # system_prompt: a String, or a callable evaluated only when a summary is made.
    def initialize(history:, llm_client:, model:, system_prompt:, char_budget: nil)
      @history = history
      @llm_client = llm_client
      @model = model
      @system_prompt = system_prompt
      @char_budget = char_budget || self.class.char_budget_for(model)
    end

    def self.char_budget_for(model)
      window = ::Ai::Llm::ModelCapabilities.context_window(model)
      window ? (window * CONTEXT_SHARE * CHARS_PER_TOKEN).to_i : FALLBACK_CHAR_BUDGET
    end

    # @return [Boolean] whether a compaction was recorded
    def compact_if_needed!
      return false if size_of(@history.messages) <= @char_budget

      summary = summarize(@history.messages_before_current_turn)
      return false if summary.blank?

      @history.record_compaction!(summary)
      true
    rescue StandardError => e
      Rails.logger.warn("[ConciergeCompactor] compaction skipped: #{e.class}: #{e.message}")
      false
    end

    private

    def size_of(messages) = messages.sum { |m| m[:content].to_s.length }

    # The summarizer request reuses the conversation's system prompt and history
    # as they are and appends the instruction, so it shares the conversation's
    # cached prefix.
    def summarize(messages)
      response = @llm_client.complete(
        messages: messages + [ { role: "user", content: SUMMARY_PROMPT } ],
        model: @model,
        system_prompt: @system_prompt.respond_to?(:call) ? @system_prompt.call : @system_prompt,
        max_tokens: ::Ai::Llm::ModelCapabilities.default_max_tokens(@model) || 4096
      )
      text = response.content.to_s
      text[%r{<summary>(.*)</summary>}m, 1]&.strip.presence || text.strip.presence
    end
  end
end
