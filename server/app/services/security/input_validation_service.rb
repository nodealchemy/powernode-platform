# frozen_string_literal: true

module Security
  class InputValidationService
    class ValidationError < StandardError
      attr_reader :field, :violation_type

      def initialize(field:, violation_type:, message:)
        @field = field
        @violation_type = violation_type
        super(message)
      end
    end

    # Shell injection patterns
    SHELL_INJECTION_PATTERNS = [
      /[;&|`$]/,                  # Shell operators
      /\$\(.*\)/,                 # Command substitution
      /`.*`/,                     # Backtick execution
      /\|\|/,                     # OR operator
      /&&/,                       # AND operator
      />\s*\/|>>/,                # Output redirection
      /\|\s*\w/                   # Pipe to command
    ].freeze

    # Path traversal patterns
    PATH_TRAVERSAL_PATTERNS = [
      /\.\.[\/\\]/,               # Parent directory
      /\.{2,}/,                   # Multiple dots
      /%2e%2e/i,                  # URL encoded dots
      /%252e/i,                   # Double URL encoded
      /\.%00/,                    # Null byte injection
      /\x00/                      # Null bytes
    ].freeze

    # SQL injection patterns (basic protection - use parameterized queries)
    SQL_INJECTION_PATTERNS = [
      /'\s*or\s+.*=/i,
      /'\s*and\s+.*=/i,
      /--\s*$/,
      /;\s*drop\s+/i,
      /;\s*delete\s+/i,
      /;\s*update\s+/i,
      /union\s+select/i,
      /'\s*;\s*--/
    ].freeze

    # Prompt injection patterns
    PROMPT_INJECTION_PATTERNS = [
      /<\|.*\|>/,                 # Common prompt markers
      /\[INST\]|\[\/INST\]/i,    # Instruction markers
      /<<SYS>>|<\/SYS>>/i,       # System prompt markers
      /system:\s*ignore/i,        # Override attempts
      /disregard\s+(all\s+)?previous/i,
      /ignore\s+(all\s+)?previous/i,
      /forget\s+(all\s+)?previous/i,
      /new\s+instructions?:/i,
      /you\s+are\s+now\s+/i,
      /pretend\s+(you\s+are|to\s+be)/i,
      /act\s+as\s+(if\s+you\s+are\s+)?a?/i
    ].freeze

    # XSS patterns
    XSS_PATTERNS = [
      /<script[\s>]/i,
      /javascript:/i,
      /on\w+\s*=/i,               # Event handlers
      /data:\s*text\/html/i,
      /vbscript:/i,
      /<iframe/i,
      /<object/i,
      /<embed/i,
      /<svg.*on\w+/i
    ].freeze

    class << self
      # Validate general text input
      def validate_text!(value, field:, max_length: 10_000, allow_html: false)
        return if value.blank?

        if value.length > max_length
          raise ValidationError.new(
            field: field,
            violation_type: "length_exceeded",
            message: "#{field} exceeds maximum length of #{max_length}"
          )
        end

        unless allow_html
          check_xss!(value, field: field)
        end

        value
      end

      # Validate path/filename input
      def validate_path!(value, field:)
        return if value.blank?

        PATH_TRAVERSAL_PATTERNS.each do |pattern|
          if value.match?(pattern)
            raise ValidationError.new(
              field: field,
              violation_type: "path_traversal",
              message: "#{field} contains path traversal sequence"
            )
          end
        end

        value
      end

      # Validate shell/command input
      def validate_command_input!(value, field:)
        return if value.blank?

        SHELL_INJECTION_PATTERNS.each do |pattern|
          if value.match?(pattern)
            raise ValidationError.new(
              field: field,
              violation_type: "shell_injection",
              message: "#{field} contains potentially dangerous shell characters"
            )
          end
        end

        value
      end

      # Validate AI prompt input (for external user messages)
      def validate_prompt!(value, field:)
        return if value.blank?

        PROMPT_INJECTION_PATTERNS.each do |pattern|
          if value.match?(pattern)
            Rails.logger.warn "Potential prompt injection detected in #{field}: #{value.truncate(100)}"
            # Don't raise, but sanitize
          end
        end

        value
      end

      # Sanitize external message content for AI processing
      def sanitize_external_message(content, source: "external")
        return "" if content.blank?

        # Escape potential prompt markers
        sanitized = content
          .gsub(/<\|/, "&lt;|")
          .gsub(/\|>/, "|&gt;")
          .gsub(/\[INST\]/i, "[_INST_]")
          .gsub(/\[\/INST\]/i, "[/_INST_]")
          .gsub(/<<SYS>>/i, "<<_SYS_>>")
          .gsub(/<\/SYS>>/i, "</_SYS_>>")

        # Wrap in safe delimiters
        "[#{source.upcase}_MESSAGE_START]\n#{sanitized}\n[#{source.upcase}_MESSAGE_END]"
      end

      # Validate UUID format
      def validate_uuid!(value, field:)
        return if value.blank?

        unless value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
          raise ValidationError.new(
            field: field,
            violation_type: "invalid_uuid",
            message: "#{field} must be a valid UUID"
          )
        end

        value
      end

      # Validate URL format
      def validate_url!(value, field:, allowed_schemes: %w[http https])
        return if value.blank?

        begin
          uri = URI.parse(value)

          unless allowed_schemes.include?(uri.scheme&.downcase)
            raise ValidationError.new(
              field: field,
              violation_type: "invalid_scheme",
              message: "#{field} must use #{allowed_schemes.join(' or ')} scheme"
            )
          end

          if uri.host.blank?
            raise ValidationError.new(
              field: field,
              violation_type: "missing_host",
              message: "#{field} must have a valid host"
            )
          end
        rescue URI::InvalidURIError
          raise ValidationError.new(
            field: field,
            violation_type: "invalid_url",
            message: "#{field} is not a valid URL"
          )
        end

        value
      end

      # Validate domain name
      def validate_domain!(value, field:)
        return if value.blank?

        # Allow wildcard domains like *.example.com
        domain = value.gsub(/^\*\./, "")

        unless domain.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/i)
          raise ValidationError.new(
            field: field,
            violation_type: "invalid_domain",
            message: "#{field} is not a valid domain name"
          )
        end

        value
      end

      # Validate JSON structure
      def validate_json!(value, field:, schema: nil)
        return if value.blank?

        begin
          parsed = value.is_a?(String) ? JSON.parse(value) : value

          if schema.present?
            # TODO: Add JSON schema validation if needed
          end

          parsed
        rescue JSON::ParserError
          raise ValidationError.new(
            field: field,
            violation_type: "invalid_json",
            message: "#{field} is not valid JSON"
          )
        end
      end

      # Validate execution ID format
      def validate_execution_id!(value, field:)
        return if value.blank?

        unless value.match?(/\Aexec-[a-z0-9]{8}-\d+\z/)
          raise ValidationError.new(
            field: field,
            violation_type: "invalid_execution_id",
            message: "#{field} is not a valid execution ID format"
          )
        end

        value
      end

      private

      def check_xss!(value, field:)
        XSS_PATTERNS.each do |pattern|
          if value.match?(pattern)
            raise ValidationError.new(
              field: field,
              violation_type: "xss_attempt",
              message: "#{field} contains potentially dangerous HTML/JavaScript"
            )
          end
        end
      end
    end
  end
end
