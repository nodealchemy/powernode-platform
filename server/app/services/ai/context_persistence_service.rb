# frozen_string_literal: true

class Ai::ContextPersistenceService
  class ContextError < StandardError; end
  class NotFoundError < ContextError; end
  class AccessDeniedError < ContextError; end
  class ValidationError < ContextError; end

  class << self
    # ==================== Context Management ====================

    # Create a new persistent context
    def create_context(account:, attributes:, created_by: nil)
      context = Ai::PersistentContext.new(
        account: account,
        created_by_user: created_by,
        name: attributes[:name],
        context_type: attributes[:context_type] || "knowledge_base",
        scope: attributes[:scope] || "account",
        description: attributes[:description],
        context_data: attributes[:context_data] || {},
        access_control: build_access_control(attributes[:access_control]),
        retention_policy: build_retention_policy(attributes[:retention_policy]),
        ai_agent_id: attributes[:ai_agent_id]
      )

      context.save!

      log_access(context: context, action: "create", accessor: created_by)

      context
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    # Get context by ID
    def find_context(account:, context_id:, accessor: nil)
      context = Ai::PersistentContext.find_by(id: context_id, account: account)
      raise NotFoundError, "Context not found: #{context_id}" unless context

      check_read_access!(context, accessor)
      log_access(context: context, action: "read", accessor: accessor)

      context
    end

    # List contexts for an account
    def list_contexts(account:, filters: {}, page: 1, per_page: 20)
      scope = Ai::PersistentContext.where(account: account)

      scope = scope.where(context_type: filters[:type]) if filters[:type].present?
      scope = scope.where(scope: filters[:scope]) if filters[:scope].present?
      scope = scope.where(ai_agent_id: filters[:agent_id]) if filters[:agent_id].present?
      scope = scope.active unless filters[:include_archived]

      scope.order(updated_at: :desc)
           .page(page)
           .per(per_page)
    end

    # Update context
    def update_context(account:, context_id:, attributes:, accessor: nil)
      context = find_context(account: account, context_id: context_id, accessor: accessor)
      check_write_access!(context, accessor)

      updatable = attributes.slice(:name, :description, :context_data, :access_control, :retention_policy)
      context.update!(updatable)

      log_access(context: context, action: "update", accessor: accessor)

      context
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    # Archive context
    def archive_context(account:, context_id:, accessor: nil)
      context = find_context(account: account, context_id: context_id, accessor: accessor)
      check_write_access!(context, accessor)

      context.archive!
      log_access(context: context, action: "archive", accessor: accessor)

      context
    end

    # Clone context
    def clone_context(account:, context_id:, new_name:, accessor: nil)
      original = find_context(account: account, context_id: context_id, accessor: accessor)

      new_context = create_context(
        account: account,
        created_by: accessor,
        attributes: {
          name: new_name,
          context_type: original.context_type,
          scope: original.scope,
          description: "Cloned from: #{original.name}",
          context_data: original.context_data.deep_dup,
          access_control: original.access_control.deep_dup,
          retention_policy: original.retention_policy.deep_dup
        }
      )

      # Clone entries
      original.ai_context_entries.active.find_each do |entry|
        new_context.ai_context_entries.create!(
          entry_key: entry.entry_key,
          entry_type: entry.entry_type,
          content: entry.content.deep_dup,
          metadata: entry.metadata.deep_dup,
          importance_score: entry.importance_score,
          source_type: "import",
          source_id: entry.id,
          created_by_user: accessor
        )
      end

      log_access(context: original, action: "clone", accessor: accessor)

      new_context
    end

    # ==================== Entry Management ====================

    # Add entry to context
    def add_entry(context:, attributes:, accessor: nil)
      check_write_access!(context, accessor)

      entry = context.ai_context_entries.new(
        entry_key: attributes[:key] || attributes[:entry_key],
        entry_type: attributes[:type] || attributes[:entry_type] || "fact",
        content: attributes[:content],
        content_text: attributes[:content_text],
        metadata: attributes[:metadata] || {},
        importance_score: attributes[:importance_score] || 0.5,
        source_type: attributes[:source_type] || "api",
        source_id: attributes[:source_id],
        created_by_user: accessor.is_a?(User) ? accessor : nil,
        ai_agent_id: accessor.is_a?(Ai::Agent) ? accessor.id : attributes[:agent_id],
        expires_at: attributes[:expires_at]
      )

      entry.save!

      log_access(context: context, action: "write", accessor: accessor, entry: entry)

      entry
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    # Get entry by key
    def get_entry(context:, key:, accessor: nil)
      check_read_access!(context, accessor)

      entry = context.ai_context_entries.active.find_by(entry_key: key)
      raise NotFoundError, "Entry not found: #{key}" unless entry

      log_access(context: context, action: "read", accessor: accessor, entry: entry)

      entry.read_content
      entry
    end

    # Update entry
    def update_entry(context:, key:, attributes:, accessor: nil, create_version: true)
      check_write_access!(context, accessor)

      entry = context.ai_context_entries.active.find_by(entry_key: key)
      raise NotFoundError, "Entry not found: #{key}" unless entry

      previous_value = entry.content.deep_dup

      if attributes[:content].present?
        entry = entry.update_content(attributes[:content], create_version: create_version)
      end

      # Update other attributes
      updatable = attributes.slice(:metadata, :importance_score, :expires_at)
      entry.update!(updatable) if updatable.present?

      log_access(
        context: context,
        action: "update",
        accessor: accessor,
        entry: entry,
        metadata: { previous_value: previous_value, new_value: entry.content }
      )

      entry
    end

    # Delete entry
    def delete_entry(context:, key:, accessor: nil)
      check_write_access!(context, accessor)

      entry = context.ai_context_entries.find_by(entry_key: key)
      raise NotFoundError, "Entry not found: #{key}" unless entry

      log_access(context: context, action: "delete", accessor: accessor, entry: entry)

      entry.destroy!
      true
    end

    # List entries
    def list_entries(context:, filters: {}, accessor: nil, page: 1, per_page: 50)
      check_read_access!(context, accessor)

      scope = context.ai_context_entries

      scope = scope.active unless filters[:include_archived]
      scope = scope.by_type(filters[:type]) if filters[:type].present?
      scope = scope.by_source(filters[:source]) if filters[:source].present?
      scope = scope.high_importance if filters[:high_importance]

      scope.order(importance_score: :desc, updated_at: :desc)
           .page(page)
           .per(per_page)
    end

    # ==================== Search ====================

    # Full-text search within context
    def search(context:, query:, accessor: nil, filters: {}, limit: 20)
      check_read_access!(context, accessor)

      scope = context.ai_context_entries.active.searchable

      # Text search
      if query.present?
        scope = scope.where(
          "content_text ILIKE :q OR entry_key ILIKE :q",
          q: "%#{query}%"
        )
      end

      # Apply filters
      scope = scope.by_type(filters[:type]) if filters[:type].present?
      scope = scope.where("importance_score >= ?", filters[:min_importance]) if filters[:min_importance].present?

      results = scope.order(importance_score: :desc).limit(limit)

      log_access(
        context: context,
        action: "search",
        accessor: accessor,
        metadata: { query: query, results_count: results.count }
      )

      results
    end

    # Semantic search using embeddings (requires pgvector)
    def semantic_search(context:, query_embedding:, accessor: nil, limit: 10, threshold: 0.7)
      check_read_access!(context, accessor)

      # Use pgvector's cosine distance operator
      results = context.ai_context_entries
        .active
        .where.not(embedding: nil)
        .select("*, (embedding <=> '#{query_embedding}') as distance")
        .where("(embedding <=> '#{query_embedding}') < ?", 1 - threshold)
        .order("distance ASC")
        .limit(limit)

      log_access(
        context: context,
        action: "search",
        accessor: accessor,
        metadata: { search_type: "semantic", results_count: results.count }
      )

      results
    end

    # ==================== Agent Memory ====================

    # Get or create agent memory context
    def get_agent_memory(account:, agent:, create_if_missing: true)
      context = Ai::PersistentContext.find_by(
        account: account,
        ai_agent_id: agent.id,
        context_type: "agent_memory"
      )

      if context.nil? && create_if_missing
        context = create_context(
          account: account,
          created_by: nil,
          attributes: {
            name: "#{agent.name} Memory",
            context_type: "agent_memory",
            scope: "agent",
            ai_agent_id: agent.id,
            description: "Persistent memory for agent: #{agent.name}"
          }
        )
      end

      context
    end

    # Store agent memory
    def store_memory(agent:, key:, value:, type: "memory", metadata: {})
      context = get_agent_memory(account: agent.account, agent: agent)

      existing = context.ai_context_entries.active.find_by(entry_key: key)

      if existing.present?
        update_entry(
          context: context,
          key: key,
          attributes: { content: value, metadata: metadata },
          accessor: agent
        )
      else
        add_entry(
          context: context,
          attributes: {
            key: key,
            type: type,
            content: value,
            metadata: metadata,
            agent_id: agent.id
          },
          accessor: agent
        )
      end
    end

    # Recall agent memory
    def recall_memory(agent:, key:)
      context = get_agent_memory(account: agent.account, agent: agent, create_if_missing: false)
      return nil unless context.present?

      entry = context.ai_context_entries.active.find_by(entry_key: key)
      entry&.read_content
    end

    # Get relevant memories for agent
    def get_relevant_memories(agent:, query: nil, limit: 10)
      context = get_agent_memory(account: agent.account, agent: agent, create_if_missing: false)
      return [] unless context.present?

      if query.present?
        search(context: context, query: query, accessor: agent, limit: limit)
      else
        context.ai_context_entries.active.recent.limit(limit)
      end
    end

    # ==================== Export/Import ====================

    # Export context data
    def export_context(context:, accessor: nil, format: :json)
      check_read_access!(context, accessor)

      data = {
        context: context.context_summary,
        entries: context.ai_context_entries.active.map(&:entry_snapshot),
        exported_at: Time.current.iso8601,
        version: "1.0"
      }

      log_access(context: context, action: "export", accessor: accessor)

      case format
      when :json
        data.to_json
      else
        data
      end
    end

    # Import context data
    def import_context(account:, data:, accessor: nil, merge: false)
      parsed = data.is_a?(String) ? JSON.parse(data).with_indifferent_access : data

      if merge && parsed[:context][:id].present?
        context = find_context(account: account, context_id: parsed[:context][:id], accessor: accessor)
      else
        context = create_context(
          account: account,
          created_by: accessor,
          attributes: parsed[:context].except(:id)
        )
      end

      # Import entries
      (parsed[:entries] || []).each do |entry_data|
        add_entry(
          context: context,
          attributes: entry_data.merge(source_type: "import"),
          accessor: accessor
        )
      end

      log_access(context: context, action: "import", accessor: accessor)

      context
    end

    private

    def check_read_access!(context, accessor)
      return true if context.access_control.blank?
      return true if accessor.nil? # System access
      return true if context.public_read?

      unless can_read?(context, accessor)
        raise AccessDeniedError, "Read access denied"
      end
    end

    def check_write_access!(context, accessor)
      return true if context.access_control.blank?
      return true if accessor.nil? # System access

      unless can_write?(context, accessor)
        raise AccessDeniedError, "Write access denied"
      end
    end

    def can_read?(context, accessor)
      access = context.access_control
      return true if access["public_read"]

      accessor_id = accessor.is_a?(Hash) ? accessor[:id] : accessor.id
      accessor_type = accessor.is_a?(Hash) ? accessor[:type] : accessor.class.name.underscore

      readers = access["readers"] || []
      readers.any? { |r| r["type"] == accessor_type && r["id"] == accessor_id }
    end

    def can_write?(context, accessor)
      access = context.access_control
      return true if access["public_write"]

      accessor_id = accessor.is_a?(Hash) ? accessor[:id] : accessor.id
      accessor_type = accessor.is_a?(Hash) ? accessor[:type] : accessor.class.name.underscore

      writers = access["writers"] || []
      writers.any? { |r| r["type"] == accessor_type && r["id"] == accessor_id }
    end

    def build_access_control(config)
      return {} if config.blank?

      {
        public_read: config[:public_read] || false,
        public_write: config[:public_write] || false,
        readers: config[:readers] || [],
        writers: config[:writers] || []
      }
    end

    def build_retention_policy(config)
      return {} if config.blank?

      {
        max_entries: config[:max_entries],
        max_age_days: config[:max_age_days],
        cleanup_strategy: config[:cleanup_strategy] || "oldest_first",
        archive_before_delete: config[:archive_before_delete] || true
      }
    end

    def log_access(context:, action:, accessor:, entry: nil, metadata: {})
      Ai::ContextAccessLog.log_access(
        context: context,
        action: action,
        accessor: accessor,
        entry: entry,
        metadata: metadata
      )
    rescue StandardError => e
      Rails.logger.error("Failed to log context access: #{e.message}")
    end
  end
end
