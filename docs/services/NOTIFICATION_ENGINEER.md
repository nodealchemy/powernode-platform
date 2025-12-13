# Notification Engineer

**MCP Connection**: `notification_engineer`
**Primary Role**: Notification specialist implementing email, SMS, and real-time communication systems

## Role & Responsibilities

The Notification Engineer specializes in implementing comprehensive notification and communication systems for the Powernode subscription platform. This includes email campaigns, SMS alerts, real-time notifications, and multi-channel communication workflows.

### Core Areas
- **Email System Management**: Transactional and marketing email implementation
- **SMS Integration**: Text message notifications and alerts
- **Real-time Notifications**: WebSocket-based live updates and push notifications
- **Notification Preferences**: User preference management and subscription controls
- **Template Management**: Email and notification template creation and maintenance
- **Delivery Tracking**: Notification delivery status and engagement metrics
- **Multi-channel Orchestration**: Coordinated messaging across all communication channels

### Integration Points
- **Platform Architect**: Notification system architecture and scalability planning
- **Backend Specialists**: Notification triggers and business logic integration
- **Frontend Specialists**: In-app notification display and user preference interfaces
- **Background Job Engineer**: Asynchronous notification processing and queue management
- **Analytics Engineer**: Notification performance metrics and engagement tracking

## Email System Architecture

### Email Service Configuration
```ruby
# config/initializers/email_service.rb
class EmailServiceConfiguration
  include ActiveModel::Model
  
  # Multi-provider email configuration
  EMAIL_PROVIDERS = {
    transactional: {
      primary: :sendgrid,
      fallback: :mailgun,
      config: {
        sendgrid: {
          api_key: Rails.application.credentials.sendgrid_api_key,
          template_engine: 'handlebars',
          webhook_endpoint: '/webhooks/sendgrid'
        },
        mailgun: {
          api_key: Rails.application.credentials.mailgun_api_key,
          domain: Rails.application.credentials.mailgun_domain,
          webhook_endpoint: '/webhooks/mailgun'
        }
      }
    },
    marketing: {
      primary: :mailchimp,
      fallback: :sendgrid,
      config: {
        mailchimp: {
          api_key: Rails.application.credentials.mailchimp_api_key,
          server_prefix: Rails.application.credentials.mailchimp_server,
          webhook_endpoint: '/webhooks/mailchimp'
        }
      }
    }
  }.freeze
  
  def self.configure_email_providers
    # Configure ActionMailer with primary provider
    configure_action_mailer
    
    # Set up webhook handlers for delivery tracking
    configure_webhook_handlers
    
    # Initialize email template engine
    configure_template_engine
  end
  
  private
  
  def self.configure_action_mailer
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = {
      user_name: 'apikey',
      password: EMAIL_PROVIDERS[:transactional][:config][:sendgrid][:api_key],
      domain: 'powernode.com',
      address: 'smtp.sendgrid.net',
      port: 587,
      authentication: :plain,
      enable_starttls_auto: true
    }
  end
end

# Email delivery service with failover
class EmailDeliveryService
  include ActiveModel::Model
  
  DELIVERY_PRIORITIES = {
    critical: { max_retry: 5, delay: 1.minute },
    high: { max_retry: 3, delay: 5.minutes },
    medium: { max_retry: 2, delay: 15.minutes },
    low: { max_retry: 1, delay: 1.hour }
  }.freeze
  
  def self.deliver_email(email_params, priority: :medium)
    email_record = create_email_record(email_params, priority)
    
    begin
      # Attempt delivery with primary provider
      result = deliver_with_provider(email_params, :primary)
      
      # Track successful delivery
      email_record.update!(
        status: 'delivered',
        provider_used: result[:provider],
        delivered_at: Time.current,
        provider_response: result[:response]
      )
      
      result
    rescue EmailDeliveryError => e
      Rails.logger.error "Primary email provider failed: #{e.message}"
      
      # Attempt delivery with fallback provider
      fallback_delivery(email_record, email_params)
    end
  end
  
  private
  
  def self.deliver_with_provider(email_params, provider_type)
    provider = determine_provider(email_params[:type], provider_type)
    
    case provider
    when :sendgrid
      deliver_via_sendgrid(email_params)
    when :mailgun
      deliver_via_mailgun(email_params)
    when :mailchimp
      deliver_via_mailchimp(email_params)
    else
      raise EmailDeliveryError, "Unknown email provider: #{provider}"
    end
  end
  
  def self.deliver_via_sendgrid(email_params)
    mail = SendGrid::Mail.new
    mail.from = SendGrid::Email.new(email: email_params[:from_email], name: email_params[:from_name])
    mail.subject = email_params[:subject]
    
    personalization = SendGrid::Personalization.new
    personalization.add_to(SendGrid::Email.new(email: email_params[:to_email]))
    
    # Add dynamic template data
    if email_params[:template_data]
      email_params[:template_data].each do |key, value|
        personalization.add_dynamic_template_data(key => value)
      end
    end
    
    mail.add_personalization(personalization)
    
    # Use template if specified
    if email_params[:template_id]
      mail.template_id = email_params[:template_id]
    else
      mail.add_content(SendGrid::Content.new(type: 'text/html', value: email_params[:html_content]))
    end
    
    # Send email
    sg = SendGrid::API.new(api_key: Rails.application.credentials.sendgrid_api_key)
    response = sg.client.mail._('send').post(request_body: mail.to_json)
    
    {
      provider: :sendgrid,
      response: response,
      message_id: response.headers['X-Message-Id']
    }
  end
  
  def self.create_email_record(email_params, priority)
    EmailDelivery.create!(
      recipient_email: email_params[:to_email],
      sender_email: email_params[:from_email],
      subject: email_params[:subject],
      email_type: email_params[:type],
      priority: priority,
      status: 'pending',
      template_id: email_params[:template_id],
      template_data: email_params[:template_data],
      scheduled_at: email_params[:scheduled_at] || Time.current,
      created_at: Time.current
    )
  end
end
```

