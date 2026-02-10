# frozen_string_literal: true

module Ai
  module Routing
    # Service for classifying task complexity and recommending model tiers.
    #
    # Analyzes task characteristics (token count, tool usage, conversation depth,
    # content patterns) to determine complexity level and recommend an appropriate
    # model tier for cost-effective routing.
    #
    # Usage:
    #   service = Ai::Routing::TaskComplexityClassifierService.new(account: account)
    #   result = service.classify(task_type: "code_review", messages: messages, tools: tools)
    #   result[:complexity_level]  # => "moderate"
    #   result[:recommended_tier]  # => "standard"
    #
    class TaskComplexityClassifierService
      include Ai::Concerns::AccountScoped

      CLASSIFIER_VERSION = "1.0.0"

      # Signal weights for composite score calculation
      SIGNAL_WEIGHTS = {
        token_density: 0.25,
        tool_complexity: 0.15,
        conversation_depth: 0.15,
        content_complexity: 0.25,
        task_type_baseline: 0.20
      }.freeze

      # Task type baseline complexity scores (0.0 to 1.0)
      TASK_TYPE_BASELINES = {
        "classification" => 0.1,
        "extraction" => 0.15,
        "formatting" => 0.1,
        "routing" => 0.15,
        "simple_qa" => 0.2,
        "summarization" => 0.35,
        "translation" => 0.35,
        "analysis" => 0.5,
        "code_review" => 0.55,
        "agent_task" => 0.5,
        "reasoning" => 0.75,
        "code_generation" => 0.7,
        "creative" => 0.65,
        "critical_decision" => 0.85
      }.freeze

      # Complexity level thresholds
      LEVEL_THRESHOLDS = {
        "trivial" => 0.0,
        "simple" => 0.12,
        "moderate" => 0.25,
        "complex" => 0.45,
        "expert" => 0.80
      }.freeze

      # Tier mapping from complexity level
      LEVEL_TO_TIER = {
        "trivial" => "economy",
        "simple" => "economy",
        "moderate" => "standard",
        "complex" => "premium",
        "expert" => "premium"
      }.freeze

      # Content complexity indicator patterns
      CODE_PATTERNS = [
        /```[\s\S]*?```/,
        /def\s+\w+/,
        /class\s+\w+/,
        /function\s+\w+/,
        /import\s+/,
        /require\s*\(/
      ].freeze

      MATH_PATTERNS = [
        /\b(?:calculate|compute|equation|formula|integral|derivative|matrix)\b/i,
        /[+\-*\/=]{2,}/,
        /\d+\.\d+/,
        /\\(?:frac|sum|prod|int)/
      ].freeze

      HIGH_COMPLEXITY_KEYWORDS = %w[
        analyze compare evaluate synthesize optimize
        architecture design refactor debug security
        performance scalability trade-off decision
        multi-step reasoning proof explain why
      ].freeze

      LOW_COMPLEXITY_KEYWORDS = %w[
        list format convert translate extract
        summarize yes no true false simple
        short brief quick basic
      ].freeze

      # Classify a task and return complexity assessment
      #
      # @param task_type [String] Type of task (e.g., "code_review", "simple_qa")
      # @param messages [Array<Hash>] Conversation messages with :role and :content
      # @param tools [Array] Available tools for the task
      # @param context [Hash] Additional context (e.g., agent capabilities)
      # @return [Hash] Classification result with complexity_level, score, tier, signals
      def classify(task_type:, messages:, tools: [], context: {})
        signals = compute_signals(task_type, messages, tools, context)
        score = compute_composite_score(signals)
        level = determine_level(score)
        tier = determine_tier(level, context)

        assessment = record_assessment(
          task_type: task_type,
          messages: messages,
          tools: tools,
          signals: signals,
          score: score,
          level: level,
          tier: tier
        )

        {
          complexity_level: level,
          complexity_score: score.round(4),
          recommended_tier: tier,
          signals: signals,
          assessment_id: assessment&.id,
          classifier_version: CLASSIFIER_VERSION
        }
      end

      # Classify without persisting (for dry-run or preview)
      #
      # @param task_type [String] Type of task
      # @param messages [Array<Hash>] Conversation messages
      # @param tools [Array] Available tools
      # @param context [Hash] Additional context
      # @return [Hash] Classification result
      def classify_preview(task_type:, messages:, tools: [], context: {})
        signals = compute_signals(task_type, messages, tools, context)
        score = compute_composite_score(signals)
        level = determine_level(score)
        tier = determine_tier(level, context)

        {
          complexity_level: level,
          complexity_score: score.round(4),
          recommended_tier: tier,
          signals: signals,
          classifier_version: CLASSIFIER_VERSION
        }
      end

      private

      def compute_signals(task_type, messages, tools, context)
        content = extract_content(messages)
        token_count = estimate_tokens(content)

        {
          token_density: compute_token_density_signal(token_count),
          tool_complexity: compute_tool_complexity_signal(tools),
          conversation_depth: compute_depth_signal(messages),
          content_complexity: compute_content_complexity_signal(content),
          task_type_baseline: compute_task_baseline_signal(task_type),
          raw: {
            token_count: token_count,
            tool_count: tools.length,
            message_count: messages.length,
            has_code: content_has_code?(content),
            has_math: content_has_math?(content),
            high_complexity_keyword_count: count_keywords(content, HIGH_COMPLEXITY_KEYWORDS),
            low_complexity_keyword_count: count_keywords(content, LOW_COMPLEXITY_KEYWORDS)
          }
        }
      end

      def compute_composite_score(signals)
        weighted_sum = 0.0

        SIGNAL_WEIGHTS.each do |signal, weight|
          value = signals[signal] || 0.0
          weighted_sum += value * weight
        end

        weighted_sum.clamp(0.0, 1.0)
      end

      def determine_level(score)
        LEVEL_THRESHOLDS.to_a.reverse.detect { |_, threshold| score >= threshold }&.first || "trivial"
      end

      def determine_tier(level, context)
        # Check for budget override from context
        if context[:force_tier].present?
          return context[:force_tier] if Ai::TaskComplexityAssessment::RECOMMENDED_TIERS.include?(context[:force_tier])
        end

        LEVEL_TO_TIER[level] || "standard"
      end

      # Signal computation methods

      def compute_token_density_signal(token_count)
        # Scale: 0-100 tokens = low, 100-500 = medium, 500-2000 = high, 2000+ = very high
        case token_count
        when 0..100 then 0.1
        when 101..500 then 0.3
        when 501..1000 then 0.5
        when 1001..2000 then 0.7
        when 2001..5000 then 0.85
        else 1.0
        end
      end

      def compute_tool_complexity_signal(tools)
        count = tools.length
        case count
        when 0 then 0.0
        when 1..2 then 0.2
        when 3..5 then 0.4
        when 6..10 then 0.6
        when 11..20 then 0.8
        else 1.0
        end
      end

      def compute_depth_signal(messages)
        depth = messages.length
        case depth
        when 0..1 then 0.0
        when 2..3 then 0.15
        when 4..6 then 0.3
        when 7..10 then 0.5
        when 11..20 then 0.7
        when 21..50 then 0.85
        else 1.0
        end
      end

      def compute_content_complexity_signal(content)
        score = 0.0

        # Code presence increases complexity
        score += 0.25 if content_has_code?(content)

        # Math presence increases complexity
        score += 0.2 if content_has_math?(content)

        # High complexity keywords
        high_count = count_keywords(content, HIGH_COMPLEXITY_KEYWORDS)
        score += [high_count * 0.05, 0.35].min

        # Low complexity keywords reduce score
        low_count = count_keywords(content, LOW_COMPLEXITY_KEYWORDS)
        score -= [low_count * 0.03, 0.2].min

        score.clamp(0.0, 1.0)
      end

      def compute_task_baseline_signal(task_type)
        TASK_TYPE_BASELINES[task_type.to_s] || 0.4
      end

      # Helper methods

      def extract_content(messages)
        messages.map { |m| m[:content] || m["content"] || "" }.join("\n")
      end

      def estimate_tokens(text)
        # Rough estimation: ~4 characters per token
        (text.length / 4.0).ceil
      end

      def content_has_code?(content)
        CODE_PATTERNS.any? { |pattern| content.match?(pattern) }
      end

      def content_has_math?(content)
        MATH_PATTERNS.any? { |pattern| content.match?(pattern) }
      end

      def count_keywords(content, keywords)
        downcased = content.downcase
        keywords.count { |kw| downcased.include?(kw) }
      end

      def record_assessment(task_type:, messages:, tools:, signals:, score:, level:, tier:)
        content = extract_content(messages)

        Ai::TaskComplexityAssessment.create!(
          account: account,
          task_type: task_type,
          input_token_count: signals.dig(:raw, :token_count) || estimate_tokens(content),
          tool_count: tools.length,
          conversation_depth: messages.length,
          complexity_signals: signals.except(:raw).merge(raw_summary: signals[:raw]),
          complexity_score: score.round(4),
          complexity_level: level,
          recommended_tier: tier,
          classifier_version: CLASSIFIER_VERSION
        )
      rescue StandardError => e
        Rails.logger.error "[TaskComplexityClassifier] Failed to record assessment: #{e.message}"
        nil
      end
    end
  end
end
