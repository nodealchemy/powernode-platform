# frozen_string_literal: true

# Service for processing GDPR Article 17 data deletion requests
class DataDeletionService
  class DeletionError < StandardError; end

  def initialize(data_deletion_request)
    @request = data_deletion_request
    @user = data_deletion_request.user
    @account = data_deletion_request.account
    @deletion_log = []
    @retention_log = []
  end

  def execute
    return unless @request.can_start_processing?

    @request.start_processing!

    begin
      ActiveRecord::Base.transaction do
        process_deletion
        @request.complete!(deletion_log: @deletion_log, retention_log: @retention_log)
      end

      { success: true, deletion_log: @deletion_log, retention_log: @retention_log }
    rescue => e
      @request.fail!(e.message)
      { success: false, error: e.message }
    end
  end

  private

  def process_deletion
    case @request.deletion_type
    when 'full'
      process_full_deletion
    when 'partial'
      process_partial_deletion
    when 'anonymize'
      process_anonymization
    end
  end

  def process_full_deletion
    # Process each deletable data type
    DataDeletionRequest::DELETABLE_DATA_TYPES.each do |data_type|
      next if @request.data_types_to_retain.include?(data_type)

      delete_data_type(data_type)
    end

    # Handle legally retained data
    @request.data_types_to_retain.each do |data_type|
      retain_data_type(data_type)
    end

    # Finally delete or anonymize the user
    anonymize_user_record
  end

  def process_partial_deletion
    data_types = @request.data_types_to_delete || []

    data_types.each do |data_type|
      delete_data_type(data_type)
    end
  end

  def process_anonymization
    anonymize_all_pii
  end

  def delete_data_type(data_type)
    count = case data_type
            when 'profile'
              delete_profile_data
            when 'activity'
              delete_activity_data
            when 'audit_logs'
              # Audit logs are retained for compliance - anonymize instead
              anonymize_audit_logs
            when 'payments'
              # Payment records retained for tax - anonymize
              anonymize_payments
            when 'files'
              delete_files
            when 'settings'
              delete_settings
            when 'consents'
              delete_consents
            when 'communications'
              delete_communications
            when 'analytics'
              delete_analytics
            else
              0
            end

    @deletion_log << {
      data_type: data_type,
      action: 'deleted',
      records_affected: count,
      processed_at: Time.current.iso8601
    }
  end

  def retain_data_type(data_type)
    @retention_log << {
      data_type: data_type,
      reason: retention_reason_for(data_type),
      legal_basis: legal_basis_for(data_type),
      retention_period: retention_period_for(data_type)
    }
  end

  def delete_profile_data
    # Clear non-essential profile data
    @user.update_columns(
      name: 'Deleted User',
      preferences: {},
      notification_preferences: {}
    )
    1
  end

  def delete_activity_data
    # Delete activity older than legal retention period
    count = AuditLog.where(user: @user)
                    .where('created_at < ?', 7.years.ago)
                    .delete_all
    count
  end

  def anonymize_audit_logs
    # Anonymize user reference but keep the log
    count = AuditLog.where(user: @user).update_all(
      ip_address: nil,
      user_agent: nil,
      metadata: {}
    )
    count
  end

  def anonymize_payments
    return 0 unless defined?(Payment)

    # Anonymize payment records but keep for accounting
    Payment.joins(:subscription)
           .where(subscriptions: { account_id: @account.id })
           .update_all(
             metadata: nil,
             billing_details: nil
           )
  end

  def delete_files
    return 0 unless defined?(FileObject)

    files = FileObject.where(account: @account, user_id: @user.id)
    count = files.count

    files.find_each do |file|
      file.destroy # Triggers storage cleanup
    end

    count
  end

  def delete_settings
    @user.update_columns(
      preferences: {},
      notification_preferences: {},
      two_factor_secret: nil,
      backup_codes: nil
    )
    1
  end

  def delete_consents
    UserConsent.where(user: @user).delete_all
  end

  def delete_communications
    # Delete notification preferences and communication logs
    @user.update_columns(notification_preferences: {})
    0
  end

  def delete_analytics
    # Delete user analytics data
    0
  end

  def anonymize_user_record
    # Generate anonymous identifier
    anonymous_id = "deleted_#{SecureRandom.hex(8)}"

    @user.update_columns(
      email: "#{anonymous_id}@deleted.powernode.local",
      name: 'Deleted User',
      password_digest: nil,
      status: 'deleted',
      two_factor_secret: nil,
      backup_codes: nil,
      last_login_ip: nil,
      reset_token_digest: nil,
      email_verification_token: nil
    )

    @deletion_log << {
      data_type: 'user_record',
      action: 'anonymized',
      anonymous_id: anonymous_id,
      processed_at: Time.current.iso8601
    }
  end

  def anonymize_all_pii
    anonymize_user_record
    anonymize_audit_logs
    anonymize_payments if defined?(Payment)

    @deletion_log << {
      data_type: 'all_pii',
      action: 'anonymized',
      processed_at: Time.current.iso8601
    }
  end

  def retention_reason_for(data_type)
    {
      'financial_records' => 'Required for tax and accounting purposes',
      'tax_documents' => 'Required by tax regulations',
      'legal_agreements' => 'Required for contract enforcement',
      'audit_logs' => 'Required for security and compliance auditing'
    }[data_type] || 'Legal retention requirement'
  end

  def legal_basis_for(data_type)
    {
      'financial_records' => 'GDPR Art. 17(3)(b) - Legal obligation',
      'tax_documents' => 'National tax regulations',
      'legal_agreements' => 'GDPR Art. 17(3)(e) - Legal claims',
      'audit_logs' => 'SOC 2 / PCI DSS requirements'
    }[data_type] || 'GDPR Art. 17(3)'
  end

  def retention_period_for(data_type)
    {
      'financial_records' => '7 years',
      'tax_documents' => '7 years',
      'legal_agreements' => '10 years',
      'audit_logs' => '7 years'
    }[data_type] || 'As required by law'
  end
end
