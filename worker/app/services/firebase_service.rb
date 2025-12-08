# frozen_string_literal: true

require 'googleauth'
require 'google/apis/fcm_v1'

# Firebase Cloud Messaging service for push notifications
class FirebaseService
  class FirebaseError < StandardError; end
  class ConfigurationError < FirebaseError; end
  class DeliveryError < FirebaseError; end
  class InvalidTokenError < FirebaseError; end

  FCM = Google::Apis::FcmV1

  def initialize
    validate_configuration!
    @logger = PowernodeWorker.logger
    setup_fcm_client
  end

  # Send push notification to a single device
  # @param device_token [String] FCM device registration token
  # @param title [String] Notification title
  # @param body [String] Notification body
  # @param data [Hash] Custom data payload
  # @param options [Hash] Additional notification options
  # @return [Hash] Result with success status
  def send_notification(device_token:, title:, body:, data: {}, options: {})
    @logger.info "[FirebaseService] Sending push to device: #{mask_token(device_token)}"

    message = build_message(device_token, title, body, data, options)

    begin
      result = @fcm.send_message(
        "projects/#{project_id}",
        FCM::SendMessageRequest.new(message: message)
      )

      @logger.info "[FirebaseService] Push sent successfully: #{result.name}"

      {
        success: true,
        message_id: result.name,
        device_token: device_token
      }
    rescue Google::Apis::ClientError => e
      handle_fcm_error(e, device_token)
    end
  end

  # Send push notification to multiple devices
  # @param device_tokens [Array<String>] Array of FCM device tokens
  # @param title [String] Notification title
  # @param body [String] Notification body
  # @param data [Hash] Custom data payload
  # @return [Hash] Batch result
  def send_multicast(device_tokens:, title:, body:, data: {})
    results = device_tokens.map do |token|
      send_notification(
        device_token: token,
        title: title,
        body: body,
        data: data
      )
    end

    failed_tokens = results.select { |r| r[:invalid_token] }.map { |r| r[:device_token] }

    {
      success: results.all? { |r| r[:success] || r[:invalid_token] },
      total: device_tokens.count,
      sent: results.count { |r| r[:success] },
      failed: results.count { |r| !r[:success] && !r[:invalid_token] },
      invalid_tokens: failed_tokens,
      results: results
    }
  end

  # Send notification to a topic
  # @param topic [String] Topic name
  # @param title [String] Notification title
  # @param body [String] Notification body
  # @param data [Hash] Custom data payload
  # @return [Hash] Result
  def send_to_topic(topic:, title:, body:, data: {})
    @logger.info "[FirebaseService] Sending push to topic: #{topic}"

    message = FCM::Message.new(
      topic: topic,
      notification: FCM::Notification.new(
        title: title,
        body: body
      ),
      data: data.transform_values(&:to_s)
    )

    result = @fcm.send_message(
      "projects/#{project_id}",
      FCM::SendMessageRequest.new(message: message)
    )

    {
      success: true,
      message_id: result.name,
      topic: topic
    }
  rescue Google::Apis::ClientError => e
    @logger.error "[FirebaseService] Topic send error: #{e.message}"
    { success: false, error: e.message, topic: topic }
  end

  # Subscribe device to a topic
  # @param device_token [String] FCM device token
  # @param topic [String] Topic name
  # @return [Hash] Result
  def subscribe_to_topic(device_token:, topic:)
    # FCM v1 API doesn't directly support topic subscription
    # This would require the FCM Admin SDK or Instance ID API
    @logger.warn "[FirebaseService] Topic subscription requires Instance ID API"
    { success: false, error: 'Not implemented - use Instance ID API' }
  end

  private

  def project_id
    ENV['FIREBASE_PROJECT_ID']
  end

  def credentials_path
    ENV['GOOGLE_APPLICATION_CREDENTIALS']
  end

  def credentials_json
    ENV['FIREBASE_CREDENTIALS_JSON']
  end

  def validate_configuration!
    unless project_id.present?
      raise ConfigurationError, "Missing FIREBASE_PROJECT_ID environment variable"
    end

    unless credentials_path.present? || credentials_json.present?
      raise ConfigurationError, "Missing Firebase credentials. Set GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_CREDENTIALS_JSON"
    end
  end

  def setup_fcm_client
    @fcm = FCM::FirebaseCloudMessagingService.new

    # Load credentials
    if credentials_path.present? && File.exist?(credentials_path)
      @fcm.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(credentials_path),
        scope: 'https://www.googleapis.com/auth/firebase.messaging'
      )
    elsif credentials_json.present?
      @fcm.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(credentials_json),
        scope: 'https://www.googleapis.com/auth/firebase.messaging'
      )
    else
      raise ConfigurationError, "Could not load Firebase credentials"
    end
  end

  def build_message(device_token, title, body, data, options)
    notification = FCM::Notification.new(
      title: title,
      body: body,
      image: options[:image]
    )

    # Android-specific configuration
    android = FCM::AndroidConfig.new(
      priority: options[:priority] || 'high',
      notification: FCM::AndroidNotification.new(
        icon: options[:icon],
        color: options[:color],
        sound: options[:sound] || 'default',
        click_action: options[:click_action],
        channel_id: options[:channel_id]
      )
    )

    # iOS-specific configuration
    apns = FCM::ApnsConfig.new(
      payload: {
        aps: {
          alert: { title: title, body: body },
          sound: options[:sound] || 'default',
          badge: options[:badge],
          'content-available' => options[:content_available] ? 1 : 0,
          'mutable-content' => options[:mutable_content] ? 1 : 0
        }
      }.to_json
    )

    FCM::Message.new(
      token: device_token,
      notification: notification,
      data: data.transform_values(&:to_s),
      android: android,
      apns: apns
    )
  end

  def mask_token(token)
    return 'nil' unless token
    "#{token[0..7]}...#{token[-4..]}"
  end

  def handle_fcm_error(error, device_token)
    error_body = JSON.parse(error.body) rescue {}
    error_code = error_body.dig('error', 'details', 0, 'errorCode')

    @logger.error "[FirebaseService] FCM error: #{error.message}"

    case error_code
    when 'UNREGISTERED', 'INVALID_ARGUMENT'
      # Token is invalid or expired - should be removed
      {
        success: false,
        error: 'Invalid or expired token',
        invalid_token: true,
        device_token: device_token
      }
    when 'SENDER_ID_MISMATCH'
      raise ConfigurationError, "Sender ID mismatch - check Firebase project configuration"
    when 'QUOTA_EXCEEDED'
      raise DeliveryError, "FCM quota exceeded"
    when 'UNAVAILABLE', 'INTERNAL'
      # Transient error - can retry
      raise DeliveryError, "FCM service temporarily unavailable"
    else
      {
        success: false,
        error: error.message,
        device_token: device_token
      }
    end
  end
end
