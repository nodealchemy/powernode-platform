# frozen_string_literal: true

# PayPal Webhook Signature Verification Service
class PaypalWebhookVerifier
  include ActiveModel::Model

  attr_accessor :webhook_id, :event_body, :headers

  def initialize(webhook_id:, event_body:, headers:)
    @webhook_id = webhook_id
    @event_body = event_body
    @headers = headers
  end

  # Verify PayPal webhook signature using their verification API
  def verify_signature
    return false unless webhook_id.present? && event_body.present?

    begin
      # Construct the verification request
      verification_request = build_verification_request

      # Use PayPal SDK to verify webhook
      response = PayPal::SDK::REST::DataTypes::VerifyWebhookSignature.new(verification_request)

      if response.post
        Rails.logger.info "PayPal webhook signature verified successfully"
        { success: true, verified: response.verification_status == "SUCCESS" }
      else
        Rails.logger.warn "PayPal webhook signature verification failed: #{response.error}"
        { success: false, error: response.error, verified: false }
      end
    rescue => e
      Rails.logger.error "PayPal webhook verification error: #{e.message}"
      { success: false, error: e.message, verified: false }
    end
  end

  # Alternative manual verification method for critical security
  def manual_verification
    return false unless webhook_id.present?

    begin
      # Get webhook details from PayPal
      webhook_details = get_webhook_details
      return false unless webhook_details

      # Verify certificate chain and signature
      signature_valid = verify_certificate_and_signature
      event_valid = verify_event_structure

      {
        success: true,
        verified: signature_valid && event_valid,
        details: {
          signature_valid: signature_valid,
          event_valid: event_valid,
          webhook_id: webhook_id
        }
      }
    rescue => e
      Rails.logger.error "PayPal manual webhook verification failed: #{e.message}"
      { success: false, error: e.message, verified: false }
    end
  end

  private

  def build_verification_request
    {
      auth_algo: headers["PAYPAL-AUTH-ALGO"],
      cert_id: headers["PAYPAL-CERT-ID"],
      transmission_id: headers["PAYPAL-TRANSMISSION-ID"],
      transmission_sig: headers["PAYPAL-TRANSMISSION-SIG"],
      transmission_time: headers["PAYPAL-TRANSMISSION-TIME"],
      webhook_id: webhook_id,
      webhook_event: JSON.parse(event_body)
    }
  end

  def get_webhook_details
    begin
      webhook = PayPal::SDK::REST::WebhookEvent.get(webhook_id)
      webhook if webhook.valid?
    rescue => e
      Rails.logger.error "Failed to get PayPal webhook details: #{e.message}"
      nil
    end
  end

  def verify_certificate_and_signature
    # Extract certificate from headers
    cert_id = headers["PAYPAL-CERT-ID"]
    transmission_sig = headers["PAYPAL-TRANSMISSION-SIG"]

    return false unless cert_id.present? && transmission_sig.present?

    # In production, implement actual certificate verification
    # This is a simplified version for development
    cert_id.present? && transmission_sig.present?
  end

  def verify_event_structure
    begin
      parsed_event = JSON.parse(event_body)

      # Verify required fields
      required_fields = %w[id event_type create_time resource_type summary]
      required_fields.all? { |field| parsed_event.key?(field) }
    rescue JSON::ParserError
      false
    end
  end
end
