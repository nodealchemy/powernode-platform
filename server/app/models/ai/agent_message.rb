# frozen_string_literal: true

module Ai
  class AgentMessage < ApplicationRecord
    self.table_name = "ai_agent_messages"

    # ==================== Associations ====================
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_run_id"

    # ==================== Validations ====================
    validates :message_id, presence: true, uniqueness: true
    validates :from_agent_id, presence: true
    validates :message_type, presence: true, inclusion: {
      in: %w[direct broadcast request response notification],
      message: "%{value} is not a valid message type"
    }
    validates :communication_pattern, presence: true, inclusion: {
      in: %w[request_response fire_and_forget publish_subscribe command_query],
      message: "%{value} is not a valid communication pattern"
    }
    validates :status, presence: true, inclusion: {
      in: %w[sent delivered acknowledged processed failed],
      message: "%{value} is not a valid status"
    }
    validates :message_content, presence: true
    validates :sequence_number, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # ==================== Scopes ====================
    scope :recent, -> { order(sequence_number: :desc) }
    scope :chronological, -> { order(sequence_number: :asc) }
    scope :for_run, ->(run_id) { where(ai_workflow_run_id: run_id) }
    scope :by_type, ->(type) { where(message_type: type) }
    scope :by_pattern, ->(pattern) { where(communication_pattern: pattern) }
    scope :by_status, ->(status) { where(status: status) }
    scope :from_agent, ->(agent_id) { where(from_agent_id: agent_id) }
    scope :to_agent, ->(agent_id) { where(to_agent_id: agent_id) }
    scope :between_agents, ->(from_id, to_id) { where(from_agent_id: from_id, to_agent_id: to_id) }
    scope :broadcasts, -> { where(message_type: "broadcast") }
    scope :direct_messages, -> { where(message_type: "direct") }
    scope :pending, -> { where(status: "sent") }
    scope :delivered, -> { where(status: %w[delivered acknowledged processed]) }
    scope :failed, -> { where(status: "failed") }

    # ==================== Callbacks ====================
    before_validation :generate_message_id, on: :create
    before_validation :set_sequence_number, on: :create
    after_create :broadcast_message_event

    # ==================== Instance Methods ====================

    # Get message summary
    def message_summary
      {
        id: id,
        message_id: message_id,
        from: from_agent_id,
        to: to_agent_id,
        type: message_type,
        pattern: communication_pattern,
        status: status,
        sequence: sequence_number,
        created_at: created_at,
        reply_to: in_reply_to_message_id
      }
    end

    # Full message details
    def message_details
      message_summary.merge(
        content: message_content,
        metadata: metadata,
        delivered_at: delivered_at,
        acknowledged_at: acknowledged_at
      )
    end

    # Check if message is a broadcast
    def broadcast?
      message_type == "broadcast"
    end

    # Check if message is direct
    def direct?
      message_type == "direct"
    end

    # Check if message is a request
    def request?
      message_type == "request"
    end

    # Check if message is a response
    def response?
      message_type == "response"
    end

    # Check if message has been delivered
    def delivered?
      %w[delivered acknowledged processed].include?(status)
    end

    # Check if message has been acknowledged
    def acknowledged?
      %w[acknowledged processed].include?(status)
    end

    # Mark message as delivered
    def mark_delivered!
      update!(
        status: "delivered",
        delivered_at: Time.current
      )
    end

    # Mark message as acknowledged
    def mark_acknowledged!
      update!(
        status: "acknowledged",
        acknowledged_at: Time.current
      )
    end

    # Mark message as processed
    def mark_processed!
      update!(status: "processed")
    end

    # Mark message as failed
    def mark_failed!(reason:)
      update!(
        status: "failed",
        metadata: metadata.merge(
          "failure_reason" => reason,
          "failed_at" => Time.current.iso8601
        )
      )
    end

    # Get conversation thread
    def conversation_thread
      thread_messages = []

      # Find root message
      root = self
      while root.in_reply_to_message_id.present?
        parent = self.class.find_by(message_id: root.in_reply_to_message_id)
        break unless parent
        root = parent
      end

      # Collect all messages in thread
      collect_thread_messages(root, thread_messages)

      thread_messages.sort_by(&:sequence_number)
    end

    # Create a reply to this message
    def create_reply(from_agent_id:, content:, type: "response")
      self.class.create!(
        workflow_run: workflow_run,
        from_agent_id: from_agent_id,
        to_agent_id: self.from_agent_id, # Reply to sender
        message_type: type,
        communication_pattern: communication_pattern,
        message_content: content,
        in_reply_to_message_id: message_id,
        metadata: {
          "reply_to" => message_id,
          "original_sender" => from_agent_id
        }
      )
    end

    # Get agent conversation history
    def self.conversation_between(agent_a_id, agent_b_id, workflow_run_id)
      where(ai_workflow_run_id: workflow_run_id)
        .where(
          "(from_agent_id = ? AND to_agent_id = ?) OR (from_agent_id = ? AND to_agent_id = ?)",
          agent_a_id, agent_b_id, agent_b_id, agent_a_id
        )
        .chronological
    end

    # Get unread messages for an agent
    def self.unread_for_agent(agent_id, workflow_run_id)
      where(ai_workflow_run_id: workflow_run_id, to_agent_id: agent_id)
        .where(status: %w[sent delivered])
        .chronological
    end

    private

    # Generate unique message ID
    def generate_message_id
      self.message_id ||= "msg_#{SecureRandom.hex(12)}"
    end

    # Set sequence number
    def set_sequence_number
      return if sequence_number.present?

      last_message = self.class.where(ai_workflow_run_id: ai_workflow_run_id)
                               .order(sequence_number: :desc)
                               .first

      self.sequence_number = last_message ? last_message.sequence_number + 1 : 0
    end

    # Broadcast message event via WebSocket
    def broadcast_message_event
      McpChannel.broadcast_to(
        "account_#{workflow_run.account_id}",
        {
          type: "agent_message",
          workflow_run_id: workflow_run.run_id,
          message: message_summary
        }
      )
    end

    # Recursively collect thread messages
    def collect_thread_messages(message, collection)
      collection << message

      replies = self.class.where(in_reply_to_message_id: message.message_id)
      replies.each do |reply|
        collect_thread_messages(reply, collection)
      end
    end
  end
end