### Email Template System
```ruby
# Email template management
class EmailTemplateManager
  include ActiveModel::Model
  
  TEMPLATE_CATEGORIES = {
    authentication: {
      welcome: 'Welcome to Powernode',
      email_verification: 'Verify Your Email Address',
      password_reset: 'Reset Your Password',
      account_locked: 'Account Security Alert'
    },
    billing: {
      payment_successful: 'Payment Confirmation',
      payment_failed: 'Payment Failed - Action Required',
      subscription_created: 'Subscription Activated',
      subscription_cancelled: 'Subscription Cancelled',
      invoice_generated: 'New Invoice Available'
    },
    notifications: {
      account_activity: 'Account Activity Summary',
      feature_announcement: 'New Feature Available',
      maintenance_notice: 'Scheduled Maintenance',
      security_alert: 'Security Alert'
    }
  }.freeze
  
  def self.render_template(template_key, user, data = {})
    template_info = find_template_info(template_key)
    raise ArgumentError, "Unknown template: #{template_key}" unless template_info
    
    # Prepare template data
    template_data = prepare_template_data(user, data)
    
    # Render template based on engine
    case template_info[:engine]
    when 'liquid'
      render_liquid_template(template_info[:content], template_data)
    when 'erb'
      render_erb_template(template_info[:content], template_data)
    when 'handlebars'
      render_handlebars_template(template_info[:template_id], template_data)
    else
      raise ArgumentError, "Unknown template engine: #{template_info[:engine]}"
    end
  end
  
  def self.create_template(category, name, config)
    template = EmailTemplate.create!(
      category: category,
      name: name,
      subject_template: config[:subject],
      html_content: config[:html_content],
      text_content: config[:text_content],
      template_engine: config[:engine] || 'liquid',
      provider_template_id: config[:provider_template_id],
      variables: config[:variables] || [],
      active: true,
      created_at: Time.current
    )
    
    # Register with email provider if using remote templates
    if config[:provider_template_id] && config[:register_with_provider]
      register_template_with_provider(template, config)
    end
    
    template
  end
  
  private
  
  def self.prepare_template_data(user, additional_data)
    base_data = {
      # User data
      user_name: user&.name || 'User',
      user_email: user&.email,
      user_first_name: user&.name&.split(' ')&.first || 'User',
      
      # Account data
      account_name: user&.account&.name,
      account_subdomain: user&.account&.subdomain,
      
      # System data
      app_name: 'Powernode',
      app_url: Rails.application.routes.url_helpers.root_url,
      support_email: 'support@powernode.com',
      current_year: Date.current.year,
      
      # Branding
      logo_url: "#{Rails.application.routes.url_helpers.root_url}assets/logo.png",
      brand_color: '#3B82F6'
    }
    
    base_data.merge(additional_data)
  end
  
  def self.render_liquid_template(content, data)
    template = Liquid::Template.parse(content)
    template.render(data.stringify_keys)
  end
  
  def self.render_handlebars_template(template_id, data)
    # For SendGrid dynamic templates
    {
      template_id: template_id,
      dynamic_template_data: data
    }
  end
end

# Email template builder service
class EmailTemplateBuilder
  def self.build_default_templates
    # Authentication templates
    build_authentication_templates
    
    # Billing templates
    build_billing_templates
    
    # Notification templates
    build_notification_templates
    
    Rails.logger.info "Built #{EmailTemplate.count} email templates"
  end
  
  private
  
  def self.build_authentication_templates
    EmailTemplateManager.create_template(:authentication, :welcome, {
      subject: 'Welcome to {{app_name}}, {{user_first_name}}!',
      html_content: load_template_content('welcome.html.liquid'),
      text_content: load_template_content('welcome.txt.liquid'),
      engine: 'liquid',
      variables: %w[user_first_name app_name app_url account_name]
    })
    
    EmailTemplateManager.create_template(:authentication, :email_verification, {
      subject: 'Verify your email address for {{app_name}}',
      html_content: load_template_content('email_verification.html.liquid'),
      text_content: load_template_content('email_verification.txt.liquid'),
      engine: 'liquid',
      variables: %w[user_first_name verification_url app_name]
    })
  end
  
  def self.build_billing_templates
    EmailTemplateManager.create_template(:billing, :payment_successful, {
      subject: 'Payment confirmation - ${{amount}} {{currency}}',
      html_content: load_template_content('payment_successful.html.liquid'),
      text_content: load_template_content('payment_successful.txt.liquid'),
      engine: 'liquid',
      variables: %w[user_first_name amount currency payment_date invoice_url]
    })
    
    EmailTemplateManager.create_template(:billing, :subscription_created, {
      subject: 'Your {{plan_name}} subscription is now active',
      html_content: load_template_content('subscription_created.html.liquid'),
      text_content: load_template_content('subscription_created.txt.liquid'),
      engine: 'liquid',
      variables: %w[user_first_name plan_name billing_cycle next_billing_date manage_subscription_url]
    })
  end
end
```

