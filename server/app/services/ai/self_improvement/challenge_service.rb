# frozen_string_literal: true

module Ai
  module SelfImprovement
    class ChallengeService
      include Ai::LlmCallable

      DIFFICULTY_MAP = { "easy" => 0, "medium" => 1, "hard" => 2, "expert" => 3 }.freeze
      PASS_THRESHOLD = 0.7

      def initialize(account:)
        @account = account
      end

      def generate_challenge!(agent:, skill: nil, difficulty: "medium")
        prompt = build_challenge_generation_prompt(agent, skill, difficulty)

        response = call_llm(agent: agent, prompt: prompt, max_tokens: 500, temperature: 0.7)

        return nil unless response&.dig(:content)

        parsed = parse_challenge(response[:content])

        Ai::SelfChallenge.create!(
          account: @account,
          challenger_agent: agent,
          executor_agent: agent,
          skill: skill,
          difficulty: difficulty,
          status: "generating",
          challenge_prompt: parsed[:prompt],
          expected_criteria: parsed[:criteria]
        )
      end

      def execute_challenge!(challenge:, executor: nil)
        executor ||= challenge.executor_agent || challenge.challenger_agent
        challenge.update!(status: "executing", executor_agent: executor)

        response = call_llm(agent: executor, prompt: challenge.challenge_prompt, max_tokens: 1000, temperature: 0.3)

        challenge.update!(execution_result: response&.dig(:content))
        challenge
      end

      def validate_challenge!(challenge:, validator: nil)
        validating_agent = validator || challenge.executor_agent || challenge.challenger_agent
        challenge.update!(status: "validating", validator_agent: validator)

        prompt = build_validation_prompt(challenge)

        response = call_llm(agent: validating_agent, prompt: prompt, max_tokens: 300, temperature: 0.1)

        return nil unless response&.dig(:content)

        score = parse_validation_score(response[:content])
        challenge.update!(
          validation_result: { raw: response[:content], score: score },
          quality_score: score
        )

        challenge
      end

      def complete_challenge!(challenge:)
        if challenge.passed?
          challenge.update!(status: "completed")

          # Create trajectory as experience replay
          WorkerJobService.enqueue_ai_experience_replay_capture(
            challenge.challenger_agent_id,
            nil # No execution ID, just a challenge
          ) rescue nil
        else
          challenge.update!(status: "failed")
        end

        challenge
      end

      def adaptive_difficulty(agent:, skill: nil)
        recent = Ai::SelfChallenge.for_agent(agent.id)
        recent = recent.for_skill(skill.id) if skill
        recent = recent.where("created_at >= ?", 30.days.ago)
          .where(status: %w[completed failed])
          .order(created_at: :desc)
          .limit(5)

        return "medium" if recent.empty?

        passed = recent.select(&:passed?).size
        current_difficulty = recent.first&.difficulty || "medium"
        current_level = DIFFICULTY_MAP[current_difficulty] || 1

        if passed >= 3 && recent.select { |c| c.quality_score.to_f > 0.8 }.size >= 3
          new_level = [current_level + 1, 3].min
        elsif recent.select { |c| !c.passed? }.size >= 2
          new_level = [current_level - 1, 0].max
        else
          new_level = current_level
        end

        DIFFICULTY_MAP.key(new_level) || "medium"
      end

      private

      def build_challenge_generation_prompt(agent, skill, difficulty)
        skill_context = skill ? "Skill: #{skill.name} - #{skill.description}" : "General capabilities"

        <<~PROMPT
          Generate a #{difficulty}-difficulty challenge for an AI agent.

          Agent: #{agent.name} (#{agent.agent_type})
          #{skill_context}

          Respond in this format:
          CHALLENGE: <the task prompt for the agent to complete>
          CRITERIA_1: <success criterion 1>
          CRITERIA_2: <success criterion 2>
          CRITERIA_3: <success criterion 3>
        PROMPT
      end

      def build_validation_prompt(challenge)
        <<~PROMPT
          Validate this challenge response against the criteria.

          Challenge: #{challenge.challenge_prompt}
          Expected Criteria: #{challenge.expected_criteria.to_json}
          Response: #{challenge.execution_result&.truncate(1000)}

          Score the response 0.0-1.0 based on how well it meets all criteria.
          Respond with just: SCORE: <number>
        PROMPT
      end

      def parse_challenge(text)
        prompt = text[/CHALLENGE:\s*(.+?)(?:CRITERIA|$)/im, 1]&.strip
        criteria = {}
        text.scan(/CRITERIA_(\d+):\s*(.+)/i).each do |num, criterion|
          criteria["criterion_#{num}"] = criterion.strip
        end

        { prompt: prompt || text.truncate(500), criteria: criteria }
      end

      def parse_validation_score(text)
        score = text[/SCORE:\s*([\d.]+)/i, 1]&.to_f
        score ? [score, 1.0].min : 0.5
      end
    end
  end
end
