# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # E8: a webhook URL is often the credential itself — a Slack incoming-webhook
  # URL is the capability to post. Partial match, so this also covers
  # slack_webhook_url, wherever in a request it appears; without it those keys
  # were filtered only while nested under a key containing "secret".
  :webhook_url
]
