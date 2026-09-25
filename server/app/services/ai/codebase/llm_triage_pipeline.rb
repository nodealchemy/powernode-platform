# frozen_string_literal: true

module Ai
  module Codebase
    # Shared LLM-triage plumbing for the analyzer-detects + AI-judges codebase
    # services (DuplicateAnalysisService, DeadCodeAnalysisService,
    # SymbolSummaryService): account-scoped client resolution, batched best-effort
    # triage, the structured-output {"results": [...]} request, default-model pick,
    # and the capped shell-out helper.
    #
    # Including services must define:
    #   TRIAGE_BATCH             — items per LLM call
    #   CMD_BYTE_CAP             — max bytes read from a shelled-out command
    #   #triage_batch(client, model, batch) — builds the prompt and merges results
    #   #triage_log_tag          — short tag for log lines (e.g. "DeadCodeAnalysis")
    module LlmTriagePipeline
      # A {"results": [item, ...]} schema for structured output. Every object is
      # closed and lists every property as required: Anthropic output_config.format
      # requires additionalProperties false, and OpenAI strict json_schema requires
      # both. No numeric or length constraints (unsupported).
      def self.results_schema(name, item_properties)
        item = { type: "object", additionalProperties: false,
                 required: item_properties.keys.map(&:to_s), properties: item_properties }
        { name: name,
          schema: { type: "object", additionalProperties: false, required: [ "results" ],
                    properties: { results: { type: "array", items: item } } } }.freeze
      end

      private

      # Batched, best-effort triage: a failed batch is passed through untriaged.
      # @return [Array(Array<Hash>, String)] [triaged items, status]
      def run_triage(items, model:)
        client = Ai::Llm::Client.for_account(@account)
        resolved = model.presence || default_model(client)
        return [items, "skipped (no LLM credential)"] if client.nil? || resolved.blank?

        triaged = []
        items.each_slice(self.class::TRIAGE_BATCH) do |batch|
          triaged.concat(triage_batch(client, resolved, batch))
        rescue => e
          Rails.logger.warn "[#{triage_log_tag}] triage batch failed: #{e.message}"
          triaged.concat(batch)
        end
        [triaged, "completed (#{resolved})"]
      end

      # One structured-output request; the API enforces the schema, so the
      # content parses as-is. An empty or unparseable reply (a refusal, a
      # max_tokens cut) raises, and the caller's batch rescue counts it.
      def request_results(client, model:, prompt:, system_prompt:, schema:, max_tokens:)
        resp = client.complete_structured(
          messages: [ { role: "user", content: prompt } ],
          schema: schema,
          model: model,
          system_prompt: system_prompt,
          max_tokens: max_tokens,
          temperature: 0
        )
        Array(JSON.parse(resp.content.to_s)["results"])
      end

      def default_model(client)
        return nil unless client

        models = client.provider&.available_models rescue nil
        first = models.is_a?(Array) ? models.first : nil
        first.is_a?(Hash) ? (first["id"] || first["name"] || first[:id] || first[:name]) : first
      end

      def run(command)
        IO.popen(command, err: [:child, :out]) { |io| io.read(self.class::CMD_BYTE_CAP) }
      rescue Errno::ENOENT, Errno::EPIPE => e
        Rails.logger.warn "[#{triage_log_tag}] command failed: #{e.message}"
        nil
      end
    end
  end
end
