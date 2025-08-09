VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = false

  # Filter sensitive data
  config.filter_sensitive_data('<STRIPE_SECRET_KEY>') { ENV['STRIPE_SECRET_KEY'] }
  config.filter_sensitive_data('<STRIPE_PUBLISHABLE_KEY>') { ENV['STRIPE_PUBLISHABLE_KEY'] }
  config.filter_sensitive_data('<PAYPAL_CLIENT_ID>') { ENV['PAYPAL_CLIENT_ID'] }
  config.filter_sensitive_data('<PAYPAL_CLIENT_SECRET>') { ENV['PAYPAL_CLIENT_SECRET'] }
  config.filter_sensitive_data('<JWT_SECRET>') { ENV['JWT_SECRET'] }
end
