# frozen_string_literal: true

require 'mail'
require_relative '../../services/email_configuration_service'

module AiWorkflow
  # Job to send approval notification emails for AI workflow human_approval nodes
  # Creates approval tokens and sends emails to all approvers
  class ApprovalNotificationJob < BaseJob
    sidekiq_options queue: 'email', retry: 3

    def execute(node_execution_id, approvers)
      logger.info "Sending AI workflow approval notifications for node execution #{node_execution_id}"

      # Fetch node execution details from backend
      execution_details = fetch_execution_details(node_execution_id)
      return { success: false, error: "Node execution not found" } unless execution_details

      # Create approval tokens for each approver
      tokens = create_approval_tokens(node_execution_id, approvers)
      return { success: false, error: "Failed to create approval tokens" } if tokens.empty?

      # Configure mail settings
      configure_mail_settings

      # Send emails to each approver
      results = tokens.map do |token_data|
        send_approval_email(token_data, execution_details)
      end

      successful = results.count { |r| r[:success] }
      failed = results.count { |r| !r[:success] }

      logger.info "AI workflow approval notifications sent: #{successful} successful, #{failed} failed"

      {
        success: true,
        node_execution_id: node_execution_id,
        notifications_sent: successful,
        notifications_failed: failed,
        results: results
      }
    end

    private

    def fetch_execution_details(node_execution_id)
      response = api_client.get("/api/v1/internal/ai_workflow_approvals/#{node_execution_id}")
      response[:data]
    rescue BackendApiClient::ApiError => e
      logger.error "Failed to fetch AI workflow execution details: #{e.message}"
      nil
    end

    def create_approval_tokens(node_execution_id, approvers)
      # Format approvers for the API
      recipients = approvers.map do |approver|
        if approver.is_a?(Hash)
          approver
        else
          # Assume it's an email string
          { "type" => "email", "value" => approver }
        end
      end

      response = api_client.post(
        "/api/v1/internal/ai_workflow_approvals/#{node_execution_id}/create_tokens",
        { recipients: recipients }
      )

      response.dig(:data, "tokens") || []
    rescue BackendApiClient::ApiError => e
      logger.error "Failed to create AI workflow approval tokens: #{e.message}"
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

    def send_approval_email(token_data, execution_details)
      recipient_email = token_data["recipient_email"]
      raw_token = token_data["raw_token"]
      expires_at = token_data["expires_at"]

      # Build email URLs
      base_url = ENV['FRONTEND_URL'] || 'http://localhost:5173'
      approve_url = "#{base_url}/ai-workflows/approve/#{raw_token}"
      reject_url = "#{base_url}/ai-workflows/reject/#{raw_token}"
      dashboard_url = "#{base_url}/app/ai/workflows/#{execution_details.dig('workflow', 'id')}/runs/#{execution_details.dig('workflow_run', 'id')}"

      # Build email content
      subject = build_email_subject(execution_details)
      html_body = build_email_body(execution_details, approve_url, reject_url, dashboard_url, expires_at)
      text_body = build_text_body(execution_details, approve_url, reject_url, dashboard_url, expires_at)

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

      logger.info "AI workflow approval email sent to #{recipient_email}"
      { success: true, recipient: recipient_email }

    rescue StandardError => e
      logger.error "Failed to send AI workflow approval email to #{recipient_email}: #{e.message}"
      { success: false, recipient: recipient_email, error: e.message }
    end

    def build_email_subject(execution_details)
      workflow_name = execution_details.dig("workflow", "name")
      node_name = execution_details.dig("node", "name") || "Human Approval"
      "[Action Required] AI Workflow approval needed: #{workflow_name} - #{node_name}"
    end

    def build_email_body(execution_details, approve_url, reject_url, dashboard_url, expires_at)
      workflow_name = execution_details.dig("workflow", "name")
      node_name = execution_details.dig("node", "name") || "Human Approval"
      run_id = execution_details.dig("workflow_run", "run_id")
      trigger_type = execution_details.dig("workflow_run", "trigger_type")
      approval_message = execution_details["approval_message"]

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
              background: linear-gradient(135deg, #8B5CF6 0%, #6366F1 100%);
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
            .message-box {
              background: #EDE9FE;
              border-left: 4px solid #8B5CF6;
              padding: 12px 16px;
              margin: 16px 0;
              border-radius: 0 6px 6px 0;
            }
            .message-box p {
              margin: 0;
              color: #5B21B6;
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
              <h1>🤖 AI Workflow Approval</h1>
              <p>Your approval is needed to continue</p>
            </div>
            <div class="content">
              <div class="info-box">
                <div class="info-row">
                  <span class="info-label">Workflow</span>
                  <span class="info-value">#{escape_html(workflow_name)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Step</span>
                  <span class="info-value">#{escape_html(node_name)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Run ID</span>
                  <span class="info-value">#{escape_html(run_id)}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Trigger</span>
                  <span class="info-value">#{escape_html(trigger_type&.humanize || 'Manual')}</span>
                </div>
              </div>

              #{approval_message ? "<div class=\"message-box\"><p><strong>Message:</strong> #{escape_html(approval_message)}</p></div>" : ''}

              <p style="text-align: center; color: #6B7280; margin: 24px 0 8px;">
                Please review and respond to this request:
              </p>

              <div class="buttons">
                <a href="#{approve_url}" class="btn btn-approve">✓ Approve</a>
                <a href="#{reject_url}" class="btn btn-reject">✗ Reject</a>
              </div>

              <div style="text-align: center; margin-top: 16px;">
                <a href="#{dashboard_url}" class="btn btn-view">View Workflow Run</a>
              </div>

              <div class="expiry-notice">
                ⏰ This request will expire on #{format_datetime(expires_at)}
              </div>
            </div>
            <div class="footer">
              <p>Powernode Platform - AI Workflow Approval</p>
              <p>If you did not expect this email, please ignore it.</p>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    def build_text_body(execution_details, approve_url, reject_url, dashboard_url, expires_at)
      workflow_name = execution_details.dig("workflow", "name")
      node_name = execution_details.dig("node", "name") || "Human Approval"
      run_id = execution_details.dig("workflow_run", "run_id")
      trigger_type = execution_details.dig("workflow_run", "trigger_type")
      approval_message = execution_details["approval_message"]

      text = <<~TEXT
        AI WORKFLOW APPROVAL REQUIRED
        =============================

        Workflow: #{workflow_name}
        Step: #{node_name}
        Run ID: #{run_id}
        Trigger: #{trigger_type&.humanize || 'Manual'}
      TEXT

      text += "\nMessage: #{approval_message}\n" if approval_message

      text += <<~TEXT

        ACTIONS:
        --------
        To APPROVE this step, visit:
        #{approve_url}

        To REJECT this step, visit:
        #{reject_url}

        To view the full workflow run:
        #{dashboard_url}

        This request will expire on #{format_datetime(expires_at)}

        --
        Powernode Platform - AI Workflow Approval
      TEXT

      text
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
