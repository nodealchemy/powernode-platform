# frozen_string_literal: true

module Ai
  class ExecutionEvent < ApplicationRecord
    belongs_to :account

    validates :source_type, presence: true
    validates :source_id, presence: true
    validates :event_type, presence: true
    validates :status, presence: true

    scope :by_source_type, ->(type) { where(source_type: type) if type.present? }
    scope :by_status, ->(status) { where(status: status) if status.present? }
    scope :by_event_type, ->(type) { where(event_type: type) if type.present? }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }
    scope :in_time_range, ->(from, to = Time.current) { where(created_at: from..to) }
    scope :with_errors, -> { where.not(error_class: nil) }
    scope :by_account, ->(account_id) { where(account_id: account_id) }

    def source
      source_type.constantize.find_by(id: source_id)
    rescue NameError
      nil
    end

    def error?
      error_class.present? || error_message.present?
    end
  end
end
