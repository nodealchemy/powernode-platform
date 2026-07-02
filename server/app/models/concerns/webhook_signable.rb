# frozen_string_literal: true

# Timestamped-HMAC payload signing for outbound webhook models.
#
# Expects the including model to have a `signature_secret` string column.
# Crypto lives in Security::WebhookAuthenticator; this concern only binds it
# to the model's persisted secret.
#
# Header format (Stripe style): "t=<unix_ts>,v1=<hex hmac of '<ts>.<payload>'>"
module WebhookSignable
  extend ActiveSupport::Concern

  # Sign an outgoing payload with the model's signature_secret.
  # Returns nil when no secret is configured.
  def generate_signature(payload)
    return nil unless signature_secret.present?

    Security::WebhookAuthenticator.sign_timestamped(payload: payload, secret: signature_secret)
  end

  # Verify a timestamped signature header against the model's signature_secret.
  # Constant-time comparison; rejects timestamps outside the allowed skew.
  def verify_signature(payload, signature_header)
    return false unless signature_secret.present?

    Security::WebhookAuthenticator.verify_timestamped(
      payload: payload,
      header: signature_header,
      secret: signature_secret
    )
  end

  # Rotate the signing secret and persist it.
  def regenerate_signature_secret!
    self.signature_secret = Security::WebhookAuthenticator.generate_signing_secret
    save!
  end
end
