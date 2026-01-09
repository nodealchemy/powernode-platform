# frozen_string_literal: true

# Backward compatibility alias for Review::Notification
require_relative "review/notification"
ReviewNotification = Review::Notification unless defined?(ReviewNotification)