## SMS Integration System

### SMS Service Configuration
```ruby
# SMS service with multiple provider support
class SmsService
  include ActiveModel::Model
  
  SMS_PROVIDERS = {
    primary: :twilio,
    fallback: :aws_sns,
    config: {
      twilio: {
        account_sid: Rails.application.credentials.twilio_account_sid,
        auth_token: Rails.application.credentials.twilio_auth_token,
        from_number: Rails.application.credentials.twilio_from_number
      },
      aws_sns: {
        access_key: Rails.application.credentials.aws_access_key,
        secret_key: Rails.application.credentials.aws_secret_key,
        region: Rails.application.credentials.aws_region
      }
    }
  }.freeze
  
  def self.send_sms(phone_number, message, options = {})
    sms_record = create_sms_record(phone_number, message, options)
    
    begin
      # Format and validate phone number
      formatted_number = format_phone_number(phone_number)
      validate_phone_number(formatted_number)
      
      # Send SMS with primary provider
      result = send_with_provider(formatted_number, message, :primary)
      
      # Update SMS record with success
      sms_record.update!(
        status: 'sent',
        provider_used: result[:provider],
        sent_at: Time.current,
        provider_message_id: result[:message_id],
        provider_response: result[:response]
      )
      
      result
    rescue SmsDeliveryError => e
      Rails.logger.error "SMS delivery failed: #{e.message}"
      
      # Attempt fallback delivery
      fallback_sms_delivery(sms_record, formatted_number, message)
    end
  end
  
  def self.send_verification_code(user, code)
    message = "Your Powernode verification code is: #{code}. This code expires in 10 minutes."
    
    send_sms(user.phone, message, {
      type: 'verification',
      user_id: user.id,
      expires_at: 10.minutes.from_now
    })
  end
  
  def self.send_security_alert(user, alert_message)
    message = "Powernode Security Alert: #{alert_message}. If this wasn't you, please contact support immediately."
    
    send_sms(user.phone, message, {
      type: 'security_alert',
      user_id: user.id,
      priority: 'high'
    })
  end
  
  private
  
  def self.send_with_provider(phone_number, message, provider_type)
    provider = provider_type == :primary ? SMS_PROVIDERS[:primary] : SMS_PROVIDERS[:fallback]
    
    case provider
    when :twilio
      send_via_twilio(phone_number, message)
    when :aws_sns
      send_via_aws_sns(phone_number, message)
    else
      raise SmsDeliveryError, "Unknown SMS provider: #{provider}"
    end
  end
  
  def self.send_via_twilio(phone_number, message)
    client = Twilio::REST::Client.new(
      SMS_PROVIDERS[:config][:twilio][:account_sid],
      SMS_PROVIDERS[:config][:twilio][:auth_token]
    )
    
    response = client.messages.create(
      from: SMS_PROVIDERS[:config][:twilio][:from_number],
      to: phone_number,
      body: message
    )
    
    {
      provider: :twilio,
      message_id: response.sid,
      response: response
    }
  end
  
  def self.format_phone_number(phone_number)
    # Remove all non-digit characters
    digits = phone_number.gsub(/\D/, '')
    
    # Add country code if missing (assume US)
    digits = "1#{digits}" if digits.length == 10
    
    # Format as E.164
    "+#{digits}"
  end
  
  def self.create_sms_record(phone_number, message, options)
    SmsDelivery.create!(
      phone_number: phone_number,
      message: message,
      sms_type: options[:type] || 'notification',
      user_id: options[:user_id],
      priority: options[:priority] || 'medium',
      status: 'pending',
      expires_at: options[:expires_at],
      created_at: Time.current
    )
  end
end

# SMS template management
class SmsTemplateManager
  include ActiveModel::Model
  
  SMS_TEMPLATES = {
    verification: 'Your {{app_name}} verification code is: {{code}}. This code expires in {{expiry_minutes}} minutes.',
    payment_failed: '{{app_name}} Alert: Your payment of ${{amount}} failed. Please update your payment method at {{payment_url}}',
    subscription_expiry: '{{app_name}}: Your subscription expires in {{days}} days. Renew at {{renewal_url}}',
    security_alert: '{{app_name}} Security Alert: {{alert_message}}. Contact support if this wasn\'t you.',
    password_reset: 'Your {{app_name}} password reset code is: {{code}}. Use this code within {{expiry_minutes}} minutes.',
    login_alert: '{{app_name}}: New login from {{location}} on {{device}}. Contact support if this wasn\'t you.'
  }.freeze
  
  def self.render_sms_template(template_key, data = {})
    template = SMS_TEMPLATES[template_key.to_sym]
    raise ArgumentError, "Unknown SMS template: #{template_key}" unless template
    
    # Replace template variables
    message = template.dup
    data.each do |key, value|
      message.gsub!("{{#{key}}}", value.to_s)
    end
    
    # Ensure message length compliance (160 chars for single SMS)
    if message.length > 160
      Rails.logger.warn "SMS message exceeds 160 characters: #{message.length} chars"
    end
    
    message
  end
end
```

