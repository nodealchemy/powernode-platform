# frozen_string_literal: true

class GatewayConnectionJob < ApplicationRecord
  validates :gateway, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :finished, -> { where(status: %w[completed failed]) }

  def finished?
    status.in?(%w[completed failed])
  end

  def success?
    status == 'completed' && result&.dig('success') == true
  end

  def duration
    return nil unless completed_at && created_at
    completed_at - created_at
  end
end