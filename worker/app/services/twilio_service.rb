# frozen_string_literal: true

require 'twilio-ruby'

# Twilio SMS service for sending SMS notifications
class TwilioService
  class TwilioError < StandardError; end
  class ConfigurationError < TwilioError; end
  class DeliveryError < TwilioError; end
  class InvalidPhoneError < TwilioError; end

  def initialize
    validate_configuration!
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    @logger = PowernodeWorker.logger
  end

  # Send an SMS message
  # @param to [String] Phone number to send to (E.164 format)
  # @param body [String] Message content
  # @param from [String, nil] Optional sender phone number
  # @return [Hash] Result with success status and message SID
  def send_sms(to:, body:, from: nil)
    validate_phone_number!(to)

    sender = from || default_from_number
    truncated_body = truncate_message(body)

    @logger.info "[TwilioService] Sending SMS to #{mask_phone(to)}"

    message = @client.messages.create(
      to: normalize_phone(to),
      from: sender,
      body: truncated_body
    )

    @logger.info "[TwilioService] SMS sent successfully. SID: #{message.sid}"

    {
      success: true,
      message_sid: message.sid,
      status: message.status,
      to: to,
      from: sender,
      segments: calculate_segments(truncated_body)
    }
  rescue Twilio::REST::RestError => e
    handle_twilio_error(e, to)
  end

  # Send bulk SMS messages
  # @param messages [Array<Hash>] Array of {to:, body:, from:} hashes
  # @return [Array<Hash>] Results for each message
  def send_bulk_sms(messages)
    results = messages.map do |msg|
      send_sms(to: msg[:to], body: msg[:body], from: msg[:from])
    rescue StandardError => e
      { success: false, error: e.message, to: msg[:to] }
    end

    {
      success: results.all? { |r| r[:success] },
      total: messages.count,
      sent: results.count { |r| r[:success] },
      failed: results.count { |r| !r[:success] },
      results: results
    }
  end

  # Look up a phone number to validate it
  # @param phone [String] Phone number to look up
  # @return [Hash] Phone number information
  def lookup_phone(phone)
    lookup = @client.lookups.v2.phone_numbers(normalize_phone(phone)).fetch

    {
      success: true,
      phone_number: lookup.phone_number,
      country_code: lookup.country_code,
      carrier: lookup.carrier,
      valid: lookup.valid
    }
  rescue Twilio::REST::RestError => e
    { success: false, error: e.message }
  end

  # Get message status
  # @param message_sid [String] Twilio message SID
  # @return [Hash] Message status information
  def get_message_status(message_sid)
    message = @client.messages(message_sid).fetch

    {
      success: true,
      sid: message.sid,
      status: message.status,
      error_code: message.error_code,
      error_message: message.error_message,
      date_sent: message.date_sent,
      date_updated: message.date_updated
    }
  rescue Twilio::REST::RestError => e
    { success: false, error: e.message }
  end

  private

  def account_sid
    ENV['TWILIO_ACCOUNT_SID']
  end

  def auth_token
    ENV['TWILIO_AUTH_TOKEN']
  end

  def default_from_number
    ENV['TWILIO_PHONE_NUMBER'] || ENV['TWILIO_FROM_NUMBER']
  end

  def validate_configuration!
    missing = []
    missing << 'TWILIO_ACCOUNT_SID' unless account_sid.present?
    missing << 'TWILIO_AUTH_TOKEN' unless auth_token.present?
    missing << 'TWILIO_PHONE_NUMBER' unless default_from_number.present?

    if missing.any?
      raise ConfigurationError, "Missing Twilio configuration: #{missing.join(', ')}"
    end
  end

  def validate_phone_number!(phone)
    normalized = normalize_phone(phone)

    # Basic E.164 format validation
    unless normalized.match?(/^\+[1-9]\d{1,14}$/)
      raise InvalidPhoneError, "Invalid phone number format: #{phone}. Must be E.164 format (e.g., +14155551234)"
    end
  end

  def normalize_phone(phone)
    # Remove spaces, dashes, parentheses
    cleaned = phone.to_s.gsub(/[\s\-\(\)]/, '')

    # Add + if not present and starts with country code
    cleaned.start_with?('+') ? cleaned : "+#{cleaned}"
  end

  def mask_phone(phone)
    # Mask all but last 4 digits for logging
    normalized = normalize_phone(phone)
    "#{normalized[0..2]}****#{normalized[-4..]}"
  end

  def truncate_message(body)
    # SMS max is 1600 characters (10 segments)
    max_length = 1600
    body.to_s.slice(0, max_length)
  end

  def calculate_segments(body)
    # GSM-7 encoding: 160 chars per segment, 153 if multipart
    # UCS-2 encoding (unicode): 70 chars per segment, 67 if multipart
    length = body.to_s.length

    # Simplified calculation assuming GSM-7
    if length <= 160
      1
    else
      (length.to_f / 153).ceil
    end
  end

  def handle_twilio_error(error, to)
    @logger.error "[TwilioService] Twilio error for #{mask_phone(to)}: #{error.code} - #{error.message}"

    case error.code
    when 21211 # Invalid 'To' Phone Number
      raise InvalidPhoneError, "Invalid phone number: #{to}"
    when 21608 # Unverified number (in trial)
      raise DeliveryError, "Unverified phone number. Please verify in Twilio console."
    when 21614 # Not a valid mobile number
      raise InvalidPhoneError, "Not a valid mobile number: #{to}"
    when 30003 # Unreachable destination
      { success: false, error: 'Phone unreachable', code: error.code, to: to }
    when 30004 # Message blocked
      { success: false, error: 'Message blocked by carrier', code: error.code, to: to }
    when 30005 # Unknown destination
      { success: false, error: 'Unknown destination', code: error.code, to: to }
    else
      raise DeliveryError, "SMS delivery failed: #{error.message} (#{error.code})"
    end
  end
end
