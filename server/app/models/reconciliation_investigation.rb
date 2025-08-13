class ReconciliationInvestigation < ApplicationRecord
  include AASM
  
  belongs_to :local_payment, class_name: 'Payment', foreign_key: :local_payment_id, optional: true
  
  validates :investigation_type, presence: true, inclusion: { 
    in: %w[amount_mismatch duplicate_payment timing_discrepancy currency_mismatch] 
  }
  validates :status, presence: true
  validates :local_amount, :provider_amount, presence: true, numericality: true
  validates :amount_difference, presence: true, numericality: true
  
  scope :pending, -> { where(status: 'pending') }
  scope :in_progress, -> { where(status: 'investigating') }
  scope :completed, -> { where(status: ['resolved', 'closed']) }
  scope :significant_variance, -> { where('ABS(amount_difference) > 1000') } # $10+ difference
  
  aasm column: :status do
    state :pending, initial: true
    state :investigating
    state :resolved
    state :closed
    
    event :start_investigation do
      transitions from: :pending, to: :investigating
      after do
        self.investigation_started_at = Time.current
      end
    end
    
    event :resolve do
      transitions from: [:pending, :investigating], to: :resolved
      after do
        self.resolved_at = Time.current
      end
    end
    
    event :close do
      transitions from: [:pending, :investigating, :resolved], to: :closed
      after do
        self.closed_at = Time.current
      end
    end
  end
  
  def significant_variance?
    amount_difference.abs > 1000 # More than $10 difference
  end
  
  def variance_percentage
    return 0 if local_amount.zero?
    (amount_difference.to_f / local_amount * 100).round(2)
  end
  
  def investigation_duration
    return nil unless investigation_started_at
    end_time = resolved_at || closed_at || Time.current
    ((end_time - investigation_started_at) / 1.day).round(2)
  end
  
  def add_finding(finding_type, description, metadata = {})
    findings = self.findings || []
    findings << {
      type: finding_type,
      description: description,
      metadata: metadata,
      found_at: Time.current.iso8601
    }
    
    update!(findings: findings)
  end
  
  def resolution_summary
    return nil unless resolved? || closed?
    
    {
      investigation_duration_days: investigation_duration,
      findings_count: (findings || []).count,
      resolution_type: resolution_type,
      amount_corrected: amount_corrected,
      corrective_actions_taken: corrective_actions || []
    }
  end
end