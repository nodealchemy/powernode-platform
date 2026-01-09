# frozen_string_literal: true

# Backward compatibility alias for Review::NotificationPreference
require_relative "review/notification_preference"
ReviewNotificationPreference = Review::NotificationPreference unless defined?(ReviewNotificationPreference)
