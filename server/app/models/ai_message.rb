# frozen_string_literal: true

class AiMessage < ApplicationRecord
  # Authentication
  # Access controlled through conversation ownership

  # Concerns
  include Auditable

  # Associations
  belongs_to :ai_conversation
  belongs_to :ai_agent
  belongs_to :user, optional: true
  belongs_to :parent_message, class_name: 'AiMessage', optional: true
  has_many :child_messages, class_name: 'AiMessage', foreign_key: 'parent_message_id', dependent: :nullify

  # Delegations
  delegate :account, to: :ai_conversation

  # Validations
  validates :message_id, presence: true, uniqueness: true
  validates :role, presence: true, inclusion: { in: %w[system user assistant function] }
  validates :content, presence: true
  validates :message_type, inclusion: { in: %w[text image audio video file code] }
  validates :status, inclusion: { in: %w[sent processing completed failed] }
  validates :token_count, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :sequence_number, presence: true, uniqueness: { scope: :ai_conversation_id }, on: :create
  validates :sequence_number, presence: true, on: :update

  # Scopes
  scope :by_role, ->(role) { where(role: role) }
  scope :user_messages, -> { where(role: 'user') }
  scope :assistant_messages, -> { where(role: 'assistant') }
  scope :system_messages, -> { where(role: 'system') }
  scope :by_type, ->(type) { where(message_type: type) }
  scope :text_messages, -> { where(message_type: 'text') }
  scope :with_attachments, -> { where.not(attachments: []) }
  scope :ordered, -> { order(:sequence_number) }
  scope :recent, -> { order(created_at: :desc) }
  scope :processed, -> { where(status: %w[completed failed]) }
  scope :pending_processing, -> { where(status: %w[sent processing]) }
  scope :edited, -> { where(is_edited: true) }

  # Callbacks
  before_validation :set_message_id, on: :create
  after_create :update_conversation_tokens_and_cost
  after_update :track_edit_history, if: :saved_change_to_content?

  # Methods
  def user_message?
    role == 'user'
  end

  def assistant_message?
    role == 'assistant'
  end

  def system_message?
    role == 'system'
  end

  def has_attachments?
    attachments.present? && attachments.any?
  end

  def text_content?
    message_type == 'text'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def mark_processing!
    update!(status: 'processing', processed_at: Time.current)
  end

  def mark_completed!(token_count: nil, cost: nil, metadata: {})
    update!(
      status: 'completed',
      processed_at: Time.current,
      token_count: token_count || self.token_count,
      cost_usd: cost || self.cost_usd,
      processing_metadata: processing_metadata.merge(metadata)
    )
  end

  def mark_failed!(error_message, metadata: {})
    update!(
      status: 'failed',
      error_message: error_message&.truncate(1000),
      processing_metadata: processing_metadata.merge(metadata),
      processed_at: Time.current
    )
  end

  def edit_content!(new_content, user: nil)
    raise ArgumentError, 'Cannot edit system messages' if system_message?
    
    old_content = content
    
    update!(
      content: new_content,
      is_edited: true,
      edited_at: Time.current
    )
    
    add_to_edit_history(old_content, user)
  end

  def attachment_summary
    return [] unless has_attachments?
    
    attachments.map do |attachment|
      {
        type: attachment['type'],
        name: attachment['name'],
        size: attachment['size'],
        url: attachment['url']
      }
    end
  end

  def content_preview(limit: 100)
    return content if content.length <= limit
    
    "#{content[0..limit-3]}..."
  end

  def message_data
    {
      id: message_id,
      conversation_id: ai_conversation.conversation_id,
      role: role,
      content: content,
      content_preview: content_preview,
      message_type: message_type,
      status: status,
      user: user&.full_name,
      sequence_number: sequence_number,
      token_count: token_count,
      cost_usd: cost_usd,
      has_attachments: has_attachments?,
      attachment_count: attachments.size,
      is_edited: is_edited?,
      created_at: created_at,
      processed_at: processed_at,
      parent_message_id: parent_message&.message_id
    }
  end

  def thread_messages
    # Get all messages in this thread (parent + children)
    messages = [self]
    messages += child_messages.ordered
    messages += parent_message.child_messages.ordered if parent_message
    messages.uniq.sort_by(&:sequence_number)
  end

  def can_edit?(user)
    return false if system_message?
    return true if self.user == user
    return true if user.permissions.include?('ai.messages.manage')
    
    false
  end

  def can_delete?(user)
    return false if system_message?
    return true if self.user == user
    return true if user.permissions.include?('ai.messages.manage')
    
    false
  end

  def to_param
    message_id
  end

  def display_role
    case role
    when 'user'
      user&.full_name || 'User'
    when 'assistant'
      ai_conversation.ai_agent&.name || ai_conversation.ai_provider.name
    when 'system'
      'System'
    else
      role.humanize
    end
  end

  private

  def set_message_id
    self.message_id ||= UUID7.generate
  end

  def update_conversation_tokens_and_cost
    return unless token_count > 0 || cost_usd > 0
    
    ai_conversation.increment!(:total_tokens, token_count)
    ai_conversation.increment!(:total_cost, cost_usd) if cost_usd > 0
  end

  def track_edit_history
    return unless is_edited?
    
    previous_content = content_before_last_save
    add_to_edit_history(previous_content)
  end

  def add_to_edit_history(previous_content, edited_by = nil)
    edit_entry = {
      content: previous_content,
      edited_at: Time.current.iso8601,
      edited_by: edited_by&.full_name || user&.full_name
    }
    
    new_history = (edit_history || []) + [edit_entry]
    update_column(:edit_history, new_history)
  end
end