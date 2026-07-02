# frozen_string_literal: true

module Ai
  module Codebase
    # Shared LLM-triage plumbing for the analyzer-detects + AI-judges codebase
    # services (DuplicateAnalysisService, DeadCodeAnalysisService): account-scoped
    # client resolution, batched best-effort triage, tolerant JSON extraction,
    # default-model pick, and the capped shell-out helper.
    #
    # Including services must define:
    #   TRIAGE_BATCH             — items per LLM call
    #   CMD_BYTE_CAP             — max bytes read from a shelled-out command
    #   #triage_batch(client, model, batch) — builds the prompt and merges results
    #   #triage_log_tag          — short tag for log lines (e.g. "DeadCodeAnalysis")
    module LlmTriagePipeline
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

      # Robustly pull the {"results":[...]} array from an LLM text response,
      # tolerating markdown fences / surrounding prose.
      def extract_results(content)
        return [] if content.blank?

        text = content.to_s.gsub(/```(?:json)?/i, "")
        first = text.index("{")
        last  = text.rindex("}")
        return [] unless first && last && last > first

        parsed = JSON.parse(text[first..last]) rescue nil
        parsed.is_a?(Hash) ? Array(parsed["results"]) : []
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
