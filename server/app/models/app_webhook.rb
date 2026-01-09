# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Webhook
require_relative "marketplace/webhook"
AppWebhook = Marketplace::Webhook unless defined?(AppWebhook)
