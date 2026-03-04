# frozen_string_literal: true

module Ai
  module Learning
    class ExperienceReplayService
      MAX_COMPRESSED_TOKENS = 1500
      CHARS_PER_TOKEN = 4
      MIN_QUALITY_FOR_CAPTURE = 0.5

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Capture a successful execution trajectory as a reusable few-shot example
      def capture_from_execution(execution, trajectory: nil)
        return nil unless execution
        return nil unless execution_quality(execution) >= MIN_QUALITY_FOR_CAPTURE

        agent = execution.respond_to?(:ai_agent) ? execution.ai_agent : nil
        return nil unless agent

        compressed = compress_trajectory(execution, trajectory)
        return nil if compressed.blank?

        embedding = @embedding_service.generate(compressed)
        token_count = (compressed.length / CHARS_PER_TOKEN.to_f).ceil

        Ai::ExperienceReplay.create!(
          account: @account,
          agent: agent,
          source_execution: execution,
          source_trajectory: trajectory,
          task_type: extract_task_type(execution),
          task_description: extract_task_description(execution),
          compressed_example: compressed,
          quality_score: execution_quality(execution),
          token_count: token_count,
          embedding: embedding,
          metadata: {
            execution_id: execution.id,
            duration_ms: execution.respond_to?(:duration_ms) ? execution.duration_ms : nil,
            cost_usd: execution.respond_to?(:cost_usd) ? execution.cost_usd&.to_f : nil
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[ExperienceReplay] Capture failed: #{e.message}")
        nil
      end

      # Retrieve relevant experience replays for a task
      def retrieve_relevant(task_description:, agent_id: nil, limit: 10, threshold: 0.5)
        embedding = @embedding_service.generate(task_description)
        return [] unless embedding

        candidates = Ai::ExperienceReplay.semantic_search(
          embedding,
          account_id: @account.id,
          agent_id: agent_id,
          threshold: threshold,
          limit: limit * 2
        )

        # Rank by composite score and take top N
        candidates.sort_by { |r| -r.ranking_score }.first(limit)
      end

      # Build replay context within a token budget
      def build_replay_context(agent:, task_description:, token_budget: 2000)
        replays = retrieve_relevant(
          task_description: task_description,
          agent_id: agent.id,
          limit: 10
        )

        return { context: nil, token_estimate: 0, replay_ids: [] } if replays.empty?

        char_budget = token_budget * CHARS_PER_TOKEN
        lines = ["## Experience Replays (Few-Shot Examples)"]
        used_chars = lines.first.length + 2
        replay_ids = []

        replays.each do |replay|
          example_text = "### Example (quality: #{replay.quality_score.round(2)})\n#{replay.compressed_example}"
          break if used_chars + example_text.length > char_budget

          lines << example_text
          used_chars += example_text.length + 1
          replay_ids << replay.id
        end

        return { context: nil, token_estimate: 0, replay_ids: [] } if lines.size == 1

        {
          context: lines.join("\n\n"),
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          replay_ids: replay_ids
        }
      end

      # Record whether injected replays helped
      def record_injection_outcome!(replay_id, successful:)
        replay = Ai::ExperienceReplay.find_by(id: replay_id, account: @account)
        replay&.record_injection_outcome!(successful: successful)
      end

      private

      def compress_trajectory(execution, trajectory)
        parts = []

        # Task description
        if execution.respond_to?(:input_parameters)
          input = execution.input_parameters
          task_desc = input["prompt"] || input["task"] || input["message"] || input.to_json.truncate(200)
          parts << "Task: #{task_desc.truncate(300)}"
        end

        # Key steps from trajectory
        if trajectory&.respond_to?(:chapters)
          trajectory.chapters.order(:sequence_number).limit(5).each do |chapter|
            summary = chapter.respond_to?(:summary) ? chapter.summary : chapter.content&.truncate(200)
            parts << "Step #{chapter.sequence_number}: #{summary}" if summary.present?
          end
        end

        # Output summary
        if execution.respond_to?(:output_data)
          output = execution.output_data
          result_text = output["result"] || output["response"] || output.to_json.truncate(300)
          parts << "Result: #{result_text.truncate(300)}"
        end

        compressed = parts.join("\n")
        max_chars = MAX_COMPRESSED_TOKENS * CHARS_PER_TOKEN
        compressed.truncate(max_chars)
      end

      def execution_quality(execution)
        return 0.0 unless execution.respond_to?(:status) && execution.status == "completed"

        score = 0.5 # Base score for completion

        # Bonus for fast execution
        if execution.respond_to?(:duration_ms) && execution.duration_ms
          score += 0.1 if execution.duration_ms < 30_000
        end

        # Bonus for low cost
        if execution.respond_to?(:cost_usd) && execution.cost_usd
          score += 0.1 if execution.cost_usd < 0.05
        end

        # Bonus for having output
        if execution.respond_to?(:output_data) && execution.output_data.present?
          score += 0.2
        end

        # Cap at 1.0
        [score, 1.0].min
      end

      def extract_task_type(execution)
        return nil unless execution.respond_to?(:input_parameters)

        execution.input_parameters["task_type"] || execution.input_parameters["type"]
      end

      def extract_task_description(execution)
        return nil unless execution.respond_to?(:input_parameters)

        input = execution.input_parameters
        input["prompt"] || input["task"] || input["message"]
      end
    end
  end
end