## Real-time Notification System

### WebSocket Notification Service
```ruby
# Real-time notification via Action Cable
class NotificationChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe user to their personal notification channel
    stream_from "notifications:user:#{current_user.id}"
    
    # Subscribe to account-wide notifications if user has permission
    if current_user.permissions.include?('account.notifications')
      stream_from "notifications:account:#{current_user.account_id}"
    end
    
    # Mark user as online
    NotificationPresenceService.mark_online(current_user)
  end
  
  def unsubscribed
    # Mark user as offline
    NotificationPresenceService.mark_offline(current_user)
  end
  
  def mark_as_read(data)
    notification_ids = data['notification_ids'] || []
    
    notifications = Notification.where(
      id: notification_ids,
      user_id: current_user.id,
      read_at: nil
    )
    
    notifications.update_all(read_at: Time.current, updated_at: Time.current)
    
    # Broadcast updated unread count
    broadcast_unread_count(current_user)
  end
  
  private
  
  def broadcast_unread_count(user)
    unread_count = Notification.where(user_id: user.id, read_at: nil).count
    
    ActionCable.server.broadcast("notifications:user:#{user.id}", {
      type: 'unread_count_update',
      unread_count: unread_count
    })
  end
end

# Real-time notification broadcasting service
class RealtimeNotificationService
  include ActiveModel::Model
  
  NOTIFICATION_TYPES = {
    system: { icon: '🔧', color: 'blue', priority: 'medium' },
    billing: { icon: '💳', color: 'green', priority: 'high' },
    security: { icon: '🔒', color: 'red', priority: 'critical' },
    feature: { icon: '✨', color: 'purple', priority: 'low' },
    social: { icon: '👥', color: 'orange', priority: 'low' }
  }.freeze
  
  def self.broadcast_notification(user, notification_data)
    # Create notification record
    notification = Notification.create!(
      user_id: user.id,
      account_id: user.account_id,
      title: notification_data[:title],
      message: notification_data[:message],
      notification_type: notification_data[:type],
      priority: notification_data[:priority] || 'medium',
      action_url: notification_data[:action_url],
      action_label: notification_data[:action_label],
      metadata: notification_data[:metadata] || {},
      created_at: Time.current
    )
    
    # Broadcast real-time notification
    broadcast_data = format_notification_for_broadcast(notification)
    ActionCable.server.broadcast("notifications:user:#{user.id}", broadcast_data)
    
    # Send push notification if user is offline
    if should_send_push_notification?(user, notification)
      PushNotificationService.send_push_notification(user, notification)
    end
    
    notification
  end
  
  def self.broadcast_account_notification(account, notification_data)
    # Create notifications for all account users
    notifications = account.users.active.map do |user|
      Notification.create!(
        user_id: user.id,
        account_id: account.id,
        title: notification_data[:title],
        message: notification_data[:message],
        notification_type: notification_data[:type],
        priority: notification_data[:priority] || 'medium',
        action_url: notification_data[:action_url],
        action_label: notification_data[:action_label],
        metadata: notification_data[:metadata] || {},
        created_at: Time.current
      )
    end
    
    # Broadcast to account channel
    broadcast_data = format_notification_for_broadcast(notifications.first)
    ActionCable.server.broadcast("notifications:account:#{account.id}", broadcast_data)
    
    notifications
  end
  
  private
  
  def self.format_notification_for_broadcast(notification)
    type_config = NOTIFICATION_TYPES[notification.notification_type.to_sym] || NOTIFICATION_TYPES[:system]
    
    {
      type: 'new_notification',
      notification: {
        id: notification.id,
        title: notification.title,
        message: notification.message,
        notification_type: notification.notification_type,
        priority: notification.priority,
        icon: type_config[:icon],
        color: type_config[:color],
        action_url: notification.action_url,
        action_label: notification.action_label,
        created_at: notification.created_at.iso8601,
        read: false
      }
    }
  end
  
  def self.should_send_push_notification?(user, notification)
    # Don't send push if user is currently online
    return false if NotificationPresenceService.online?(user)
    
    # Check user's notification preferences
    preferences = user.notification_preferences || {}
    type_preference = preferences[notification.notification_type]
    
    # Default to sending push for high and critical priority
    return %w[high critical].include?(notification.priority) if type_preference.nil?
    
    type_preference['push_enabled'] == true
  end
end
```

