ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

# Load core Ruby extensions
require 'active_support/all'

# Load all application files
$LOAD_PATH.unshift(File.expand_path('../app', __dir__))
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Auto-require core files first
require_relative '../app/services/backend_api_client'
require_relative '../app/middleware/sidekiq_web_auth'
require_relative '../app/controllers/jobs_controller'

# Require module definitions first
require_relative '../app/jobs/analytics'
require_relative '../app/jobs/billing'
require_relative '../app/jobs/reports'
require_relative '../app/jobs/webhooks'

# Auto-require all worker files
Dir[File.expand_path('../app/jobs/**/*.rb', __dir__)].sort.each { |f| require f }