# frozen_string_literal: true

# Sensitive Data Sanitizer for PCI Compliance
# Prevents logging or storing sensitive payment data
class SensitiveDataSanitizer
  # PCI DSS prohibited data patterns
  SENSITIVE_PATTERNS = {
    # Credit card numbers (various formats)
    credit_card: [
      /\b4\d{3}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/, # Visa
      /\b5[1-5]\d{2}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/, # Mastercard
      /\b3[47]\d{2}[\s\-]?\d{6}[\s\-]?\d{5}\b/, # American Express
      /\b6011[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/, # Discover
      /\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/ # Generic 16-digit
    ],
    
    # CVV/CVC codes
    cvv: [
      /\bcvv[\s:]?\d{3,4}\b/i,
      /\bcvc[\s:]?\d{3,4}\b/i,
      /\bcvn[\s:]?\d{3,4}\b/i,
      /\bsecurity[\s_]code[\s:]?\d{3,4}\b/i
    ],
    
    # Expiration dates
    expiry: [
      /\bexp[\s_]?date[\s:]?\d{1,2}\/\d{2,4}\b/i,
      /\bexpir[\w]*[\s:]?\d{1,2}\/\d{2,4}\b/i,
      /\b\d{1,2}\/\d{2,4}\b/ # Generic MM/YY or MM/YYYY
    ],
    
    # Track data
    track_data: [
      /[%^]\d{4,19}\^[\w\s\/]+\^\d{4,7}\?/,
      /;\d{4,19}=\d{4,7}\?/
    ],
    
    # PIN data
    pin: [
      /\bpin[\s:]?\d{4,8}\b/i,
      /\bpasscode[\s:]?\d{4,8}\b/i
    ],
    
    # Bank account numbers
    bank_account: [
      /\baccount[\s_]?number[\s:]?\d{6,17}\b/i,
      /\brouting[\s_]?number[\s:]?\d{9}\b/i,
      /\baba[\s_]?number[\s:]?\d{9}\b/i
    ],
    
    # SSN
    ssn: [
      /\b\d{3}-\d{2}-\d{4}\b/,
      /\bssn[\s:]?\d{3}-?\d{2}-?\d{4}\b/i
    ]
  }.freeze

  class << self
    # Sanitize sensitive data from strings
    def sanitize_string(input)
      return input unless input.is_a?(String)
      
      sanitized = input.dup
      
      SENSITIVE_PATTERNS.each do |type, patterns|
        patterns.each do |pattern|
          sanitized.gsub!(pattern) do |match|
            mask_sensitive_data(match, type)
          end
        end
      end
      
      sanitized
    end

    # Sanitize sensitive data from hashes (e.g., params, metadata)
    def sanitize_hash(hash)
      return hash unless hash.is_a?(Hash)
      
      sanitized = {}
      
      hash.each do |key, value|
        sanitized_key = key.to_s.downcase
        
        case value
        when Hash
          sanitized[key] = sanitize_hash(value)
        when Array
          sanitized[key] = value.map { |item| item.is_a?(Hash) ? sanitize_hash(item) : sanitize_string(item.to_s) }
        when String, Numeric
          if sensitive_key?(sanitized_key)
            sanitized[key] = mask_by_key(sanitized_key, value.to_s)
          else
            sanitized[key] = sanitize_string(value.to_s)
          end
        else
          sanitized[key] = value
        end
      end
      
      sanitized
    end

    # Sanitize Rails parameters
    def sanitize_params(params)
      return params unless params.respond_to?(:to_unsafe_h)
      
      sanitize_hash(params.to_unsafe_h)
    end

    # Check if data contains sensitive information
    def contains_sensitive_data?(input)
      return false unless input.is_a?(String)
      
      SENSITIVE_PATTERNS.values.flatten.any? do |pattern|
        input.match?(pattern)
      end
    end

    # Get sanitization summary for logging
    def sanitization_summary(original, sanitized)
      {
        original_length: original.to_s.length,
        sanitized_length: sanitized.to_s.length,
        patterns_found: detect_patterns(original.to_s),
        sanitized_at: Time.current.iso8601
      }
    end

    private

    def sensitive_key?(key)
      sensitive_keys = %w[
        card_number cardnumber card_num credit_card_number
        cvv cvc cvn security_code verification_value
        exp_month exp_year expiry_month expiry_year expiration_date
        track_data track1 track2
        pin pincode passcode
        account_number routing_number aba_number
        ssn social_security_number
        password secret_key api_key token
      ].freeze

      sensitive_keys.any? { |sensitive| key.include?(sensitive) }
    end

    def mask_by_key(key, value)
      case key
      when /card.*number|credit.*card/
        mask_credit_card(value)
      when /cvv|cvc|cvn|security.*code/
        '***'
      when /exp|expir/
        mask_expiry(value)
      when /pin|passcode/
        '****'
      when /account.*number|routing/
        mask_account_number(value)
      when /ssn|social.*security/
        mask_ssn(value)
      when /password|secret|token|key/
        '[REDACTED]'
      else
        '[SENSITIVE]'
      end
    end

    def mask_sensitive_data(match, type)
      case type
      when :credit_card
        mask_credit_card(match)
      when :cvv
        '***'
      when :expiry
        mask_expiry(match)
      when :track_data
        '[TRACK_DATA_REDACTED]'
      when :pin
        '****'
      when :bank_account
        mask_account_number(match)
      when :ssn
        mask_ssn(match)
      else
        '[SENSITIVE]'
      end
    end

    def mask_credit_card(card_number)
      # Keep first 4 and last 4 digits, mask the rest
      cleaned = card_number.gsub(/\D/, '')
      return '[INVALID_CARD]' if cleaned.length < 8
      
      first_four = cleaned[0..3]
      last_four = cleaned[-4..-1]
      masked_middle = '*' * (cleaned.length - 8)
      
      "#{first_four}#{masked_middle}#{last_four}"
    end

    def mask_expiry(expiry)
      # Preserve format but mask actual values
      if expiry.include?('/')
        parts = expiry.split('/')
        "**/#{'*' * parts.last.length}"
      else
        '*' * expiry.length
      end
    end

    def mask_account_number(account)
      # Keep last 4 digits
      cleaned = account.gsub(/\D/, '')
      return '[INVALID_ACCOUNT]' if cleaned.length < 4
      
      masked = '*' * (cleaned.length - 4) + cleaned[-4..-1]
      masked
    end

    def mask_ssn(ssn)
      # Format: ***-**-1234
      cleaned = ssn.gsub(/\D/, '')
      return '[INVALID_SSN]' if cleaned.length != 9
      
      "***-**-#{cleaned[-4..-1]}"
    end

    def detect_patterns(input)
      found_patterns = []
      
      SENSITIVE_PATTERNS.each do |type, patterns|
        patterns.each do |pattern|
          if input.match?(pattern)
            found_patterns << type.to_s
            break # Don't double-count the same type
          end
        end
      end
      
      found_patterns
    end
  end

  # Instance methods for specific use cases
  def initialize(context = nil)
    @context = context
  end

  def sanitize_for_logging(data)
    case data
    when Hash
      self.class.sanitize_hash(data)
    when String
      self.class.sanitize_string(data)
    else
      data
    end
  end

  def safe_to_log?(data)
    return true unless data.is_a?(String)
    !self.class.contains_sensitive_data?(data)
  end
end