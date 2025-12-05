# frozen_string_literal: true

# Auditable concern for models that need audit logging
# Automatically tracks changes for compliance and security
module Auditable
  extend ActiveSupport::Concern

  included do
    # Audit log creation after record creation
    after_create :log_record_creation
    
    # Audit log updates after record changes
    after_update :log_record_update
    
    # Audit log deletion before record destruction
    before_destroy :log_record_deletion
  end

  private

  def log_record_creation
    AuditLog.log_action(
      action: 'created',
      resource: self,
      account: try(:account),
      new_values: auditable_attributes,
      source: 'system'
    )
  rescue => e
    Rails.logger.error "Failed to log record creation for #{self.class.name}##{id}: #{e.message}"
  end

  def log_record_update
    return unless saved_changes.present?

    # Filter out non-auditable changes (timestamps, etc.)
    relevant_changes = saved_changes.except('updated_at', 'created_at')
    return if relevant_changes.empty?

    old_values = relevant_changes.transform_values(&:first)
    new_values = relevant_changes.transform_values(&:last)

    AuditLog.log_action(
      action: 'updated',
      resource: self,
      account: try(:account),
      old_values: old_values,
      new_values: new_values,
      source: 'system'
    )
  rescue => e
    Rails.logger.error "Failed to log record update for #{self.class.name}##{id}: #{e.message}"
  end

  def log_record_deletion
    AuditLog.log_action(
      action: 'deleted',
      resource: self,
      account: try(:account),
      old_values: auditable_attributes,
      source: 'system'
    )
  rescue => e
    Rails.logger.error "Failed to log record deletion for #{self.class.name}##{id}: #{e.message}"
  end

  # Override this method in models to specify which attributes should be audited
  # By default, all attributes except sensitive ones are included
  def auditable_attributes
    attributes.except('id', 'created_at', 'updated_at', 'password_digest', 'encrypted_password')
  end
end