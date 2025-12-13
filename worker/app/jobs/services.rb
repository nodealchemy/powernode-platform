# frozen_string_literal: true

# Services job module
# Handles asynchronous operations for services configuration and management
module Services
  # Load all services job classes
  Dir[File.join(__dir__, 'services', '*.rb')].each { |file| require file }
end