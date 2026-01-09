# frozen_string_literal: true

module Ai
  class ContextAccessLog < ApplicationRecord
    self.table_name = "ai_context_access_logs"

    # ==================== Constants ====================
    ACTIONS = %w[read write update delete search export import clone archive unarchive].freeze
    ACCESS_TYPES = %w[user agent workflow api system].freeze

    # ==================== Associations ====================
    belongs_to :persistent_context, class_name: "Ai::PersistentContext", foreign_key: "ai_persistent_context_id"
    belongs_to :context_entry, class_name: "Ai::ContextEntry", foreign_key: "ai_context_entry_id", optional: true
    belongs_to :account
    belongs_to :user, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    # ==================== Validations ====================
    validates :action, presence: true, inclusion: { in: ACTIONS }
    validates :access_type, inclusion: { in: ACCESS_TYPES }, allow_nil: true

    # ==================== Scopes ====================
    scope :successful, -> { where(success: true) }
    scope :failed, -> { where(success: false) }
    scope :by_action, ->(action) { where(action: action) }
    scope :by_access_type, ->(type) { where(access_type: type) }
    scope :by_user, ->(user_id) { where(user_id: user_id) }
    scope :by_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :recent, -> { order(created_at: :desc) }
    scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
    scope :this_week, -> { where("created_at >= ?", 1.week.ago) }
    scope :writes, -> { where(action: %w[write update delete]) }
    scope :reads, -> { where(action: %w[read search]) }

    # ==================== Callbacks ====================
    before_save :sanitize_jsonb_fields

    # ==================== Class Methods ====================
    class << self
      def log_access(context:, action:, accessor: nil, entry: nil, success: true, error: nil, metadata: {})
        accessor_type, accessor_id = parse_accessor(accessor)

        create!(
          ai_persistent_context_id: context.id,
          ai_context_entry_id: entry&.id,
          account: context.account,
          action: action,
          access_type: accessor_type,
          user_id: accessor_type == "user" ? accessor_id : nil,
          ai_agent_id: accessor_type == "agent" ? accessor_id : nil,
          success: success,
          error_message: error,
          metadata: metadata
        )
      end

      def log_read(context:, accessor:, entry: nil, metadata: {})
        log_access(context: context, action: "read", accessor: accessor, entry: entry, metadata: metadata)
      end

      def log_write(context:, accessor:, entry: nil, previous_value: nil, new_value: nil, metadata: {})
        log_access(
          context: context,
          action: "write",
          accessor: accessor,
          entry: entry,
          metadata: metadata.merge(
            previous_value: previous_value,
            new_value: new_value,
            changes_summary: summarize_changes(previous_value, new_value)
          )
        )
      end

      def log_search(context:, accessor:, query:, results_count:, metadata: {})
        log_access(
          context: context,
          action: "search",
          accessor: accessor,
          metadata: metadata.merge(query: query, results_count: results_count)
        )
      end

      private

      def parse_accessor(accessor)
        case accessor
        when User
          ["user", accessor.id]
        when Ai::Agent
          ["agent", accessor.id]
        when Hash
          [accessor[:type], accessor[:id]]
        when nil
          ["system", nil]
        else
          ["unknown", nil]
        end
      end

      def summarize_changes(previous_value, new_value)
        return {} if previous_value.nil? && new_value.nil?

        {
          had_previous: previous_value.present?,
          has_new: new_value.present?,
          size_change: (new_value.to_json.bytesize rescue 0) - (previous_value.to_json.bytesize rescue 0)
        }
      end
    end

    # ==================== Instance Methods ====================

    def log_summary
      {
        id: id,
        action: action,
        access_type: access_type,
        success: success,
        created_at: created_at,
        context_id: ai_persistent_context_id,
        entry_id: ai_context_entry_id
      }
    end

    def log_details
      log_summary.merge(
        user_id: user_id,
        agent_id: ai_agent_id,
        request_id: request_id,
        ip_address: ip_address,
        user_agent: user_agent,
        previous_value: previous_value,
        new_value: new_value,
        changes_summary: changes_summary,
        metadata: metadata,
        error_message: error_message
      )
    end

    def accessor_info
      if user_id.present?
        { type: "user", id: user_id, name: user&.full_name }
      elsif ai_agent_id.present?
        { type: "agent", id: ai_agent_id, name: agent&.name }
      else
        { type: access_type || "system", id: nil, name: nil }
      end
    end

    def is_write_operation?
      %w[write update delete].include?(action)
    end

    def is_read_operation?
      %w[read search].include?(action)
    end

    private

    def sanitize_jsonb_fields
      self.changes_summary = {} if changes_summary.blank?
      self.metadata = {} if metadata.blank?
    end
  end
end
