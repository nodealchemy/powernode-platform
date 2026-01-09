# frozen_string_literal: true

# Backward compatibility alias for Review::NotificationDelivery
require_relative "review/notification_delivery"
ReviewNotificationDelivery = Review::NotificationDelivery unless defined?(ReviewNotificationDelivery)
