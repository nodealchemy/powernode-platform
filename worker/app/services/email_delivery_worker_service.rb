# frozen_string_literal: true

require_relative 'base_worker_service'
require 'mail'
require 'net/smtp'

class EmailDeliveryWorkerService < BaseWorkerService
  EMAIL_TYPES = %w[
    password_reset
    email_verification
    welcome_email
    subscription_created
    subscription_cancelled
    payment_succeeded
    payment_failed
    invoice_generated
    trial_ending
    dunning_notification
    report_generated
    system_notification
  ].freeze

  def initialize
    super
    configure_mail_settings
  end

  # Send email with comprehensive error handling and tracking
  def send_email(to:, subject:, body:, email_type:, account_id: nil, user_id: nil, template: nil, template_data: {}, **options)
    validate_required_params({ to: to, subject: subject, body: body, email_type: email_type }, :to, :subject, :body, :email_type)
    
    unless EMAIL_TYPES.include?(email_type)
      return error_response("Unsupported email type: #{email_type}")
    end

    log_info("Sending email", email_type: email_type, to: to, subject: subject)

    begin
      # Create email delivery record for tracking
      delivery_record = create_email_delivery_record(
        to: to,
        subject: subject,
        email_type: email_type,
        account_id: account_id,
        user_id: user_id,
        template: template,
        template_data: template_data
      )

      unless delivery_record[:success]
        return error_response("Failed to create delivery record: #{delivery_record[:error]}")
      end

      delivery_id = delivery_record[:data]['id']

      # Process template if provided
      final_body = template ? render_email_template(template, template_data, body) : body

      # Create and configure mail message
      mail = Mail.new do
        from     options[:from] || ENV['SMTP_FROM_ADDRESS'] || 'noreply@powernode.dev'
        to       to
        subject  subject
        
        # Support both HTML and plain text
        if options[:content_type] == 'text/plain' || !final_body.include?('<')
          body final_body
        else
          html_part do
            content_type 'text/html; charset=UTF-8'
            body final_body
          end
          
          # Add plain text version if HTML is provided
          text_part do
            content_type 'text/plain; charset=UTF-8'
            body strip_html_tags(final_body)
          end
        end

        # Add custom headers
        header['X-Email-Type'] = email_type
        header['X-Account-ID'] = account_id if account_id
        header['X-User-ID'] = user_id if user_id
        header['X-Delivery-ID'] = delivery_id
        header['Message-ID'] = "<#{delivery_id}@#{ENV['SMTP_DOMAIN'] || 'powernode.dev'}>"
        
        # Reply-To header
        reply_to options[:reply_to] if options[:reply_to]
        
        # Attachments
        if options[:attachments]
          options[:attachments].each do |attachment|
            add_file(attachment[:path]) if attachment[:path]
            if attachment[:data] && attachment[:filename]
              add_file_data(attachment[:data], attachment[:filename])
            end
          end
        end
      end

      # Deliver the email
      delivery_result = deliver_mail(mail)

      if delivery_result[:success]
        # Update delivery record as sent
        update_delivery_record(delivery_id, 'sent', {
          message_id: mail.message_id,
          sent_at: Time.current.iso8601
        })

        # Create audit log
        create_audit_log(
          account_id: account_id,
          action: 'send_email',
          resource_type: 'EmailDelivery',
          resource_id: delivery_id,
          user_id: user_id,
          metadata: {
            email_type: email_type,
            recipient: to,
            subject: subject
          }
        )

        log_info("Email sent successfully", 
          delivery_id: delivery_id,
          message_id: mail.message_id,
          email_type: email_type,
          to: to
        )

        success_response({
          delivery_id: delivery_id,
          message_id: mail.message_id,
          email_type: email_type
        }, "Email sent successfully")
      else
        # Update delivery record as failed
        update_delivery_record(delivery_id, 'failed', {
          error_message: delivery_result[:error],
          failed_at: Time.current.iso8601
        })

        log_error("Email delivery failed", nil, 
          delivery_id: delivery_id,
          error: delivery_result[:error],
          email_type: email_type,
          to: to
        )

        error_response("Email delivery failed: #{delivery_result[:error]}")
      end

    rescue => e
      log_error("Email sending failed", e, email_type: email_type, to: to)
      error_response("Email sending failed: #{e.message}")
    end
  end

  # Send bulk emails (for notifications, newsletters)
  def send_bulk_emails(recipients:, subject:, body:, email_type:, account_id: nil, template: nil, template_data: {}, **options)
    log_info("Sending bulk emails", count: recipients.size, email_type: email_type)

    results = []
    
    recipients.each do |recipient|
      # Support both string emails and user objects
      email = recipient.is_a?(String) ? recipient : recipient['email']
      user_id = recipient.is_a?(Hash) ? recipient['id'] : nil
      
      # Personalize template data for each recipient
      personalized_data = template_data.merge(
        recipient: recipient.is_a?(Hash) ? recipient : { email: email }
      )

      result = send_email(
        to: email,
        subject: subject,
        body: body,
        email_type: email_type,
        account_id: account_id,
        user_id: user_id,
        template: template,
        template_data: personalized_data,
        **options
      )

      results << {
        email: email,
        success: result[:success],
        error: result[:error],
        delivery_id: result.dig(:data, :delivery_id)
      }

      # Rate limiting - small delay between emails
      sleep(0.1) if recipients.size > 10
    end

    successful_count = results.count { |r| r[:success] }
    failed_count = results.count { |r| !r[:success] }

    log_info("Bulk email sending completed", 
      total: recipients.size,
      successful: successful_count,
      failed: failed_count
    )

    success_response({
      results: results,
      summary: {
        total: recipients.size,
        successful: successful_count,
        failed: failed_count
      }
    }, "Bulk email sending completed")
  end

  # Send transactional emails with predefined templates
  def send_transactional_email(email_type:, recipient:, data: {}, account_id: nil, user_id: nil)
    template_config = get_email_template_config(email_type)
    
    unless template_config
      return error_response("No template configuration found for email type: #{email_type}")
    end

    # Get recipient email
    email = recipient.is_a?(String) ? recipient : recipient[:email] || recipient['email']
    
    # Merge template data with provided data
    template_data = template_config[:default_data].merge(data)
    template_data[:recipient] = recipient.is_a?(Hash) ? recipient : { email: email }

    send_email(
      to: email,
      subject: render_template_string(template_config[:subject], template_data),
      body: template_config[:body],
      email_type: email_type,
      account_id: account_id,
      user_id: user_id,
      template: template_config[:template],
      template_data: template_data,
      content_type: template_config[:content_type] || 'text/html'
    )
  end

  private

  def configure_mail_settings
    Mail.defaults do
      delivery_method :smtp, {
        address: ENV['SMTP_HOST'] || 'localhost',
        port: (ENV['SMTP_PORT'] || '587').to_i,
        domain: ENV['SMTP_DOMAIN'] || 'powernode.dev',
        user_name: ENV['SMTP_USERNAME'],
        password: ENV['SMTP_PASSWORD'],
        authentication: ENV['SMTP_AUTH'] || 'plain',
        enable_starttls_auto: ENV['SMTP_STARTTLS'] != 'false'
      }
    end
  end

  def create_email_delivery_record(to:, subject:, email_type:, account_id: nil, user_id: nil, template: nil, template_data: {})
    delivery_data = {
      recipient_email: to,
      subject: subject,
      email_type: email_type,
      account_id: account_id,
      user_id: user_id,
      template: template,
      template_data: template_data,
      status: 'pending',
      created_at: Time.current.iso8601
    }

    with_api_retry do
      api_client.post('/api/v1/email_deliveries', delivery_data)
    end
  end

  def update_delivery_record(delivery_id, status, metadata = {})
    update_data = { status: status }.merge(metadata)
    
    with_api_retry do
      api_client.patch("/api/v1/email_deliveries/#{delivery_id}", update_data)
    end
  end

  def deliver_mail(mail)
    begin
      mail.deliver!
      success_response(nil, "Mail delivered successfully")
    rescue Net::SMTPAuthenticationError => e
      error_response("SMTP Authentication failed: #{e.message}")
    rescue Net::SMTPServerBusy => e
      error_response("SMTP Server busy: #{e.message}")
    rescue Net::SMTPSyntaxError => e
      error_response("SMTP Syntax error: #{e.message}")
    rescue Net::SMTPFatalError => e
      error_response("SMTP Fatal error: #{e.message}")
    rescue => e
      error_response("Mail delivery failed: #{e.message}")
    end
  end

  def render_email_template(template, data, fallback_body)
    return fallback_body unless template

    # Simple template rendering - in production you might use ERB, Mustache, etc.
    rendered = template.dup
    
    data.each do |key, value|
      placeholder = "{{#{key}}}"
      rendered.gsub!(placeholder, value.to_s)
    end

    rendered
  end

  def render_template_string(template_string, data)
    rendered = template_string.dup
    
    data.each do |key, value|
      placeholder = "{{#{key}}}"
      rendered.gsub!(placeholder, value.to_s)
    end

    rendered
  end

  def strip_html_tags(html)
    html.gsub(/<[^>]+>/, '').gsub(/\s+/, ' ').strip
  end

  def get_email_template_config(email_type)
    templates = {
      'password_reset' => {
        subject: 'Reset Your Password - {{app_name}}',
        template: 'Hello {{recipient.name}}, you have requested a password reset. Click the link below to reset your password: {{reset_link}}',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      },
      'email_verification' => {
        subject: 'Verify Your Email Address - {{app_name}}',
        template: 'Hello {{recipient.name}}, please verify your email address by clicking this link: {{verification_link}}',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      },
      'welcome_email' => {
        subject: 'Welcome to {{app_name}}!',
        template: 'Welcome {{recipient.name}}! Thank you for joining {{app_name}}. We\'re excited to have you aboard!',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      },
      'subscription_created' => {
        subject: 'Subscription Activated - {{app_name}}',
        template: 'Your {{plan_name}} subscription has been activated. You now have access to all features!',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      },
      'payment_failed' => {
        subject: 'Payment Failed - {{app_name}}',
        template: 'We were unable to process your payment. Please update your payment method to continue your subscription.',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      },
      'report_generated' => {
        subject: 'Your {{report_type}} Report is Ready - {{app_name}}',
        template: 'Your requested {{report_type}} report has been generated and is attached to this email.',
        content_type: 'text/html',
        default_data: {
          app_name: 'Powernode Platform'
        }
      }
    }

    templates[email_type]
  end
end