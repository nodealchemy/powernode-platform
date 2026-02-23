# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

# Load core Ruby extensions
require 'active_support/all'
require 'action_mailer'

# Configure Time.zone (required for jobs using Time.zone.parse)
Time.zone = 'UTC'

# Load all application files
$LOAD_PATH.unshift(File.expand_path('../app', __dir__))
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Auto-require core files first
require_relative '../app/services/backend_api_client'
require_relative '../app/services/web_auth_api_client'
require_relative '../app/middleware/sidekiq_web_auth'
require_relative '../app/controllers/jobs_controller'

# Auto-require external service integrations
require_relative '../app/services/firebase_service'
require_relative '../app/services/twilio_service'

# Require base job first
require_relative '../app/jobs/base_job'

# Load all concerns first (BEFORE job classes that use them)
services_concerns = Dir[File.expand_path('../app/services/concerns/*.rb', __dir__)].sort
jobs_concerns = Dir[File.expand_path('../app/jobs/concerns/**/*.rb', __dir__)].sort
all_concerns = (services_concerns + jobs_concerns).sort
all_concerns.each { |f| require f }

# Require module definitions BEFORE the job classes that use them
require_relative '../app/jobs/analytics'
require_relative '../app/jobs/billing'
require_relative '../app/jobs/reports'
require_relative '../app/jobs/webhooks'

# Auto-require all worker files EXCLUDING already loaded files
job_files = Dir[File.expand_path('../app/jobs/**/*.rb', __dir__)].sort
excluded_files = [
  File.expand_path('../app/jobs/base_job.rb', __dir__),
  File.expand_path('../app/jobs/analytics.rb', __dir__),
  File.expand_path('../app/jobs/billing.rb', __dir__),
  File.expand_path('../app/jobs/reports.rb', __dir__),
  File.expand_path('../app/jobs/webhooks.rb', __dir__)
]

job_files.each do |f|
  require f unless excluded_files.include?(f)
end

# Load enterprise worker extensions when the enterprise submodule is present
enterprise_worker = File.expand_path('../../../extensions/enterprise/worker', __dir__)

if Dir.exist?(enterprise_worker)
  # Conditionally require payment provider gems (only needed for enterprise billing)
  begin
    require 'stripe'
  rescue LoadError
    # Stripe gem not available — billing reconciliation will be limited
  end

  begin
    require 'paypal-sdk-rest'
  rescue LoadError
    # PayPal gem not available — PayPal reconciliation will be limited
  end

  # Load enterprise exceptions first (used by enterprise jobs)
  enterprise_exceptions = File.join(enterprise_worker, 'app', 'exceptions', 'billing_exceptions.rb')
  require enterprise_exceptions if File.exist?(enterprise_exceptions)

  # Load enterprise concerns (BEFORE enterprise job classes)
  enterprise_concerns = Dir[File.join(enterprise_worker, 'app', 'jobs', 'concerns', '**', '*.rb')].sort
  enterprise_concerns.each { |f| require f }

  # Load enterprise jobs
  enterprise_jobs = Dir[File.join(enterprise_worker, 'app', 'jobs', '**', '*.rb')].sort
  enterprise_jobs.each do |f|
    next if enterprise_concerns.include?(f) # Skip already-loaded concerns
    require f
  end

  # Load enterprise services
  enterprise_services = Dir[File.join(enterprise_worker, 'app', 'services', '**', '*.rb')].sort
  enterprise_services.each { |f| require f }
end