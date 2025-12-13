# frozen_string_literal: true

# Service for managing user consents with full audit trail
class ConsentManagementService
  class ConsentError < StandardError; end

  CONSENT_TYPES = {
    "marketing" => {
      description: "Receive marketing communications and promotional offers",
      required: false,
      default: false
    },
    "analytics" => {
      description: "Allow collection of usage analytics to improve our services",
      required: false,
      default: false
    },
    "cookies" => {
      description: "Allow use of cookies for functionality and analytics",
      required: false,
      default: false
    },
    "data_sharing" => {
      description: "Allow sharing of data with third-party service providers",
      required: false,
      default: false
    },
    "third_party" => {
      description: "Allow third-party integrations to access your data",
      required: false,
      default: false
    },
    "communications" => {
      description: "Receive service-related communications",
      required: true,
      default: true
    },
    "newsletter" => {
      description: "Subscribe to our newsletter",
      required: false,
      default: false
    },
    "promotional" => {
      description: "Receive promotional content and special offers",
      required: false,
      default: false
    }
  }.freeze

  class << self
    # Get all consents for a user
    def get_consents(user)
      consents = {}

      CONSENT_TYPES.each do |type, config|
        current = UserConsent.current_consent(user, type)

        consents[type] = {
          granted: current&.granted || false,
          required: config[:required],
          description: config[:description],
          version: current&.version,
          granted_at: current&.granted_at,
          withdrawn_at: current&.withdrawn_at
        }
      end

      consents
    end

    # Grant a consent
    def grant(user:, consent_type:, version: nil, consent_text: nil, ip_address: nil, user_agent: nil, metadata: {})
      validate_consent_type!(consent_type)

      UserConsent.grant_consent(
        user: user,
        consent_type: consent_type,
        version: version || current_version(consent_type),
        consent_text: consent_text || consent_text_for(consent_type),
        ip_address: ip_address,
        user_agent: user_agent,
        metadata: metadata.merge(source: "consent_management_service")
      )
    end

    # Withdraw a consent
    def withdraw(user:, consent_type:, ip_address: nil)
      validate_consent_type!(consent_type)
      validate_not_required!(consent_type)

      UserConsent.withdraw_consent(
        user: user,
        consent_type: consent_type,
        ip_address: ip_address
      )
    end

    # Bulk update consents
    def update_consents(user:, consents:, ip_address: nil, user_agent: nil)
      results = {}

      consents.each do |consent_type, granted|
        consent_type = consent_type.to_s

        next unless CONSENT_TYPES.key?(consent_type)

        if granted
          results[consent_type] = grant(
            user: user,
            consent_type: consent_type,
            ip_address: ip_address,
            user_agent: user_agent
          )
        else
          next if CONSENT_TYPES[consent_type][:required]

          withdraw(user: user, consent_type: consent_type, ip_address: ip_address)
          results[consent_type] = { withdrawn: true }
        end
      end

      results
    end

    # Check if user has given specific consent
    def has_consent?(user, consent_type)
      UserConsent.has_consent?(user, consent_type)
    end

    # Get consent history for a user
    def consent_history(user, consent_type: nil)
      scope = UserConsent.where(user: user).order(created_at: :desc)
      scope = scope.by_type(consent_type) if consent_type.present?
      scope
    end

    # Export consent records for a user (for data portability)
    def export_consents(user)
      UserConsent.where(user: user).map do |consent|
        {
          consent_type: consent.consent_type,
          granted: consent.granted,
          version: consent.version,
          collection_method: consent.collection_method,
          granted_at: consent.granted_at&.iso8601,
          withdrawn_at: consent.withdrawn_at&.iso8601,
          ip_address: consent.ip_address
        }
      end
    end

    # Record consent acceptance during registration
    def record_registration_consents(user:, consents:, ip_address: nil, user_agent: nil)
      # Required consents are automatically granted during registration
      CONSENT_TYPES.each do |type, config|
        if config[:required] || consents[type.to_sym] == true || consents[type] == true
          grant(
            user: user,
            consent_type: type,
            ip_address: ip_address,
            user_agent: user_agent,
            metadata: { registration: true }
          )
        end
      end
    end

    # Check if user needs to review consents (after policy update)
    def needs_consent_review?(user)
      CONSENT_TYPES.keys.any? do |type|
        current = UserConsent.current_consent(user, type)
        next false unless current&.granted

        # Check if consent version is outdated
        current.version != current_version(type)
      end
    end

    # Get consents that need review
    def consents_needing_review(user)
      CONSENT_TYPES.keys.select do |type|
        current = UserConsent.current_consent(user, type)
        next false unless current&.granted

        current.version != current_version(type)
      end
    end

    private

    def validate_consent_type!(consent_type)
      return if CONSENT_TYPES.key?(consent_type)

      raise ConsentError, "Invalid consent type: #{consent_type}"
    end

    def validate_not_required!(consent_type)
      return unless CONSENT_TYPES[consent_type][:required]

      raise ConsentError, "Cannot withdraw required consent: #{consent_type}"
    end

    def current_version(consent_type)
      # In production, this should come from a versioned consent document store
      "1.0"
    end

    def consent_text_for(consent_type)
      CONSENT_TYPES[consent_type][:description]
    end
  end
end
