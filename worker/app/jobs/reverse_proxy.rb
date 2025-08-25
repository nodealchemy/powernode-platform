# frozen_string_literal: true

# Reverse proxy job module
# Handles asynchronous operations for reverse proxy configuration and management
module ReverseProxy
  # Load all reverse proxy job classes
  Dir[File.join(__dir__, 'reverse_proxy', '*.rb')].each { |file| require file }
end