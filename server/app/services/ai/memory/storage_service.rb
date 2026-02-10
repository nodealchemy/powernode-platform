# frozen_string_literal: true

module Ai
  module Memory
    # StorageService - Unified storage for experiential, factual, shared learning, and pool memories
    # Consolidates ExperientialMemoryService, FactualMemoryService, SharedLearningService, MemoryPoolService
    class StorageService
      # === Experiential constants ===
      DEFAULT_DECAY_RATE = 0.01
      DEFAULT_IMPORTANCE = 0.5

      # === SharedLearning constants ===
      LEARNING_CATEGORIES = %w[fact pattern anti_pattern best_practice discovery].freeze

      LEARNING_MARKERS = {
        "Discovery:" => "discovery",
        "Pattern:" => "pattern",
        "Anti-pattern:" => "anti_pattern",
        "Best practice:" => "best_practice",
        "Fact:" => "fact"
      }.freeze

      attr_reader :account

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
      end

      # ==================== Experiential Memory ====================

      # Store an experiential memory
      def store_experiential(content:, context: {}, outcome_success: nil, importance: nil, tags: [], source_type: "agent_output")
        require_agent!

        @experiential_context ||= find_or_create_experiential_context
        @embedding_service ||= EmbeddingService.new(account: account)

        entry_key = generate_experiential_key(content)
        embedding = generate_embedding(content)

        entry = @experiential_context.context_entries.create!(
          entry_key: entry_key,
          entry_type: "memory",
          memory_type: "experiential",
          content: normalize_experiential_content(content),
          content_text: extract_experiential_text(content),
          metadata: { "context" => context, "embedding" => embedding },
          source_type: source_type,
          ai_agent_id: @agent.id,
          importance_score: importance || calculate_experiential_importance(outcome_success),
          confidence_score: calculate_experiential_confidence(context),
          decay_rate: DEFAULT_DECAY_RATE,
          context_tags: tags,
          task_context: context,
          outcome_success: outcome_success,
          version: 1
        )

        consolidate_experiential_if_needed(entry)
        entry
      end

      # Semantic search for relevant experiential memories
      def search_experiential(query, limit: 10, threshold: 0.7, tags: nil, outcome_filter: nil)
        require_agent!

        @experiential_context ||= find_or_create_experiential_context
        @embedding_service ||= EmbeddingService.new(account: account)

        query_embedding = @embedding_service.generate(query)
        return experiential_keyword_search(query, limit: limit, tags: tags) unless query_embedding

        scope = build_experiential_search_scope(tags: tags, outcome_filter: outcome_filter)

        if Ai::ContextEntry.embedding_column_exists?
          results = scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .to_a
            .select { |e| e.neighbor_distance <= 1.0 - threshold }

          keyword_results = experiential_keyword_search(query, limit: 5, tags: tags)
          merge_experiential_results(results, keyword_results, limit)
        else
          experiential_keyword_search(query, limit: limit, tags: tags)
        end
      end

      # Get experiential memories by outcome
      def successful_outcomes(limit: 20)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .successful_outcomes
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      def failed_outcomes(limit: 20)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .failed_outcomes
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Get recent experiential memories
      def recent_experiential(limit: 20)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .recent.limit(limit)
          .map(&:entry_details)
      end

      # Get most important experiential memories
      def most_important_experiential(limit: 20)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Get experiential memories by tag
      def experiential_by_tag(tag, limit: 20)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .with_tag(tag)
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Boost importance of an experiential memory
      def reinforce(entry_id, boost: 0.1)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        entry = @experiential_context.context_entries
          .active.experiential.find_by(id: entry_id)
        return unless entry

        entry.boost_importance!(boost)
        entry.touch(:last_accessed_at)
        entry
      end

      # Decay all experiential memories
      def apply_experiential_decay
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .where("decay_rate > 0")
          .find_each do |entry|
            entry.send(:decay_relevance)
            entry.save!
          end
      end

      # Consolidate similar experiential memories
      def consolidate_similar_experiential(similarity_threshold: 0.9)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        entries = @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .with_embedding
          .order(created_at: :desc)

        consolidated = 0

        entries.each do |entry|
          similar = find_similar_experiential_entries(entry, threshold: similarity_threshold)
          similar.each do |similar_entry|
            merge_experiential_entries(entry, similar_entry)
            consolidated += 1
          end
        end

        consolidated
      end

      # Remove old low-importance experiential memories
      def cleanup_experiential(max_age_days: 90, min_importance: 0.2)
        require_agent!
        @experiential_context ||= find_or_create_experiential_context

        cutoff = max_age_days.days.ago

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .where("created_at < ?", cutoff)
          .where("importance_score < ?", min_importance)
          .find_each(&:archive!)
      end

      # ==================== Factual Memory ====================

      # Store a verified fact
      def store_fact(key:, value:, metadata: {}, source_type: "system", source_id: nil)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        entry = @factual_context.context_entries.find_by(
          entry_key: key,
          archived_at: nil
        )

        content = normalize_factual_content(value)

        if entry
          if entry.content != content
            entry.update_content(content, create_version: true)
          else
            entry
          end
        else
          @factual_context.context_entries.create!(
            entry_key: key,
            entry_type: "fact",
            memory_type: "factual",
            content: content,
            metadata: metadata,
            source_type: source_type,
            source_id: source_id,
            ai_agent_id: @agent.id,
            importance_score: 1.0,
            confidence_score: 1.0,
            decay_rate: 0.0,
            version: 1
          )
        end
      end

      # Retrieve a specific fact by key
      def retrieve_fact(key)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        entry = @factual_context.context_entries
          .active.factual.find_by(entry_key: key)

        return nil unless entry

        entry.read_content
      end

      # Check if a fact exists
      def fact_exists?(key)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        @factual_context.context_entries
          .active.factual.exists?(entry_key: key)
      end

      # Get all facts for the agent
      def all_facts(limit: 100)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        @factual_context.context_entries
          .active.factual.by_agent(@agent.id)
          .order(created_at: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Search facts by key pattern
      def search_facts_by_key(pattern)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        @factual_context.context_entries
          .active.factual.by_agent(@agent.id)
          .where("entry_key ILIKE ?", "%#{pattern}%")
          .map(&:entry_details)
      end

      # Search facts by content
      def search_facts_by_content(query)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        @factual_context.context_entries
          .active.factual.by_agent(@agent.id)
          .where("content_text ILIKE ?", "%#{query}%")
          .map(&:entry_details)
      end

      # Remove a fact
      def remove_fact(key)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        entry = @factual_context.context_entries
          .active.factual.find_by(entry_key: key)
        entry&.archive!
      end

      # Bulk store facts
      def store_facts_batch(facts)
        facts.map do |fact|
          store_fact(
            key: fact[:key],
            value: fact[:value],
            metadata: fact[:metadata] || {},
            source_type: fact[:source_type] || "system",
            source_id: fact[:source_id]
          )
        end
      end

      # Get facts by category
      def facts_by_category(category)
        require_agent!
        @factual_context ||= find_or_create_factual_context

        @factual_context.context_entries
          .active.factual.by_agent(@agent.id)
          .where("metadata->>'category' = ?", category)
          .map(&:entry_details)
      end

      # Export all facts
      def export_facts
        all_facts(limit: 10_000).map do |fact|
          {
            key: fact[:entry_key],
            value: fact[:content],
            metadata: fact[:metadata],
            created_at: fact[:created_at]
          }
        end
      end

      # Import facts from export
      def import_facts(facts_data, overwrite: false)
        imported = 0
        skipped = 0

        facts_data.each do |fact|
          if fact_exists?(fact[:key]) && !overwrite
            skipped += 1
            next
          end

          store_fact(
            key: fact[:key],
            value: fact[:value],
            metadata: fact[:metadata] || {},
            source_type: "import"
          )
          imported += 1
        end

        { imported: imported, skipped: skipped }
      end

      # ==================== Shared Learning ====================

      # Record a single learning entry to a memory pool
      def record_learning(pool:, category:, content:, agent_id: nil)
        return unless LEARNING_CATEGORIES.include?(category)

        learnings = pool.data["learnings"] || []
        learnings << {
          "category" => category,
          "content" => content,
          "agent_id" => agent_id,
          "importance" => calculate_learning_importance(content, category),
          "recorded_at" => Time.current.iso8601
        }

        pool.data["learnings"] = learnings
        pool.last_accessed_at = Time.current
        pool.save!

        Rails.logger.info("[SharedLearning] Recorded #{category} learning in pool #{pool.pool_id}")
      end

      # Extract learnings from agent output using marker patterns
      def extract_learnings_from_output(output:, agent_id: nil)
        return [] if output.blank?

        text = output.is_a?(Hash) ? (output["text"] || output[:text] || output.to_json) : output.to_s
        learnings = []

        LEARNING_MARKERS.each do |marker, category|
          text.scan(/#{Regexp.escape(marker)}\s*(.+?)(?:\n|$)/i).each do |match|
            content = match[0].strip
            next if content.blank?

            learnings << {
              category: category,
              content: content,
              agent_id: agent_id
            }
          end
        end

        learnings
      end

      # Full pipeline: extract learnings from output and record them
      def process_completed_task(pool:, output:, agent_id: nil)
        learnings = extract_learnings_from_output(output: output, agent_id: agent_id)

        learnings.each do |learning|
          record_learning(
            pool: pool,
            category: learning[:category],
            content: learning[:content],
            agent_id: learning[:agent_id]
          )
        end

        Rails.logger.info("[SharedLearning] Processed #{learnings.size} learnings from task output")
        learnings.size
      end

      # Promote high-importance learnings from an execution pool to the global pool
      def promote_to_global(execution_pool:, min_importance: 0.7)
        global_pool = ensure_global_learning_pool
        learnings = execution_pool.data["learnings"] || []

        promoted = learnings.select { |l| (l["importance"] || 0) >= min_importance }
        return 0 if promoted.empty?

        global_learnings = global_pool.data["learnings"] || []

        promoted.each do |learning|
          next if global_learnings.any? { |gl| gl["content"] == learning["content"] }

          global_learnings << learning.merge(
            "promoted_from" => execution_pool.pool_id,
            "promoted_at" => Time.current.iso8601
          )
        end

        global_pool.data["learnings"] = global_learnings
        global_pool.last_accessed_at = Time.current
        global_pool.save!

        Rails.logger.info("[SharedLearning] Promoted #{promoted.size} learnings to global pool")
        promoted.size
      end

      # Retrieve relevant learnings using keyword-based search
      def retrieve_relevant_learnings(query:, limit: 10)
        return [] if query.blank?

        global_pool = find_global_learning_pool
        return [] unless global_pool

        all_learnings = global_pool.data["learnings"] || []
        return [] if all_learnings.empty?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }
        return all_learnings.first(limit) if keywords.empty?

        scored = all_learnings.map do |learning|
          content_lower = (learning["content"] || "").downcase
          score = keywords.count { |kw| content_lower.include?(kw) }
          importance = learning["importance"] || 0.5
          { learning: learning, score: score + importance }
        end

        scored
          .select { |s| s[:score] > 0 }
          .sort_by { |s| -s[:score] }
          .first(limit)
          .map { |s| s[:learning] }
      end

      # Format learnings for LLM prompt injection
      def build_learning_context(query:, max_chars: 2000)
        learnings = retrieve_relevant_learnings(query: query, limit: 20)
        return nil if learnings.empty?

        lines = ["## Shared Learnings"]
        used = lines.first.length + 2

        learnings.each do |learning|
          category = learning["category"]
          content = learning["content"]
          line = "- [#{category}] #{content}"
          break if used + line.length > max_chars

          lines << line
          used += line.length + 1
        end

        return nil if lines.size == 1

        lines.join("\n")
      end

      # ==================== Memory Pool ====================

      # Create a new memory pool
      def create_pool(params)
        pool = Ai::MemoryPool.new(
          account: account,
          name: params[:name],
          pool_type: params[:pool_type] || "shared",
          scope: params[:scope] || "execution",
          owner_agent_id: params[:owner_agent_id],
          team_id: params[:team_id],
          task_execution_id: params[:task_execution_id],
          data: params[:data] || {},
          access_control: build_pool_access_control(params[:access_control]),
          retention_policy: params[:retention_policy] || {},
          persist_across_executions: params[:persist_across_executions] || false,
          expires_at: params[:expires_at],
          metadata: params[:metadata] || {}
        )

        pool.save!
        Rails.logger.info("Created memory pool #{pool.pool_id} for account #{account.id}")
        pool
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to create memory pool: #{e.message}")
        raise
      end

      # Update pool attributes
      def update_pool(pool, params)
        updatable = params.slice(
          :name, :scope, :access_control, :retention_policy,
          :persist_across_executions, :expires_at, :metadata
        )

        pool.update!(updatable)
        Rails.logger.info("Updated memory pool #{pool.pool_id}")
        pool
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to update memory pool #{pool.pool_id}: #{e.message}")
        raise
      end

      # Delete pool with cleanup
      def delete_pool(pool)
        pool_id = pool.pool_id
        pool.destroy!
        Rails.logger.info("Deleted memory pool #{pool_id}")
        true
      end

      # Read data with access control
      def read_pool_data(pool, key, agent_id:)
        unless pool.accessible_by?(agent_id)
          Rails.logger.warn("Access denied: agent #{agent_id} reading pool #{pool.pool_id}")
          raise ArgumentError, "Access denied for agent #{agent_id}"
        end

        pool.touch(:last_accessed_at)
        keys = key.to_s.split(".")
        pool.data.dig(*keys)
      end

      # Write data with access control
      def write_pool_data(pool, key, value, agent_id:)
        unless pool.accessible_by?(agent_id)
          Rails.logger.warn("Access denied: agent #{agent_id} writing pool #{pool.pool_id}")
          raise ArgumentError, "Access denied for agent #{agent_id}"
        end

        keys = key.to_s.split(".")
        update_nested_hash(pool.data, keys, value)
        pool.data_size_bytes = pool.data.to_json.bytesize
        pool.last_accessed_at = Time.current
        pool.save!
        value
      end

      # Query pools with filters
      def query_pools(filters = {})
        scope = Ai::MemoryPool.where(account: account)

        scope = scope.where(scope: filters[:scope]) if filters[:scope].present?
        scope = scope.where(pool_type: filters[:pool_type]) if filters[:pool_type].present?
        scope = scope.where(owner_agent_id: filters[:agent_id]) if filters[:agent_id].present?
        scope = scope.where(team_id: filters[:team_id]) if filters[:team_id].present?
        scope = scope.where("expires_at IS NULL OR expires_at > ?", Time.current) unless filters[:include_expired]

        scope.order(updated_at: :desc)
      end

      # Auto-create a team execution pool with pre-structured data
      def create_team_execution_pool(team_execution:, team:)
        create_pool(
          name: "Team Execution: #{team.name} - #{team_execution&.id.to_s[0..7]}",
          pool_type: "team_shared",
          scope: "execution",
          team_id: team.id,
          task_execution_id: team_execution&.id,
          data: {
            "learnings" => [],
            "shared_state" => {},
            "member_outputs" => {}
          },
          access_control: { public: true, agents: [] },
          persist_across_executions: false,
          metadata: {
            "team_name" => team.name,
            "team_type" => team.team_type,
            "created_by" => "auto"
          }
        )
      end

      # Find or create the global learning pool for cross-execution learning
      def ensure_global_learning_pool
        Ai::MemoryPool.find_or_create_by!(
          account: account,
          name: "Global Learnings",
          pool_type: "global",
          scope: "persistent"
        ) do |pool|
          pool.data = { "learnings" => [] }
          pool.access_control = { "public" => true, "agents" => [] }
          pool.persist_across_executions = true
          pool.metadata = { "created_by" => "auto", "purpose" => "cross_execution_learning" }
        end
      rescue ActiveRecord::RecordInvalid
        Ai::MemoryPool.find_by(
          account: account,
          name: "Global Learnings",
          pool_type: "global",
          scope: "persistent"
        )
      end

      private

      def require_agent!
        raise ArgumentError, "agent is required for this operation" unless @agent
      end

      # === Experiential private helpers ===

      def find_or_create_experiential_context
        Ai::PersistentContext.find_or_create_by!(
          account_id: @account.id,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: @agent.id,
          name: "#{@agent.name} Experiential Memory"
        ) do |ctx|
          ctx.access_control = { "level" => "private" }
          ctx.retention_policy = {
            "max_entries" => 5000,
            "max_age_days" => 180,
            "archive_before_delete" => true
          }
        end
      end

      def generate_experiential_key(content)
        text = extract_experiential_text(content)
        "exp_#{Digest::SHA256.hexdigest(text)[0..15]}_#{Time.current.to_i}"
      end

      def generate_embedding(content)
        @embedding_service ||= EmbeddingService.new(account: account)
        text = extract_experiential_text(content)
        @embedding_service.generate(text)
      rescue StandardError => e
        Rails.logger.warn "Failed to generate embedding: #{e.message}"
        nil
      end

      def normalize_experiential_content(content)
        case content
        when Hash then content
        when String then { "text" => content }
        else { "value" => content.to_s }
        end
      end

      def extract_experiential_text(content)
        case content
        when Hash
          [
            content["text"],
            content["input_summary"],
            content["output_summary"],
            content["description"]
          ].compact.join(" ").truncate(2000)
        when String
          content.truncate(2000)
        else
          content.to_s.truncate(2000)
        end
      end

      def calculate_experiential_importance(outcome_success)
        case outcome_success
        when true then DEFAULT_IMPORTANCE
        when false then DEFAULT_IMPORTANCE + 0.2
        else DEFAULT_IMPORTANCE
        end
      end

      def calculate_experiential_confidence(context)
        base = 0.5
        base += 0.1 if context["task_id"].present?
        base += 0.1 if context["workflow_run_id"].present?
        base += 0.1 if context["duration_ms"].present?
        base += 0.1 if context["from_agent_id"].present?
        [base, 1.0].min
      end

      def build_experiential_search_scope(tags: nil, outcome_filter: nil)
        scope = @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)

        scope = scope.with_tag(tags) if tags.present?

        case outcome_filter
        when :success then scope.successful_outcomes
        when :failure then scope.failed_outcomes
        else scope
        end
      end

      def experiential_keyword_search(query, limit:, tags: nil)
        scope = build_experiential_search_scope(tags: tags)

        scope
          .where("content_text ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
          .order(importance_score: :desc)
          .limit(limit)
          .map { |e| e.entry_details.merge(similarity: 0.5) }
      end

      def merge_experiential_results(vector_results, keyword_results, limit)
        seen_ids = Set.new
        combined = []

        vector_results.each do |entry|
          next if seen_ids.include?(entry.id)

          seen_ids << entry.id
          combined << entry.entry_details.merge(similarity: entry.try(:similarity) || 0.8)
        end

        keyword_results.each do |entry|
          entry_id = entry[:id]
          next if seen_ids.include?(entry_id)

          seen_ids << entry_id
          combined << entry
        end

        combined.sort_by { |e| -(e[:similarity] || 0) }.first(limit)
      end

      def consolidate_experiential_if_needed(new_entry)
        entry_count = @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id).count

        return unless entry_count > 1000

        similar = find_similar_experiential_entries(new_entry, threshold: 0.95)
        similar.each { |e| merge_experiential_entries(new_entry, e) }
      end

      def find_similar_experiential_entries(entry, threshold:)
        return [] unless entry.embedding.present? && Ai::ContextEntry.embedding_column_exists?

        @experiential_context.context_entries
          .active.experiential.by_agent(@agent.id)
          .where.not(id: entry.id)
          .where("ai_context_entries.created_at < ?", entry.created_at)
          .nearest_neighbors(:embedding, entry.embedding, distance: "cosine")
          .limit(5)
          .to_a
          .select { |e| e.neighbor_distance <= 1.0 - threshold }
      end

      def merge_experiential_entries(target, source)
        target.importance_score = [target.importance_score, source.importance_score].max
        target.access_count += source.access_count
        target.context_tags = (target.context_tags + source.context_tags).uniq
        target.metadata = target.metadata.merge(
          "merged_from" => (target.metadata["merged_from"] || []) + [source.id]
        )

        target.save!
        source.archive!
      end

      # === Factual private helpers ===

      def find_or_create_factual_context
        Ai::PersistentContext.find_or_create_by!(
          account_id: @account.id,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: @agent.id,
          name: "#{@agent.name} Factual Memory"
        ) do |ctx|
          ctx.access_control = { "level" => "private" }
          ctx.retention_policy = { "max_entries" => 10_000 }
        end
      end

      def normalize_factual_content(value)
        case value
        when Hash
          value
        when String
          { "text" => value, "value" => value }
        when Numeric
          { "value" => value }
        when TrueClass, FalseClass
          { "value" => value }
        when Array
          { "items" => value }
        else
          { "value" => value.to_s }
        end
      end

      # === Shared Learning private helpers ===

      def calculate_learning_importance(content, category)
        base = case category
               when "anti_pattern" then 0.9
               when "best_practice" then 0.8
               when "pattern" then 0.7
               when "discovery" then 0.6
               when "fact" then 0.5
               else 0.5
               end

        length_boost = [content.to_s.length / 500.0, 0.1].min
        (base + length_boost).round(2)
      end

      def find_global_learning_pool
        Ai::MemoryPool.where(account: account, pool_type: "global", scope: "persistent")
                      .where("name LIKE ?", "%Global Learnings%")
                      .first
      end

      # === Memory Pool private helpers ===

      def build_pool_access_control(config)
        return { "public" => false, "agents" => [] } if config.blank?

        {
          "public" => config[:public] || false,
          "agents" => config[:agents] || [],
          "read_only_agents" => config[:read_only_agents] || []
        }
      end

      def update_nested_hash(hash, keys, value)
        if keys.length == 1
          hash[keys.first] = value
        else
          key = keys.shift
          hash[key] ||= {}
          update_nested_hash(hash[key], keys, value)
        end
      end
    end
  end
end
