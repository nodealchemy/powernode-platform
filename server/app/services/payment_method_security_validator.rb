# frozen_string_literal: true

# Payment Method Security Validator
# Implements fraud detection and validation for payment methods
class PaymentMethodSecurityValidator
  include ActiveModel::Model

  attr_accessor :account, :user, :payment_method_data, :request_metadata

  def initialize(account:, user:, payment_method_data:, request_metadata: {})
    @account = account
    @user = user
    @payment_method_data = payment_method_data
    @request_metadata = request_metadata
  end

  # Main validation method
  def validate
    validation_results = {
      overall_risk_score: 0,
      risk_factors: [],
      validations: {},
      recommendation: "unknown",
      requires_additional_verification: false
    }

    # Run all validation checks
    validation_results[:validations][:card_validation] = validate_card_details
    validation_results[:validations][:velocity_check] = check_velocity_limits
    validation_results[:validations][:geolocation_check] = validate_geolocation
    validation_results[:validations][:device_fingerprint] = validate_device_fingerprint
    validation_results[:validations][:account_history] = check_account_history
    validation_results[:validations][:provider_validation] = validate_with_provider

    # Calculate overall risk score
    validation_results = calculate_risk_score(validation_results)

    # Generate recommendation
    validation_results[:recommendation] = generate_recommendation(validation_results[:overall_risk_score])
    validation_results[:requires_additional_verification] = validation_results[:overall_risk_score] >= 70

    log_validation_results(validation_results)

    validation_results
  rescue => e
    Rails.logger.error "Payment method validation error: #{e.message}"
    {
      overall_risk_score: 100,
      risk_factors: [ "validation_error" ],
      recommendation: "reject",
      error: e.message
    }
  end

  private

  def validate_card_details
    return { valid: true, risk_score: 0 } unless card_payment_method?

    card = payment_method_data["card"]
    risk_factors = []
    risk_score = 0

    # Check for high-risk card characteristics
    if high_risk_country?(card["country"])
      risk_factors << "high_risk_country"
      risk_score += 25
    end

    if high_risk_issuer?(card["funding"])
      risk_factors << "high_risk_funding_source"
      risk_score += 15
    end

    if card["checks"]
      # CVC check failed
      if card["checks"]["cvc_check"] == "fail"
        risk_factors << "cvc_check_failed"
        risk_score += 30
      end

      # Address verification failed
      if card["checks"]["address_line1_check"] == "fail"
        risk_factors << "address_verification_failed"
        risk_score += 20
      end

      # Postal code check failed
      if card["checks"]["address_postal_code_check"] == "fail"
        risk_factors << "postal_code_verification_failed"
        risk_score += 15
      end
    end

    {
      valid: risk_score < 50,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        brand: card["brand"],
        country: card["country"],
        funding: card["funding"],
        checks: card["checks"]
      }
    }
  end

  def check_velocity_limits
    risk_factors = []
    risk_score = 0

    # Check payment method velocity (last 24 hours)
    recent_methods = account.payment_methods
                           .where("created_at > ?", 24.hours.ago)
                           .count

    if recent_methods > 3
      risk_factors << "high_payment_method_velocity"
      risk_score += 40
    elsif recent_methods > 1
      risk_factors << "moderate_payment_method_velocity"
      risk_score += 20
    end

    # Check failed payment method attempts - using a simple count since we don't have metadata tracking yet
    recent_payment_methods = account.payment_methods.where("created_at > ?", 1.hour.ago).count
    failed_attempts = [ recent_payment_methods / 2, 0 ].max # Estimate based on recent activity

    if failed_attempts > 5
      risk_factors << "high_failed_attempts"
      risk_score += 50
    elsif failed_attempts > 2
      risk_factors << "moderate_failed_attempts"
      risk_score += 25
    end

    {
      valid: risk_score < 60,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        recent_methods: recent_methods,
        failed_attempts: failed_attempts
      }
    }
  end

  def validate_geolocation
    return { valid: true, risk_score: 0 } unless request_metadata[:ip_address]

    risk_factors = []
    risk_score = 0

    # Implement geolocation validation
    # This would integrate with a geolocation service
    # Get user country from preferences or account settings
    user_country = user.preferences&.dig("country") || account.settings&.dig("country")
    ip_country = detect_country_from_ip(request_metadata[:ip_address])

    if ip_country && user_country && ip_country != user_country
      risk_factors << "geolocation_mismatch"
      risk_score += 30

      # Higher risk for high-risk countries
      if high_risk_country?(ip_country)
        risk_factors << "high_risk_ip_country"
        risk_score += 40
      end
    end

    # Check for VPN/Proxy usage
    if vpn_or_proxy_detected?(request_metadata[:ip_address])
      risk_factors << "vpn_proxy_detected"
      risk_score += 35
    end

    {
      valid: risk_score < 50,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        user_country: user_country,
        ip_country: ip_country,
        ip_address: request_metadata[:ip_address]
      }
    }
  end

  def validate_device_fingerprint
    return { valid: true, risk_score: 0 } unless request_metadata[:device_fingerprint]

    risk_factors = []
    risk_score = 0

    # Check if device fingerprint has been seen before
    fingerprint = request_metadata[:device_fingerprint]

    # Check for suspicious device characteristics
    if suspicious_device?(fingerprint)
      risk_factors << "suspicious_device"
      risk_score += 25
    end

    # Check device velocity (multiple accounts from same device)
    # Using preferences JSON column instead of metadata
    device_accounts = Account.joins(:users)
                            .where("users.preferences->>? = ?", "device_fingerprint", fingerprint)
                            .where("accounts.created_at > ?", 30.days.ago)
                            .count

    if device_accounts > 3
      risk_factors << "high_device_velocity"
      risk_score += 45
    elsif device_accounts > 1
      risk_factors << "moderate_device_velocity"
      risk_score += 20
    end

    {
      valid: risk_score < 50,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        fingerprint: fingerprint,
        device_accounts: device_accounts
      }
    }
  end

  def check_account_history
    risk_factors = []
    risk_score = 0

    # Check account age
    if account.created_at > 1.day.ago
      risk_factors << "new_account"
      risk_score += 25
    end

    # Check payment history
    failed_payments = account.payments.where(status: "failed").count
    total_payments = account.payments.count

    if total_payments > 0
      failure_rate = failed_payments.to_f / total_payments

      if failure_rate > 0.5
        risk_factors << "high_payment_failure_rate"
        risk_score += 40
      elsif failure_rate > 0.2
        risk_factors << "moderate_payment_failure_rate"
        risk_score += 20
      end
    end

    # Check for chargebacks or disputes
    chargeback_count = account.settings&.dig("chargeback_count")&.to_i || 0
    if chargeback_count > 0
      risk_factors << "previous_chargebacks"
      risk_score += 60
    end

    {
      valid: risk_score < 50,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        account_age_days: (Time.current - account.created_at) / 1.day,
        failed_payments: failed_payments,
        total_payments: total_payments,
        chargeback_count: account.settings&.dig("chargeback_count")&.to_i || 0
      }
    }
  end

  def validate_with_provider
    return { valid: true, risk_score: 0 } unless payment_method_data["provider"] == "stripe"

    risk_factors = []
    risk_score = 0

    # Check Stripe's risk evaluation
    if payment_method_data["card"] && payment_method_data["card"]["risk_level"]
      case payment_method_data["card"]["risk_level"]
      when "elevated"
        risk_factors << "provider_elevated_risk"
        risk_score += 30
      when "highest"
        risk_factors << "provider_highest_risk"
        risk_score += 60
      end
    end

    {
      valid: risk_score < 40,
      risk_score: risk_score,
      risk_factors: risk_factors,
      details: {
        provider_risk_level: payment_method_data.dig("card", "risk_level")
      }
    }
  end

  def calculate_risk_score(validation_results)
    total_score = 0
    risk_factors = []

    validation_results[:validations].each do |_, validation|
      if validation.is_a?(Hash) && validation[:risk_score]
        total_score += validation[:risk_score]
        risk_factors.concat(validation[:risk_factors] || [])
      end
    end

    # Apply multipliers for combinations of risk factors
    if risk_factors.include?("high_risk_country") && risk_factors.include?("geolocation_mismatch")
      total_score *= 1.2
    end

    if risk_factors.include?("new_account") && risk_factors.include?("high_payment_method_velocity")
      total_score *= 1.3
    end

    validation_results[:overall_risk_score] = [ total_score.round, 100 ].min
    validation_results[:risk_factors] = risk_factors.uniq

    validation_results
  end

  def generate_recommendation(risk_score)
    case risk_score
    when 0..30
      "approve"
    when 31..60
      "review"
    when 61..80
      "additional_verification"
    else
      "reject"
    end
  end

  def log_validation_results(results)
    AuditLog.log_action(
      action: "payment_method_validation",
      resource_type: "PaymentMethod",
      account: account,
      user: user,
      new_values: {
        risk_score: results[:overall_risk_score],
        recommendation: results[:recommendation],
        risk_factors: results[:risk_factors]
      },
      source: "security_validator",
      metadata: {
        validation_timestamp: Time.current.iso8601,
        request_ip: request_metadata[:ip_address],
        device_fingerprint: request_metadata[:device_fingerprint]
      }
    )
  rescue => e
    Rails.logger.error "Failed to log payment method validation: #{e.message}"
  end

  # Helper methods
  def card_payment_method?
    payment_method_data["type"] == "card" || payment_method_data["card"].present?
  end

  def high_risk_country?(country_code)
    # List of high-risk countries for fraud
    high_risk_countries = %w[
      AF BD BI BF BJ CF KM CD CG CI DJ DZ ER ET GM GN GW HT
      IQ LR LY ML MM MR NE NG PK SL SO SS SD SY TD TG TM UZ YE ZW
    ].freeze

    high_risk_countries.include?(country_code&.upcase)
  end

  def high_risk_issuer?(funding_type)
    %w[prepaid unknown].include?(funding_type&.downcase)
  end

  def detect_country_from_ip(ip_address)
    # This would integrate with a geolocation service like MaxMind
    # For now, return a placeholder
    return "US" if ip_address =~ /^192\.168\./  # Local IP
    return "US" if ip_address =~ /^10\./        # Local IP

    # In production, implement actual geolocation lookup
    nil
  end

  def vpn_or_proxy_detected?(ip_address)
    # This would integrate with a VPN/proxy detection service
    # For now, return false
    false
  end

  def suspicious_device?(fingerprint)
    # Check against known suspicious device characteristics
    # This would be populated based on historical fraud data
    false
  end
end
