# frozen_string_literal: true

# ValidationRule defines reusable validation rules for workflow validation
class ValidationRule < ApplicationRecord
  # ==========================================
  # Concerns
  # ==========================================
  include Auditable

  # ==========================================
  # Validations
  # ==========================================
  validates :name, presence: true, uniqueness: true
  validates :category, presence: true, inclusion: {
    in: %w[structure connectivity data configuration performance security],
    message: 'must be a valid category'
  }
  validates :severity, presence: true, inclusion: {
    in: %w[error warning info],
    message: 'must be error, warning, or info'
  }

  validate :validate_configuration_format

  # ==========================================
  # Scopes
  # ==========================================
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :auto_fixable, -> { where(auto_fixable: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :errors, -> { where(severity: 'error') }
  scope :warnings, -> { where(severity: 'warning') }
  scope :info, -> { where(severity: 'info') }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create

  # ==========================================
  # Public Methods
  # ==========================================

  # Severity check methods
  def error?
    severity == 'error'
  end

  def warning?
    severity == 'warning'
  end

  def info?
    severity == 'info'
  end

  # Enable/disable methods
  def enable!
    update!(enabled: true)
  end

  def disable!
    update!(enabled: false)
  end

  # Get configuration value
  def config_value(key)
    configuration.dig(key)
  end

  # Check if rule has specific capability
  def has_capability?(capability)
    configuration.dig('capabilities', capability) == true
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.enabled = true if enabled.nil?
    self.auto_fixable = false if auto_fixable.nil?
    self.severity ||= 'warning'
    self.configuration ||= {}
  end

  def validate_configuration_format
    return if configuration.blank?

    unless configuration.is_a?(Hash)
      errors.add(:configuration, 'must be a hash')
    end
  end
end
