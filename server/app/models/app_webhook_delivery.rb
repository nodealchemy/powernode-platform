# frozen_string_literal: true

# Backward compatibility alias for Marketplace::WebhookDelivery
require_relative "marketplace/webhook_delivery"
AppWebhookDelivery = Marketplace::WebhookDelivery unless defined?(AppWebhookDelivery)
