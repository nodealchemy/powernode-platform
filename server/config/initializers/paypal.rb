# PayPal configuration
PayPal::SDK.configure(
  mode: Rails.env.production? ? "live" : "sandbox",
  client_id: ENV["PAYPAL_CLIENT_ID"],
  client_secret: ENV["PAYPAL_CLIENT_SECRET"],
  ssl_options: {}
)

Rails.application.configure do
  config.paypal = {
    client_id: ENV["PAYPAL_CLIENT_ID"],
    client_secret: ENV["PAYPAL_CLIENT_SECRET"],
    mode: Rails.env.production? ? "live" : "sandbox",
    webhook_id: ENV["PAYPAL_WEBHOOK_ID"]
  }
end
