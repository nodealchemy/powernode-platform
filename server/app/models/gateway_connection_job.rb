# frozen_string_literal: true

class GatewayConnectionJob < ApplicationRecord
  # Alias: DB column is "response" but code/API uses "result"
  alias_attribute :result, :response
  # Alias: DB column is "payload" but code/API uses "config_data"
  alias_attribute :config_data, :payload

  validates :gateway, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
  validates :operation, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :finished, -> { where(status: %w[completed failed]) }

  def finished?
    status.in?(%w[completed failed])
  end

  def success?
    status == "completed" && result&.dig("success") == true
  end

  def duration
    return nil unless completed_at && created_at
    completed_at - created_at
  end
end