### Push Notification Integration
```ruby
# Push notification service for mobile/browser notifications
class PushNotificationService
  include ActiveModel::Model
  
  PUSH_PROVIDERS = {
    web: :web_push,
    ios: :apns,
    android: :fcm
  }.freeze
  
  def self.send_push_notification(user, notification)
    # Get user's push notification subscriptions
    push_subscriptions = user.push_subscriptions.active
    
    push_subscriptions.each do |subscription|
      begin
        case subscription.platform
        when 'web'
          send_web_push(subscription, notification)
        when 'ios'
          send_apns_push(subscription, notification)
        when 'android'
          send_fcm_push(subscription, notification)
        end
        
        # Track successful push notification
        PushNotificationDelivery.create!(
          user_id: user.id,
          notification_id: notification.id,
          push_subscription_id: subscription.id,
          status: 'delivered',
          delivered_at: Time.current
        )
        
      rescue PushDeliveryError => e
        Rails.logger.error "Push notification failed for user #{user.id}: #{e.message}"
        
        # Mark subscription as inactive if permanently failed
        if e.permanent_failure?
          subscription.update!(active: false, deactivated_at: Time.current)
        end
        
        # Track failed delivery
        PushNotificationDelivery.create!(
          user_id: user.id,
          notification_id: notification.id,
          push_subscription_id: subscription.id,
          status: 'failed',
          error_message: e.message,
          created_at: Time.current
        )
      end
    end
  end
  
  def self.register_push_subscription(user, subscription_data)
    # Remove existing subscriptions for the same endpoint
    user.push_subscriptions.where(endpoint: subscription_data[:endpoint]).destroy_all
    
    # Create new subscription
    user.push_subscriptions.create!(
      platform: subscription_data[:platform],
      endpoint: subscription_data[:endpoint],
      p256dh_key: subscription_data[:keys][:p256dh],
      auth_key: subscription_data[:keys][:auth],
      active: true,
      created_at: Time.current
    )
  end
  
  private
  
  def self.send_web_push(subscription, notification)
    message = {
      title: notification.title,
      body: notification.message,
      icon: '/assets/notification-icon.png',
      badge: '/assets/badge-icon.png',
      data: {
        notification_id: notification.id,
        action_url: notification.action_url,
        created_at: notification.created_at.iso8601
      },
      actions: notification.action_url ? [{
        action: 'open',
        title: notification.action_label || 'Open'
      }] : []
    }
    
    WebPush.payload_send(
      message: message.to_json,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh_key,
      auth: subscription.auth_key,
      vapid: {
        subject: 'mailto:support@powernode.com',
        public_key: Rails.application.credentials.vapid_public_key,
        private_key: Rails.application.credentials.vapid_private_key
      }
    )
  end
  
  def self.send_fcm_push(subscription, notification)
    fcm = FCM.new(Rails.application.credentials.fcm_server_key)
    
    response = fcm.send([subscription.endpoint], {
      notification: {
        title: notification.title,
        body: notification.message,
        icon: 'notification_icon',
        sound: 'default'
      },
      data: {
        notification_id: notification.id.to_s,
        action_url: notification.action_url,
        created_at: notification.created_at.iso8601
      }
    })
    
    raise PushDeliveryError, "FCM delivery failed: #{response}" unless response[:success] > 0
  end
end
```

## Notification Preferences & Management

