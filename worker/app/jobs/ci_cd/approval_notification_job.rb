# frozen_string_literal: true

require 'mail'
require_relative '../../services/email_configuration_service'

module CiCd
  # Job to send approval notification emails for pipeline steps
  # Creates approval tokens and sends emails to all recipients
  class ApprovalNotificationJob < BaseJob
    sidekiq_options queue: 'email', retry: 3

    def execute(step_execution_id, recipients)
      logger.info "Sending approval notifications for step execution #{step_execution_id}"

      # Fetch step execution details from backend
      step_details = fetch_step_execution_details(step_execution_id)
      return { success: false, error: "Step execution not found" } unless step_details

      # Create approval tokens for each recipient
      tokens = create_approval_tokens(step_execution_id, recipients)
      return { success: false, error: "Failed to create approval tokens" } if tokens.empty?

      # Configure mail settings
      configure_mail_settings

      # Send emails to each recipient
      results = tokens.map do |token_data|
        send_approval_email(token_data, step_details)
      end

      successful = results.count { |r| r[:success] }
      failed = results.count { |r| !r[:success] }

      logger.info "Approval notifications sent: #{successful} successful, #{failed} failed"

      {
        success: true,
        step_execution_id: step_execution_id,
        notifications_sent: successful,
        notifications_failed: failed,
        results: results
      }
    end

    private

    def fetch_step_execution_details(step_execution_id)
      response = api_client.get("/api/v1/internal/step_approvals/#{step_execution_id}")
      response[:data]
    rescue BackendApiClient::ApiError => e
      logger.error "Failed to fetch step execution details: #{e.message}"
      nil
    end

    def create_approval_tokens(step_execution_id, recipients)
      response = api_client.post(
        "/api/v1/internal/step_approvals/#{step_execution_id}/create_tokens",
        { recipients: recipients }
      )

      response.dig(:data, "tokens") || []
    rescue BackendApiClient::ApiError => e
      logger.error "Failed to create approval tokens: #{e.message}"
      []
    end

    def configure_mail_settings
      settings = EmailConfigurationService.instance.settings

      Mail.defaults do
        delivery_method :smtp, {
          address: settings[:smtp_host] || ENV['SMTP_HOST'] || 'localhost',
          port: (settings[:smtp_port] || ENV['SMTP_PORT'] || 587).to_i,
          domain: settings[:smtp_domain] || ENV['SMTP_DOMAIN'] || 'powernode.dev',
          user_name: settings[:smtp_username] || ENV['SMTP_USERNAME'],
          password: settings[:smtp_password] || ENV['SMTP_PASSWORD'],
          authentication: settings[:smtp_authentication] ? :plain : nil,
          enable_starttls_auto: (settings[:smtp_encryption] || ENV['SMTP_ENCRYPTION'] || 'tls') == 'tls',
          ssl: settings[:smtp_encryption] == 'ssl'
        }.compact
      end
    end

    def send_approval_email(token_data, step_details)
      recipient_email = token_data["recipient_email"]
      raw_token = token_data["raw_token"]
      expires_at = token_data["expires_at"]

      # Build email URLs
      base_url = ENV['FRONTEND_URL'] || 'http://localhost:5173'
      approve_url = "#{base_url}/ci-cd/approve/#{raw_token}"
      reject_url = "#{base_url}/ci-cd/reject/#{raw_token}"
      dashboard_url = "#{base_url}/app/ci-cd/runs/#{step_details.dig('pipeline_run', 'id')}"

      # Build email content
      subject = build_email_subject(step_details)
      html_body = build_email_body(step_details, approve_url, reject_url, dashboard_url, expires_at)
      text_body = build_text_body(step_details, approve_url, reject_url, dashboard_url, expires_at)

      settings = EmailConfigurationService.instance.settings
      from_address = settings[:smtp_from_address] || ENV['SMTP_FROM_ADDRESS'] || 'noreply@powernode.dev'

      mail = Mail.new do
        from    from_address
        to      recipient_email
        subject subject

        html_part do
          content_type 'text/html; charset=UTF-8'
          body html_body
        end

        text_part do
          content_type 'text/plain; charset=UTF-8'
          body text_body
        end
      end

      mail.deliver!

      logger.info "Approval email sent to #{recipient_email}"
      { success: true, recipient: recipient_email }

    rescue StandardError => e
      logger.error "Failed to send approval email to #{recipient_email}: #{e.message}"
      { success: false, recipient: recipient_email, error: e.message }
    end

    def build_email_subject(step_details)
      pipeline_name = step_details.dig("pipeline", "name")
      step_name = step_details["step_name"]
      "[Action Required] Pipeline approval needed: #{pipeline_name} - #{step_name}"
    end

    def build_email_body(step_details, approve_url, reject_url, dashboard_url, expires_at)
      pipeline_name = step_details.dig("pipeline", "name")
      step_name = step_details["step_name"]
      step_type = step_details["step_type"]
      run_number = step_details.dig("pipeline_run", "run_number")
      trigger_type = step_details.dig("pipeline_run", "trigger_type")
      trigger_context = step_details.dig("pipeline_run", "trigger_context") || {}
      description = step_details.dig("pipeline_step", "configuration", "description")

      # Format trigger context
      trigger_info = format_trigger_context(trigger_type, trigger_context)

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
              line-height: 1.6;
              color: #333;
              max-width: 600px;
              margin: 0 auto;
              padding: 20px;
              background-color: #f5f5f5;
            }
            .container {
              background: white;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              overflow: hidden;
            }
            .header {
              background: linear-gradient(135deg, #4F46E5 0%, #7C3AED 100%);
              color: white;
              padding: 24px;
              text-align: center;
            }
            .header h1 {
              margin: 0;
              font-size: 24px;
              font-weight: 600;
            }
            .header p {
              margin: 8px 0 0;
              opacity: 0.9;
              font-size: 14px;
            }
            .content {
              padding: 24px;
            }
            .info-box {
              background: #F3F4F6;
              border-radius: 6px;
              padding: 16px;
              margin: 16px 0;
            }
            .info-row {
              display: flex;
              justify-content: space-between;
              padding: 8px 0;
              border-bottom: 1px solid #E5E7EB;
            }
            .info-row:last-child {
              border-bottom: none;
            }
            .info-label {
              color: #6B7280;
              font-size: 14px;
            }
            .info-value {
              font-weight: 500;
              font-size: 14px;
            }
            .description {
              background: #FEF3C7;
              border-left: 4px solid #F59E0B;
              padding: 12px 16px;
              margin: 16px 0;
              border-radius: 0 6px 6px 0;
            }
            .description p {
              margin: 0;
              color: #92400E;
            }
            .buttons {
              display: flex;
              gap: 16px;
              margin: 24px 0;
              justify-content: center;
            }
            .btn {
              display: inline-block;
              padding: 14px 32px;
              text-decoration: none;
              border-radius: 6px;
              font-weight: 600;
              font-size: 16px;
              text-align: center;
              min-width: 120px;
            }
            .btn-approve {
              background: #10B981;
              color: white;
            }
            .btn-reject {
              background: #EF4444;
              color: white;
            }
            .btn-view {
              background: #6B7280;
              color: white;
              font-size: 14px;
              padding: 10px 20px;
            }
            .expiry-notice {
              background: #FEE2E2;
              color: #991B1B;
              padding: 12px 16px;
              border-radius: 6px;
              text-align: center;
              font-size: 14px;
              margin-top: 16px;
            }
            .footer {
              padding: 16px 24px;
              font-size: 12px;
              color: #9CA3AF;
              text-align: center;
              border-top: 1px solid #E5E7EB;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>🔔 Approval Required</h1>
              <p>Pipeline step is waiting for your response</p>
            </div>
            <div class="content">
              <div class="info-box">
                <div class="info-row">
                  <span class="info-label">Pipeline</span>
                  <span class="info-value">#{escape_html(pipeline_name)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Step</span>
                  <span class="info-value">#{escape_html(step_name)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Step Type</span>
                  <span class="info-value">#{escape_html(step_type)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Run Number</span>
                  <span class="info-value">#{escape_html(run_number)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Trigger</span>
                  <span class="info-value">#{escape_html(trigger_info)}</span>
                </div>
              </div>

              #{description ? "<div class=\"description\"><p><strong>Step Description:</strong> #{escape_html(description)}</p></div>" : ''}

              <p style="text-align: center; color: #6B7280; margin: 24px 0 8px;">
                Please review and respond to this request:
              </p>

              <div class="buttons">
                <a href="#{approve_url}" class="btn btn-approve">✓ Approve</a>
                <a href="#{reject_url}" class="btn btn-reject">✗ Reject</a>
              </div>

              <div style="text-align: center; margin-top: 16px;">
                <a href="#{dashboard_url}" class="btn btn-view">View in Dashboard</a>
              </div>

              <div class="expiry-notice">
                ⏰ This request will expire on #{format_datetime(expires_at)}
              </div>
            </div>
            <div class="footer">
              <p>Powernode Platform - CI/CD Pipeline Approval</p>
              <p>If you did not expect this email, please ignore it.</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    def build_text_body(step_details, approve_url, reject_url, dashboard_url, expires_at)
      pipeline_name = step_details.dig("pipeline", "name")
      step_name = step_details["step_name"]
      run_number = step_details.dig("pipeline_run", "run_number")
      trigger_type = step_details.dig("pipeline_run", "trigger_type")
      trigger_context = step_details.dig("pipeline_run", "trigger_context") || {}
      description = step_details.dig("pipeline_step", "configuration", "description")

      trigger_info = format_trigger_context(trigger_type, trigger_context)

      text = <<~TEXT
        APPROVAL REQUIRED - Pipeline Step Waiting for Response
        ======================================================

        Pipeline: #{pipeline_name}
        Step: #{step_name}
        Run Number: #{run_number}
        Trigger: #{trigger_info}
      TEXT

      text += "\nDescription: #{description}\n" if description

      text += <<~TEXT

        ACTIONS:
        --------
        To APPROVE this step, visit:
        #{approve_url}

        To REJECT this step, visit:
        #{reject_url}

        To view the full pipeline run:
        #{dashboard_url}

        This request will expire on #{format_datetime(expires_at)}

        --
        Powernode Platform - CI/CD Pipeline Approval
      TEXT

      text
    end

    def format_trigger_context(trigger_type, context)
      case trigger_type
      when 'pull_request'
        pr_number = context['pull_request_number'] || context['pr_number']
        "Pull Request ##{pr_number}" if pr_number
      when 'push'
        branch = context['branch'] || context['ref']
        commit = context['commit_sha']&.first(7)
        parts = []
        parts << "Branch: #{branch}" if branch
        parts << "Commit: #{commit}" if commit
        parts.join(', ')
      when 'manual'
        "Manual trigger"
      when 'schedule'
        "Scheduled run"
      else
        trigger_type.humanize
      end || trigger_type.humanize
    end

    def format_datetime(iso_string)
      Time.parse(iso_string).strftime('%B %d, %Y at %H:%M %Z')
    rescue StandardError
      iso_string
    end

    def escape_html(text)
      return '' unless text

      text.to_s
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('"', '&quot;')
          .gsub("'", '&#39;')
    end
  end
end
