# frozen_string_literal: true

# Service for generating GDPR Article 20 data exports
class DataExportService
  EXPORT_DIR = Rails.root.join('tmp', 'data_exports')

  class ExportError < StandardError; end

  def initialize(data_export_request)
    @request = data_export_request
    @user = data_export_request.user
    @account = data_export_request.account
  end

  def execute
    @request.start_processing!
    FileUtils.mkdir_p(EXPORT_DIR)

    begin
      export_data = gather_export_data
      file_path = write_export_file(export_data)
      file_size = File.size(file_path)

      @request.complete!(file_path: file_path, file_size_bytes: file_size)
      { success: true, file_path: file_path }
    rescue => e
      @request.fail!(e.message)
      { success: false, error: e.message }
    end
  end

  private

  def gather_export_data
    data = {
      export_info: {
        generated_at: Time.current.iso8601,
        user_id: @user.id,
        account_id: @account.id,
        format: @request.format,
        export_type: @request.export_type
      }
    }

    data_types = @request.include_data_types.presence || DataExportRequest::EXPORTABLE_DATA_TYPES
    excluded = @request.exclude_data_types || []

    (data_types - excluded).each do |data_type|
      data[data_type] = export_data_type(data_type)
    end

    data
  end

  def export_data_type(data_type)
    case data_type
    when 'profile'
      export_profile
    when 'activity'
      export_activity
    when 'audit_logs'
      export_audit_logs
    when 'payments'
      export_payments
    when 'invoices'
      export_invoices
    when 'subscriptions'
      export_subscriptions
    when 'files'
      export_files_metadata
    when 'settings'
      export_settings
    when 'consents'
      export_consents
    when 'communications'
      export_communications
    else
      { note: "Data type '#{data_type}' not supported" }
    end
  end

  def export_profile
    {
      id: @user.id,
      email: @user.email,
      name: @user.name,
      created_at: @user.created_at.iso8601,
      email_verified_at: @user.email_verified_at&.iso8601,
      last_login_at: @user.last_login_at&.iso8601,
      status: @user.status,
      roles: @user.role_names,
      permissions: @user.permission_names
    }
  end

  def export_activity
    # Export last 365 days of activity
    AuditLog.where(user: @user)
            .where('created_at > ?', 365.days.ago)
            .order(created_at: :desc)
            .limit(10_000)
            .map do |log|
              {
                action: log.action,
                resource_type: log.resource_type,
                created_at: log.created_at.iso8601,
                ip_address: log.ip_address
              }
            end
  end

  def export_audit_logs
    AuditLog.where(user: @user)
            .order(created_at: :desc)
            .limit(10_000)
            .map do |log|
              {
                id: log.id,
                action: log.action,
                resource_type: log.resource_type,
                resource_id: log.resource_id,
                created_at: log.created_at.iso8601,
                details: log.details,
                ip_address: log.ip_address
              }
            end
  end

  def export_payments
    return [] unless defined?(Payment)

    Payment.joins(:subscription)
           .where(subscriptions: { account_id: @account.id })
           .order(created_at: :desc)
           .map do |payment|
             {
               id: payment.id,
               amount_cents: payment.amount_cents,
               currency: payment.currency,
               status: payment.status,
               payment_method: payment.payment_method,
               created_at: payment.created_at.iso8601
             }
           end
  end

  def export_invoices
    return [] unless defined?(Invoice)

    Invoice.where(account: @account)
           .order(created_at: :desc)
           .map do |invoice|
             {
               id: invoice.id,
               invoice_number: invoice.invoice_number,
               amount_cents: invoice.amount_cents,
               currency: invoice.currency,
               status: invoice.status,
               due_date: invoice.due_date&.iso8601,
               created_at: invoice.created_at.iso8601
             }
           end
  end

  def export_subscriptions
    return [] unless defined?(Subscription)

    Subscription.where(account: @account)
                .map do |sub|
                  {
                    id: sub.id,
                    plan_name: sub.plan&.name,
                    status: sub.status,
                    current_period_start: sub.current_period_start&.iso8601,
                    current_period_end: sub.current_period_end&.iso8601,
                    created_at: sub.created_at.iso8601
                  }
                end
  end

  def export_files_metadata
    return [] unless defined?(FileObject)

    FileObject.where(account: @account)
              .order(created_at: :desc)
              .map do |file|
                {
                  id: file.id,
                  name: file.name,
                  content_type: file.content_type,
                  size: file.size,
                  created_at: file.created_at.iso8601
                }
              end
  end

  def export_settings
    {
      preferences: @user.preferences,
      notification_preferences: @user.notification_preferences,
      two_factor_enabled: @user.two_factor_enabled?
    }
  end

  def export_consents
    UserConsent.where(user: @user)
               .order(created_at: :desc)
               .map do |consent|
                 {
                   consent_type: consent.consent_type,
                   granted: consent.granted,
                   version: consent.version,
                   granted_at: consent.granted_at&.iso8601,
                   withdrawn_at: consent.withdrawn_at&.iso8601
                 }
               end
  end

  def export_communications
    # Export email/notification history if available
    { note: 'Communication history export not yet implemented' }
  end

  def write_export_file(data)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "export_#{@user.id}_#{timestamp}"

    case @request.format
    when 'json'
      write_json_export(data, filename)
    when 'csv'
      write_csv_export(data, filename)
    when 'zip'
      write_zip_export(data, filename)
    else
      write_json_export(data, filename)
    end
  end

  def write_json_export(data, filename)
    file_path = EXPORT_DIR.join("#{filename}.json")
    File.write(file_path, JSON.pretty_generate(data))
    file_path.to_s
  end

  def write_csv_export(data, filename)
    require 'csv'
    dir_path = EXPORT_DIR.join(filename)
    FileUtils.mkdir_p(dir_path)

    data.each do |key, value|
      next unless value.is_a?(Array) && value.any?

      csv_path = dir_path.join("#{key}.csv")
      CSV.open(csv_path, 'w') do |csv|
        csv << value.first.keys
        value.each { |row| csv << row.values }
      end
    end

    # Create zip of CSV files
    zip_path = EXPORT_DIR.join("#{filename}.zip")
    system("cd #{dir_path} && zip -r #{zip_path} *.csv")
    FileUtils.rm_rf(dir_path)

    zip_path.to_s
  end

  def write_zip_export(data, filename)
    # Write JSON and create zip
    json_path = write_json_export(data, filename)
    zip_path = EXPORT_DIR.join("#{filename}.zip")

    system("cd #{EXPORT_DIR} && zip #{zip_path} #{File.basename(json_path)}")
    FileUtils.rm(json_path)

    zip_path.to_s
  end
end