### User Notification Preferences
```ruby
# Notification preference management
class NotificationPreferencesService
  include ActiveModel::Model
  
  DEFAULT_PREFERENCES = {
    # Email preferences
    email_notifications: {
      authentication: { enabled: true, frequency: 'immediate' },
      billing: { enabled: true, frequency: 'immediate' },
      security: { enabled: true, frequency: 'immediate' },
      feature_updates: { enabled: true, frequency: 'weekly' },
      marketing: { enabled: false, frequency: 'monthly' }
    },
    
    # SMS preferences
    sms_notifications: {
      security_alerts: { enabled: true },
      payment_failures: { enabled: true },
      verification_codes: { enabled: true },
      marketing: { enabled: false }
    },
    
    # Push notification preferences
    push_notifications: {
      real_time_alerts: { enabled: true },
      billing_reminders: { enabled: true },
      feature_announcements: { enabled: false },
      marketing: { enabled: false }
    },
    
    # In-app notification preferences
    in_app_notifications: {
      all_types: { enabled: true },
      auto_dismiss: { enabled: false, delay: 5000 },
      sound_enabled: { enabled: true }
    }
  }.freeze
  
  def self.initialize_user_preferences(user)
    user.update!(
      notification_preferences: DEFAULT_PREFERENCES,
      preferences_updated_at: Time.current
    )
  end
  
  def self.update_preferences(user, preference_updates)
    current_preferences = user.notification_preferences || DEFAULT_PREFERENCES
    updated_preferences = deep_merge_preferences(current_preferences, preference_updates)
    
    user.update!(
      notification_preferences: updated_preferences,
      preferences_updated_at: Time.current
    )
    
    # Log preference changes for audit
    NotificationPreferenceChange.create!(
      user_id: user.id,
      changes: preference_updates,
      changed_at: Time.current
    )
    
    updated_preferences
  end
  
  def self.should_send_notification?(user, notification_type, delivery_method)
    preferences = user.notification_preferences || DEFAULT_PREFERENCES
    type_preferences = preferences["#{delivery_method}_notifications"]
    
    return true unless type_preferences # Default to sending if no preferences set
    
    setting = type_preferences[notification_type.to_s]
    return true unless setting # Default to sending if specific type not configured
    
    setting['enabled'] == true
  end
  
  def self.get_notification_frequency(user, notification_type, delivery_method)
    preferences = user.notification_preferences || DEFAULT_PREFERENCES
    type_preferences = preferences["#{delivery_method}_notifications"]
    
    return 'immediate' unless type_preferences
    
    setting = type_preferences[notification_type.to_s]
    return 'immediate' unless setting
    
    setting['frequency'] || 'immediate'
  end
  
  private
  
  def self.deep_merge_preferences(current, updates)
    current.deep_dup.tap do |merged|
      updates.each do |key, value|
        if value.is_a?(Hash) && merged[key].is_a?(Hash)
          merged[key] = deep_merge_preferences(merged[key], value)
        else
          merged[key] = value
        end
      end
    end
  end
end

# Notification digest service for batched notifications
class NotificationDigestService
  include ActiveModel::Model
  
  DIGEST_FREQUENCIES = %w[immediate hourly daily weekly monthly].freeze
  
  def self.process_notification_digests
    DIGEST_FREQUENCIES.each do |frequency|
      next if frequency == 'immediate' # Skip immediate notifications
      
      users_for_frequency = find_users_with_frequency(frequency)
      users_for_frequency.each { |user| send_digest_for_user(user, frequency) }
    end
  end
  
  private
  
  def self.find_users_with_frequency(frequency)
    User.active.joins(:notification_preferences).where(
      "notification_preferences->>'frequency' = ?", frequency
    )
  end
  
  def self.send_digest_for_user(user, frequency)
    # Get undelivered notifications for the user based on frequency
    notifications = get_notifications_for_digest(user, frequency)
    return if notifications.empty?
    
    # Group notifications by type
    grouped_notifications = notifications.group_by(&:notification_type)
    
    # Generate digest content
    digest_content = generate_digest_content(user, grouped_notifications, frequency)
    
    # Send digest email
    NotificationMailer.digest_email(user, digest_content, frequency).deliver_now
    
    # Mark notifications as delivered
    notifications.update_all(
      delivered_at: Time.current,
      delivery_method: "#{frequency}_digest",
      updated_at: Time.current
    )
  end
  
  def self.generate_digest_content(user, grouped_notifications, frequency)
    {
      user: user,
      frequency: frequency,
      period: get_period_description(frequency),
      notification_groups: grouped_notifications.map do |type, notifications|
        {
          type: type,
          count: notifications.count,
          notifications: notifications.limit(5), # Show max 5 per type in digest
          has_more: notifications.count > 5
        }
      end,
      total_count: grouped_notifications.values.flatten.count
    }
  end
end
```

## Notification Analytics & Tracking

