# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Email node executor - dispatches emails to worker
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
      include Concerns::WorkerDispatch

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

        payload = {
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
          node_id: @node.node_id
        }

        log_info "Dispatching email to: #{to.join(', ')}"

        dispatch_to_worker("Mcp::McpEmailExecutionJob", payload)
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
          [resolved].compact
        end
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
    end
  end
end
