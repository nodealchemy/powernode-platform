# frozen_string_literal: true

# PayPal configuration — only when enterprise extension provides the gem
if defined?(PayPal::SDK)
  PayPal::SDK.configure(
    mode: Rails.env.production? ? "live" : "sandbox",
    client_id: ENV["PAYPAL_CLIENT_ID"],
    client_secret: ENV["PAYPAL_CLIENT_SECRET"],
    ssl_options: {}
  )
end

Rails.application.configure do
  config.paypal = {
    client_id: ENV["PAYPAL_CLIENT_ID"],
    client_secret: ENV["PAYPAL_CLIENT_SECRET"],
    mode: Rails.env.production? ? "live" : "sandbox",
    webhook_id: ENV["PAYPAL_WEBHOOK_ID"]
  }
end