### Delivery Tracking & Analytics
```ruby
# Notification analytics service
class NotificationAnalyticsService
  include ActiveModel::Model
  
  def self.generate_delivery_report(start_date, end_date)
    report_data = {
      period: { start: start_date, end: end_date },
      email: analyze_email_deliveries(start_date, end_date),
      sms: analyze_sms_deliveries(start_date, end_date),
      push: analyze_push_deliveries(start_date, end_date),
      in_app: analyze_in_app_notifications(start_date, end_date)
    }
    
    # Calculate overall metrics
    report_data[:overall] = calculate_overall_metrics(report_data)
    
    # Store report
    NotificationAnalyticsReport.create!(
      report_data: report_data,
      report_period_start: start_date,
      report_period_end: end_date,
      generated_at: Time.current
    )
    
    report_data
  end
  
  def self.track_notification_engagement(notification_id, engagement_type)
    notification = Notification.find(notification_id)
    
    NotificationEngagement.create!(
      notification_id: notification_id,
      user_id: notification.user_id,
      engagement_type: engagement_type, # clicked, dismissed, action_taken
      engaged_at: Time.current
    )
    
    # Update notification with engagement data
    engagement_data = notification.engagement_data || {}
    engagement_data[engagement_type] = (engagement_data[engagement_type] || 0) + 1
    notification.update!(engagement_data: engagement_data)
  end
  
  private
  
  def self.analyze_email_deliveries(start_date, end_date)
    email_deliveries = EmailDelivery.where(created_at: start_date..end_date)
    
    {
      total_sent: email_deliveries.count,
      delivered: email_deliveries.where(status: 'delivered').count,
      failed: email_deliveries.where(status: 'failed').count,
      bounced: email_deliveries.where(status: 'bounced').count,
      opened: email_deliveries.where('opened_at IS NOT NULL').count,
      clicked: email_deliveries.where('clicked_at IS NOT NULL').count,
      delivery_rate: calculate_rate(email_deliveries.where(status: 'delivered').count, email_deliveries.count),
      open_rate: calculate_rate(email_deliveries.where('opened_at IS NOT NULL').count, email_deliveries.where(status: 'delivered').count),
      click_rate: calculate_rate(email_deliveries.where('clicked_at IS NOT NULL').count, email_deliveries.where('opened_at IS NOT NULL').count),
      by_type: email_deliveries.group(:email_type).group(:status).count
    }
  end
  
  def self.analyze_push_deliveries(start_date, end_date)
    push_deliveries = PushNotificationDelivery.where(created_at: start_date..end_date)
    
    {
      total_sent: push_deliveries.count,
      delivered: push_deliveries.where(status: 'delivered').count,
      failed: push_deliveries.where(status: 'failed').count,
      delivery_rate: calculate_rate(push_deliveries.where(status: 'delivered').count, push_deliveries.count),
      by_platform: push_deliveries.joins(:push_subscription).group('push_subscriptions.platform').group(:status).count
    }
  end
  
  def self.calculate_overall_metrics(report_data)
    total_sent = %i[email sms push in_app].sum { |type| report_data[type][:total_sent] }
    total_delivered = %i[email sms push in_app].sum { |type| report_data[type][:delivered] || report_data[type][:total_sent] }
    
    {
      total_notifications_sent: total_sent,
      total_delivered: total_delivered,
      overall_delivery_rate: calculate_rate(total_delivered, total_sent),
      most_effective_channel: determine_most_effective_channel(report_data),
      engagement_summary: calculate_engagement_summary(report_data)
    }
  end
end

# Notification performance monitoring
class NotificationPerformanceMonitor
  def self.monitor_delivery_performance
    # Monitor email delivery rates
    recent_email_failures = EmailDelivery.where(
      created_at: 1.hour.ago..Time.current,
      status: 'failed'
    ).count
    
    if recent_email_failures > 10
      create_performance_alert('high_email_failure_rate', {
        failure_count: recent_email_failures,
        time_period: '1 hour'
      })
    end
    
    # Monitor SMS delivery rates
    recent_sms_failures = SmsDelivery.where(
      created_at: 1.hour.ago..Time.current,
      status: 'failed'
    ).count
    
    if recent_sms_failures > 5
      create_performance_alert('high_sms_failure_rate', {
        failure_count: recent_sms_failures,
        time_period: '1 hour'
      })
    end
    
    # Monitor push notification delivery
    recent_push_failures = PushNotificationDelivery.where(
      created_at: 1.hour.ago..Time.current,
      status: 'failed'
    ).count
    
    if recent_push_failures > 20
      create_performance_alert('high_push_failure_rate', {
        failure_count: recent_push_failures,
        time_period: '1 hour'
      })
    end
  end
  
  private
  
  def self.create_performance_alert(alert_type, data)
    NotificationPerformanceAlert.create!(
      alert_type: alert_type,
      alert_data: data,
      status: 'open',
      created_at: Time.current
    )
    
    # Send immediate alert to operations team
    NotificationMailer.performance_alert(alert_type, data).deliver_now
  end
end
```

## Development Commands

### Notification System Management
```bash
# Email system
cd server && rails runner "EmailTemplateBuilder.build_default_templates"    # Build email templates
cd server && rails runner "EmailDeliveryService.test_email_providers"       # Test email providers

# SMS system  
cd server && rails runner "SmsService.test_sms_delivery('+1234567890', 'Test message')"  # Test SMS
cd server && rails runner "SmsService.validate_sms_providers"               # Validate SMS config

# Push notifications
cd server && rails runner "PushNotificationService.test_push_delivery"      # Test push notifications
cd server && rails runner "WebPush.generate_key"                           # Generate VAPID keys

# Real-time notifications
cd server && rails runner "RealtimeNotificationService.broadcast_test_notification"  # Test WebSocket
```

### Analytics & Monitoring
```bash
# Generate notification reports
cd server && rails runner "NotificationAnalyticsService.generate_delivery_report(7.days.ago, Time.current)"

# Monitor performance
cd server && rails runner "NotificationPerformanceMonitor.monitor_delivery_performance"

# Preference management
cd server && rails runner "NotificationPreferencesService.audit_user_preferences"

# Digest processing
cd server && rails runner "NotificationDigestService.process_notification_digests"
```

### Template Management
```bash
# Email templates
cd server && rails runner "EmailTemplateManager.render_template(:welcome, User.first)"
cd server && rails runner "EmailTemplateManager.validate_all_templates"

# SMS templates  
cd server && rails runner "SmsTemplateManager.render_sms_template(:verification, { app_name: 'Powernode', code: '123456', expiry_minutes: 10 })"
```

## Integration Points

### Platform Architect Coordination
- **Communication Architecture**: Design scalable notification and messaging architecture
- **Multi-channel Strategy**: Coordinate notification delivery across all communication channels
- **Performance Requirements**: Define and monitor notification system performance targets
- **Integration Planning**: Plan notification system integration with all platform components

### Backend Specialist Integration
- **Trigger Implementation**: Implement notification triggers for business events
- **Data Integration**: Ensure proper data flow between business logic and notification systems
- **API Endpoints**: Create APIs for notification management and user preferences
- **Background Processing**: Coordinate with background job system for notification delivery

### Frontend Specialist Integration
- **In-app Notifications**: Implement real-time notification display components
- **User Preferences**: Build user preference management interfaces
- **Push Notification Registration**: Implement browser/mobile push notification registration
- **Notification History**: Create notification history and management interfaces

