# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Email node executor - sends emails via configured providers
    #
    # Configuration:
    # - provider: smtp, sendgrid, mailgun, ses
    # - to: Recipient(s) - supports arrays and variables
    # - cc, bcc: Optional recipients
    # - subject: Email subject with variable interpolation
    # - body_html: HTML body template
    # - body_text: Plain text body
    # - template_id: For template-based sending
    # - template_data: Variables for template
    # - attachments: Array of file references
    #
    class Email < Base
      ALLOWED_PROVIDERS = %w[smtp sendgrid mailgun ses].freeze

      protected

      def perform_execution
        log_info "Executing email operation"

        provider = configuration["provider"] || "smtp"
        to = resolve_recipients(configuration["to"])
        cc = resolve_recipients(configuration["cc"])
        bcc = resolve_recipients(configuration["bcc"])
        from = resolve_value(configuration["from"])
        subject = resolve_value(configuration["subject"])
        body_html = resolve_value(configuration["body_html"])
        body_text = resolve_value(configuration["body_text"])
        template_id = configuration["template_id"]
        template_data = configuration["template_data"] || {}
        attachments = configuration["attachments"] || []

        validate_configuration!(provider, to, subject)

        email_context = {
          provider: provider,
          to: to,
          cc: cc,
          bcc: bcc,
          from: from,
          subject: subject,
          body_html: body_html,
          body_text: body_text,
          template_id: template_id,
          template_data: template_data,
          attachments: attachments,
          started_at: Time.current
        }

        log_info "Sending email to: #{to.join(', ')}"

        # Send the email
        result = send_email(email_context)

        build_output(email_context, result)
      end

      private

      def validate_configuration!(provider, to, subject)
        unless ALLOWED_PROVIDERS.include?(provider)
          raise ArgumentError, "Invalid provider: #{provider}. Allowed: #{ALLOWED_PROVIDERS.join(', ')}"
        end

        raise ArgumentError, "to is required" if to.blank?
        raise ArgumentError, "subject is required" if subject.blank?
      end

      def resolve_recipients(value)
        return [] if value.nil?

        resolved = resolve_value(value)
        return [] if resolved.nil?

        if resolved.is_a?(Array)
          resolved.map { |r| resolve_value(r) }.compact
        else
          [ resolved ].compact
        end
      end

      def send_email(context)
        # NOTE: This is a simulation. In production, this would:
        # 1. Select the appropriate email provider
        # 2. Build the email with proper formatting
        # 3. Send via the provider's API
        # 4. Return delivery status

        message_id = "msg_#{SecureRandom.hex(16)}"

        {
          message_id: message_id,
          status: "sent",
          provider: context[:provider],
          recipients: {
            to: context[:to],
            cc: context[:cc],
            bcc: context[:bcc]
          },
          subject: context[:subject],
          sent_at: Time.current.iso8601
        }
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(context, result)
        {
          output: {
            email_sent: true,
            message_id: result[:message_id],
            recipients_count: context[:to].length
          },
          data: result.merge(
            from: context[:from],
            template_used: context[:template_id].present?,
            attachments_count: context[:attachments].length,
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          metadata: {
            node_id: @node.node_id,
            node_type: "email",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
