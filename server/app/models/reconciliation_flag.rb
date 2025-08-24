# frozen_string_literal: true

class ReconciliationFlag < ApplicationRecord
  include AASM
  
  belongs_to :payment, optional: true, foreign_key: :local_payment_id
  
  validates :flag_type, presence: true, inclusion: { 
    in: %w[missing_provider_payment missing_local_payment amount_mismatch duplicate_payment] 
  }
  validates :provider, presence: true, inclusion: { in: %w[stripe paypal] }
  validates :status, presence: true
  
  scope :pending, -> { where(status: 'pending') }
  scope :resolved, -> { where(status: 'resolved') }
  scope :requires_review, -> { where(requires_manual_review: true) }
  
  aasm column: :status do
    state :pending, initial: true
    state :investigating
    state :resolved
    state :dismissed
    
    event :start_investigation do
      transitions from: :pending, to: :investigating
    end
    
    event :resolve do
      transitions from: [:pending, :investigating], to: :resolved
      after do
        self.resolved_at = Time.current
      end
    end
    
    event :dismiss do
      transitions from: [:pending, :investigating], to: :dismissed
      after do
        self.resolved_at = Time.current
      end
    end
  end
  
  def high_priority?
    %w[missing_provider_payment amount_mismatch].include?(flag_type)
  end
  
  def requires_immediate_attention?
    high_priority? && requires_manual_review?
  end
end