### Analytics Engineer Coordination
- **Engagement Tracking**: Implement notification engagement and conversion tracking
- **Performance Metrics**: Provide notification delivery and engagement metrics
- **A/B Testing**: Support notification content and timing A/B testing
- **Reporting Dashboard**: Create notification analytics dashboards

## Quick Reference

### Notification Types & Priorities
```ruby
# Email Types
authentication: welcome, verification, password_reset
billing: payment_success, payment_failed, subscription_changes
security: login_alerts, security_breaches, account_locks
marketing: feature_announcements, newsletters, promotions

# SMS Types  
verification: auth_codes, password_reset_codes
security: login_alerts, suspicious_activity
billing: payment_failures, subscription_expiry
emergency: system_outages, critical_alerts

# Push Notification Types
real_time: instant_messages, live_updates
billing: payment_reminders, invoice_notifications  
engagement: feature_tips, activity_summaries
```

### Configuration Commands
```bash
# Provider setup
rails credentials:edit                              # Configure API keys
rails runner "EmailServiceConfiguration.configure_email_providers"  # Setup email
rails runner "SmsService.configure_providers"      # Setup SMS

# Template management
rails runner "EmailTemplateBuilder.build_default_templates"  # Create templates
rails db:seed:notifications                        # Seed notification data

# Performance monitoring  
rails runner "NotificationPerformanceMonitor.monitor_delivery_performance"  # Check health
```

### Emergency Procedures
- **Email Service Down**: Switch to fallback provider, check API keys, verify DNS
- **SMS Delivery Issues**: Test provider connection, check phone number formats
- **Push Notifications Failing**: Verify certificates, check subscription endpoints
- **WebSocket Issues**: Restart Action Cable, check Redis connection
- **High Bounce Rate**: Review email content, check sender reputation

## Quick Reference

### Essential Notification Commands
```bash
# Notification management - run from $POWERNODE_ROOT/server
cd $POWERNODE_ROOT/server && rails notifications:send_pending      # Process pending notifications
cd $POWERNODE_ROOT/server && rails notifications:retry_failed      # Retry failed notifications
cd $POWERNODE_ROOT/server && rails notifications:clean_old         # Clean old notifications

# Email management
cd $POWERNODE_ROOT/server && rails email:test_delivery             # Test email delivery
cd $POWERNODE_ROOT/server && rails email:check_bounce_rate         # Check bounce rates
cd $POWERNODE_ROOT/server && rails email:update_templates          # Update email templates

# SMS management
cd $POWERNODE_ROOT/server && rails sms:test_delivery               # Test SMS delivery
cd $POWERNODE_ROOT/server && rails sms:validate_numbers            # Validate phone numbers
cd $POWERNODE_ROOT/server && rails sms:check_delivery_status       # Check SMS delivery status

# Push notifications
cd $POWERNODE_ROOT/server && rails push:send_test                  # Send test push notification
cd $POWERNODE_ROOT/server && rails push:update_subscriptions       # Update push subscriptions
cd $POWERNODE_ROOT/server && rails push:clean_expired              # Clean expired subscriptions

# Real-time notifications
cd $POWERNODE_ROOT/server && rails websocket:broadcast_test        # Test WebSocket broadcast
cd $POWERNODE_ROOT/server && rails websocket:check_connections     # Check active connections
```

### Notification Types
- **Email**: Transactional emails, marketing campaigns, system alerts
- **SMS**: Account verification, payment alerts, security notifications
- **Push Notifications**: Mobile app notifications, browser push notifications
- **In-App**: Real-time notifications within the application
- **WebSocket**: Live updates, chat messages, system broadcasts

### Provider Configuration
```bash
# SendGrid (Primary Email)
export SENDGRID_API_KEY="your-api-key"
export SENDGRID_FROM_EMAIL="noreply@powernode.com"

# Mailgun (Backup Email)
export MAILGUN_API_KEY="your-api-key"
export MAILGUN_DOMAIN="powernode.com"

# Twilio (SMS)
export TWILIO_ACCOUNT_SID="your-account-sid"
export TWILIO_AUTH_TOKEN="your-auth-token"
export TWILIO_PHONE_NUMBER="+1234567890"

# Firebase (Push Notifications)
export FIREBASE_PROJECT_ID="your-project-id"
export FIREBASE_PRIVATE_KEY="your-private-key"
```

### Monitoring Commands
```bash
# Check notification queue status
cd $POWERNODE_ROOT/server && rails runner "NotificationQueue.status"

# View delivery statistics
cd $POWERNODE_ROOT/server && rails runner "NotificationStats.daily_report"

# Check provider health
cd $POWERNODE_ROOT/server && rails runner "NotificationProviders.health_check"
```

### Troubleshooting
- **High Failure Rate**: Check provider status, verify credentials, review content
- **Delayed Delivery**: Check queue backlog, scale workers, verify provider limits
- **Bounce Issues**: Clean email lists, check sender reputation, verify DNS records
- **SMS Failures**: Validate phone numbers, check Twilio balance, verify message content
- **Push Not Delivered**: Check subscription status, verify certificates, test endpoints

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**