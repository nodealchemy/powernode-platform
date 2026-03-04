# frozen_string_literal: true

module Ai
  module Learning
    class CompoundLearningService
      DEDUP_THRESHOLD = 0.92
      CONFLICT_THRESHOLD_LOW = 0.7
      CHARS_PER_TOKEN = 4

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        @auto_extractor = AutoExtractorService.new(account: account)
      end

      # ==================================================
      # Extraction Phase
      # ==================================================

      # Called after any team execution completes or fails
      def post_execution_extract(execution)
        return unless execution

        team = execution.respond_to?(:agent_team) ? execution.agent_team : nil
        status = execution.status
        successful = status == "completed"

        learnings = []

        # 1. Marker-based extraction (backward compat with SharedLearningService)
        if successful && execution.respond_to?(:output_result)
          output = execution.output_result
          storage = Ai::Memory::StorageService.new(account: @account)
          markers = storage.extract_learnings_from_output(output: output)
          markers.each do |m|
            learnings << m.merge(
              extraction_method: "marker",
              source_execution_successful: true
            )
          end
        end

        # 2. Pattern-based extraction
        metadata = build_execution_metadata(execution)
        if successful
          learnings += @auto_extractor.extract_from_success(
            output: execution.respond_to?(:output_result) ? execution.output_result : nil,
            metadata: metadata
          ).map { |l| l.merge(source_execution_successful: true) }
        else
          error = execution.respond_to?(:termination_reason) ? execution.termination_reason : "Unknown error"
          learnings += @auto_extractor.extract_from_failure(
            error: error,
            metadata: metadata
          ).map { |l| l.merge(source_execution_successful: false) }
        end

        # 3. Evaluation-based extraction
        eval_learnings = @auto_extractor.extract_from_evaluations(execution_id: execution.id)
        learnings += eval_learnings.map { |l| l.merge(source_execution_successful: successful) }

        # 4. Store each learning with deduplication
        stored_count = 0
        learnings.each do |learning_data|
          stored = store_learning(
            learning_data,
            team: team,
            execution: execution
          )
          stored_count += 1 if stored
        end

        # 5. Boost confidence for previously injected learnings on successful outcome
        boost_injected_learnings_on_success(execution) if successful

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from execution #{execution.id}")

        # 6. Trigger experience replay capture for successful high-quality executions
        if successful && execution_quality_sufficient?(execution)
          begin
            WorkerJobService.enqueue_ai_experience_replay_capture(execution.id)
          rescue StandardError => e
            Rails.logger.warn("[CompoundLearning] Failed to enqueue experience replay: #{e.message}")
          end
        end

        # 7. Trigger reflexion for failed executions
        unless successful
          begin
            reflexion_service = Ai::Learning::ReflexionService.new(account: @account)
            if reflexion_service.should_reflect?(execution)
              WorkerJobService.enqueue_ai_reflexion(execution.id)
            end
          rescue StandardError => e
            Rails.logger.warn("[CompoundLearning] Failed to enqueue reflexion: #{e.message}")
          end
        end

        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Extraction failed: #{e.message}")
        0
      end

      # Called after review rejection/revision
      def review_feedback_extract(review)
        return 0 unless review

        learnings = @auto_extractor.extract_from_review(review)

        team = review.team_task&.team_execution&.agent_team
        execution = review.team_task&.team_execution

        stored_count = 0
        learnings.each do |learning_data|
          stored = store_learning(learning_data, team: team, execution: execution)
          stored_count += 1 if stored
        end

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from review #{review.id}")
        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Review extraction failed: #{e.message}")
        0
      end

      # ==================================================
      # Context Injection Phase (feature-flagged)
      # ==================================================

      def build_compound_context(agent:, task_description:, token_budget: 2000)
        return { context: nil, token_estimate: 0, learning_ids: [] } unless injection_enabled?

        char_budget = token_budget * CHARS_PER_TOKEN
        learning_ids = []

        # Generate query embedding
        query_embedding = @embedding_service.generate(task_description)

        # Retrieve relevant learnings
        candidates = if query_embedding
          Ai::CompoundLearning.semantic_search(
            query_embedding,
            account_id: @account.id,
            threshold: 0.5,
            limit: 30
          )
        else
          # Fallback to keyword search
          keyword_search(task_description)
        end

        return { context: nil, token_estimate: 0, learning_ids: [] } if candidates.empty?

        # Rank by effective_importance
        ranked = candidates.sort_by { |l| -l.effective_importance }

        # Build context string within budget
        lines = ["## Compound Learnings"]
        used_chars = lines.first.length + 2

        ranked.each do |learning|
          category_label = "[#{learning.category}]"
          freshness = learning_freshness(learning.updated_at)
          freshness_label = freshness == "fresh" ? "" : " [#{freshness}]"
          line = "- #{category_label}#{freshness_label} #{learning.title || learning.content.truncate(100)}: #{learning.content.truncate(200)}"
          break if used_chars + line.length > char_budget

          lines << line
          used_chars += line.length + 1
          learning_ids << learning.id
          learning.record_access!
        end

        return { context: nil, token_estimate: 0, learning_ids: [] } if lines.size == 1

        context = lines.join("\n")
        {
          context: context,
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          learning_ids: learning_ids
        }
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Context build failed: #{e.message}")
        { context: nil, token_estimate: 0, learning_ids: [] }
      end

      # ==================================================
      # Compounding Phase (feature-flagged)
      # ==================================================

      def promote_cross_team(min_importance: 0.7)
        return 0 unless promotion_enabled?

        candidates = Ai::CompoundLearning
          .active
          .for_account(@account.id)
          .team_scope
          .where("importance_score >= ?", min_importance)
          .where("access_count >= ?", 2)

        promoted_count = 0

        candidates.find_each do |learning|
          # Check if already promoted globally
          existing_global = Ai::CompoundLearning.active
            .for_account(@account.id)
            .global_scope
            .where("content ILIKE ?", "%#{learning.content.truncate(100)}%")

          if learning.embedding.present?
            similar = Ai::CompoundLearning.find_similar(
              learning.embedding,
              account_id: @account.id,
              threshold: DEDUP_THRESHOLD
            ).global_scope
            existing_global = existing_global.or(similar) if similar.any?
          end

          next if existing_global.exists?

          Ai::CompoundLearning.create!(
            account: @account,
            category: learning.category,
            content: learning.content,
            title: learning.title,
            importance_score: learning.importance_score,
            confidence_score: learning.confidence_score,
            scope: "global",
            extraction_method: learning.extraction_method,
            tags: learning.tags,
            applicable_domains: learning.applicable_domains,
            embedding: learning.embedding,
            promoted_at: Time.current,
            metadata: { promoted_from_team: learning.ai_agent_team_id, original_id: learning.id }
          )
          promoted_count += 1
        end

        Rails.logger.info("[CompoundLearning] Promoted #{promoted_count} learnings to global scope")
        promoted_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Promotion failed: #{e.message}")
        0
      end

      # Create a learning from team execution coordination results
      def create_from_team_execution(team_execution, results)
        return 0 unless team_execution && results

        stored_count = 0
        team = team_execution.respond_to?(:agent_team) ? team_execution.agent_team : nil
        outputs = results[:outputs] || []

        # Extract coordination pattern learning
        if outputs.size > 1
          strategy = team&.team_type || "unknown"
          tasks_completed = results[:tasks_completed] || 0
          tasks_failed = results[:tasks_failed] || 0
          success_rate = tasks_completed.to_f / [outputs.size, 1].max

          if success_rate >= 0.8
            stored = store_learning({
              title: "Team coordination: #{strategy} strategy with #{outputs.size} members",
              content: "Team '#{team&.name}' used #{strategy} strategy. #{tasks_completed}/#{outputs.size} tasks succeeded (#{(success_rate * 100).round}%). " \
                       "Roles involved: #{outputs.map { |o| o[:role] }.compact.uniq.join(', ')}. " \
                       "Total cost: $#{results[:total_cost]&.round(4)}.",
              category: "pattern",
              importance: [success_rate, 0.7].min,
              confidence: [success_rate, 0.8].min,
              extraction_method: "team_execution",
              tags: ["team", strategy, team&.name].compact,
              source_execution_successful: true
            }, team: team, execution: team_execution)
            stored_count += 1 if stored
          end

          # Extract failure pattern if any tasks failed
          if tasks_failed.positive?
            failed_agents = outputs.select { |o| o[:output].nil? }.map { |o| o[:agent_name] }
            stored = store_learning({
              title: "Team failure pattern: #{failed_agents.join(', ')} in #{strategy}",
              content: "#{tasks_failed} out of #{outputs.size} team members failed during #{strategy} execution. " \
                       "Failed agents: #{failed_agents.join(', ')}. Team: #{team&.name}.",
              category: "failure_mode",
              importance: 0.6,
              confidence: 0.7,
              extraction_method: "team_execution",
              tags: ["team", "failure", strategy].compact,
              source_execution_successful: false
            }, team: team, execution: team_execution)
            stored_count += 1 if stored
          end
        end

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from team execution")
        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Team execution learning extraction failed: #{e.message}")
        0
      end

      def reinforce_learning(learning_id)
        learning = Ai::CompoundLearning.find_by(id: learning_id, account: @account)
        return unless learning

        learning.boost_importance!(0.05)
        learning.record_access!
        learning
      end

      # Periodic maintenance: decay old, archive stale, detect contradictions
      def decay_and_consolidate
        decayed = 0
        archived = 0
        skipped = 0

        # Decay old learnings (skip recently event-processed)
        scope = Ai::CompoundLearning.active.for_account(@account.id)
          .where("updated_at < ?", 7.days.ago)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)

        scope.find_each do |learning|
          learning.decay_importance!
          decayed += 1
        end

        skipped = Ai::CompoundLearning.active.for_account(@account.id)
          .where("updated_at < ?", 7.days.ago)
          .where("last_event_processed_at >= ?", 24.hours.ago)
          .count

        # Archive very low importance learnings older than 30 days
        Ai::CompoundLearning.active.for_account(@account.id)
          .where("importance_score < ?", 0.1)
          .where("created_at < ?", 30.days.ago)
          .find_each do |learning|
            learning.deprecate!
            archived += 1
          end

        Rails.logger.info("[CompoundLearning] Maintenance: decayed=#{decayed} archived=#{archived} skipped_by_event=#{skipped}")
        { decayed: decayed, archived: archived, skipped_by_event: skipped }
      end

      # ==================================================
      # Analytics
      # ==================================================

      def compound_metrics
        base = Ai::CompoundLearning.for_account(@account.id)
        active_base = base.active

        total = base.count
        active_count = active_base.count
        by_category = active_base.group(:category).count
        by_scope = active_base.group(:scope).count
        avg_importance = active_base.average(:importance_score)&.to_f&.round(4) || 0
        avg_effectiveness = active_base.where.not(effectiveness_score: nil).average(:effectiveness_score)&.to_f&.round(4)

        most_effective = active_base
          .where.not(effectiveness_score: nil)
          .order(effectiveness_score: :desc)
          .limit(5)
          .map(&:learning_summary)

        recently_added = active_base
          .order(created_at: :desc)
          .limit(10)
          .map(&:learning_summary)

        # Compound score: weighted combination of learning volume, effectiveness, and coverage
        coverage = by_category.keys.length.to_f / Ai::CompoundLearning::CATEGORIES.length
        effectiveness_factor = avg_effectiveness || 0.5
        volume_factor = [active_count / 50.0, 1.0].min
        compound_score = ((coverage * 0.3 + effectiveness_factor * 0.4 + volume_factor * 0.3) * 100).round(1)

        {
          total_learnings: total,
          active_learnings: active_count,
          by_category: by_category,
          by_scope: by_scope,
          avg_importance: avg_importance,
          avg_effectiveness: avg_effectiveness,
          most_effective: most_effective,
          recently_added: recently_added,
          compound_score: compound_score
        }
      end

      def list_learnings(filters = {})
        scope = Ai::CompoundLearning.for_account(@account.id)

        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.by_category(filters[:category]) if filters[:category].present?
        scope = scope.where(scope: filters[:scope]) if filters[:scope].present?
        scope = scope.where("importance_score >= ?", filters[:min_importance]) if filters[:min_importance].present?
        scope = scope.for_team(filters[:team_id]) if filters[:team_id].present?

        if filters[:query].present?
          # Try semantic search first
          query_embedding = @embedding_service.generate(filters[:query])
          if query_embedding
            limit = filters[:limit] || 50
            return scope.active
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .limit(limit)
              .to_a
              .select { |e| e.neighbor_distance <= 0.6 }
          else
            scope = scope.where("content ILIKE ? OR title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%")
          end
        end

        scope = scope.order(created_at: :desc) unless filters[:query].present?
        scope.limit(filters[:limit] || 50)
      end

      # Store a learning with embedding generation and deduplication.
      # Returns true if a new learning was created, false if a near-duplicate was found and boosted.
      def store_learning(learning_data, team: nil, execution: nil)
        content = learning_data[:content]
        return false if content.blank?

        # Generate embedding for deduplication
        embedding = @embedding_service.generate(content)

        # Check for near-duplicates
        if embedding
          duplicates = Ai::CompoundLearning.find_similar(
            embedding,
            account_id: @account.id,
            threshold: DEDUP_THRESHOLD
          )

          if duplicates.any?
            # Boost existing instead of creating duplicate
            existing = duplicates.first
            existing.boost_importance!(0.03)
            existing.update!(
              confidence_score: [existing.confidence_score + 0.02, 1.0].min,
              metadata: existing.metadata.merge("last_duplicate_at" => Time.current.iso8601)
            )
            return false
          end

          # Check for potential contradictions (similar content, opposite outcomes)
          if learning_data[:source_execution_successful] == false
            conflicts = Ai::CompoundLearning.find_similar(
              embedding,
              account_id: @account.id,
              threshold: CONFLICT_THRESHOLD_LOW
            ).where(source_execution_successful: true)

            if conflicts.any?
              Rails.logger.info("[CompoundLearning] Potential contradiction detected with learning #{conflicts.first.id}")
            end
          end
        else
          # Fallback text dedup
          existing = Ai::CompoundLearning.active
            .for_account(@account.id)
            .where("content ILIKE ?", "%#{content.truncate(100)}%")
            .first

          if existing
            existing.boost_importance!(0.03)
            return false
          end
        end

        # Create new learning
        new_learning = Ai::CompoundLearning.create!(
          account: @account,
          ai_agent_team: team,
          source_agent_id: learning_data[:source_agent_id] || learning_data[:agent_id],
          source_execution: execution,
          category: learning_data[:category],
          content: content,
          title: learning_data[:title],
          importance_score: learning_data[:importance] || 0.5,
          confidence_score: learning_data[:confidence] || 0.5,
          extraction_method: learning_data[:extraction_method],
          source_execution_successful: learning_data[:source_execution_successful],
          embedding: embedding,
          tags: learning_data[:tags] || [],
          scope: "team"
        )

        # Enqueue async dedup check for the new learning
        begin
          WorkerJobService.enqueue_ai_dedup_learning(new_learning.id)
        rescue StandardError => e
          Rails.logger.warn("[CompoundLearning] Failed to enqueue dedup check: #{e.message}")
        end

        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[CompoundLearning] Failed to store learning: #{e.message}")
        false
      end

      private

      def boost_injected_learnings_on_success(execution)
        # Find learnings injected into this execution (those with recent injection timestamps)
        execution_start = execution.respond_to?(:created_at) ? execution.created_at : 1.hour.ago
        recently_injected = Ai::CompoundLearning
          .for_account(@account.id)
          .where(status: %w[active verified])
          .where("injection_count >= ?", 1)
          .where("last_injected_at >= ?", execution_start)

        recently_injected.find_each do |learning|
          learning.update_column(:confidence_score, [learning.confidence_score + 0.02, 1.0].min)
        end
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Confidence boost failed: #{e.message}")
      end

      def learning_freshness(updated_at)
        return "stale" unless updated_at

        age_days = (Time.current - updated_at) / 1.day
        if age_days < 7
          "fresh"
        elsif age_days < 30
          "aging"
        else
          "stale"
        end
      end

      def build_execution_metadata(execution)
        {
          duration_ms: execution.respond_to?(:duration_ms) ? execution.duration_ms : nil,
          total_cost_usd: execution.respond_to?(:total_cost_usd) ? execution.total_cost_usd : nil,
          tasks_completed: execution.respond_to?(:tasks_completed) ? execution.tasks_completed : nil,
          tasks_failed: execution.respond_to?(:tasks_failed) ? execution.tasks_failed : nil,
          tasks_total: execution.respond_to?(:tasks_total) ? execution.tasks_total : nil,
          team_name: execution.respond_to?(:agent_team) ? execution.agent_team&.name : nil
        }
      end

      def keyword_search(query)
        return Ai::CompoundLearning.none if query.blank?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
        return Ai::CompoundLearning.none if keywords.empty?

        conditions = keywords.map { |kw| "LOWER(content) LIKE '%#{Ai::CompoundLearning.sanitize_sql_like(kw)}%'" }
        Ai::CompoundLearning.active
          .for_account(@account.id)
          .where(conditions.join(" OR "))
          .order(importance_score: :desc)
          .limit(20)
      end

      def injection_enabled?
        Shared::FeatureFlagService.enabled?(:compound_learning_injection, @account)
      end

      def promotion_enabled?
        Shared::FeatureFlagService.enabled?(:compound_learning_promotion, @account)
      end

      def execution_quality_sufficient?(execution)
        return false unless execution.respond_to?(:status) && execution.status == "completed"
        return false unless execution.respond_to?(:output_data) && execution.output_data.present?
        true
      end
    end
  end
end
