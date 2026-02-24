# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

# Load core Ruby extensions
require 'active_support/all'
require 'action_mailer'
require 'json'

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

# Load extension worker modules dynamically from extensions/*/extension.json
extensions_dir = File.expand_path('../../extensions', __dir__)
if Dir.exist?(extensions_dir)
  Dir.children(extensions_dir).sort.each do |slug|
    manifest_path = File.join(extensions_dir, slug, 'extension.json')
    next unless File.exist?(manifest_path)

    begin
      manifest = JSON.parse(File.read(manifest_path))
    rescue JSON::ParserError => e
      warn "[Worker] Failed to parse #{manifest_path}: #{e.message}"
      next
    end

    next unless manifest.dig('components', 'worker')

    ext_worker = File.join(extensions_dir, slug, 'worker')
    next unless Dir.exist?(ext_worker)

    # Load optional gem dependencies
    deps_file = File.join(ext_worker, 'config', 'gem_dependencies.rb')
    load deps_file if File.exist?(deps_file)

    # Load exceptions first (used by jobs)
    Dir[File.join(ext_worker, 'app', 'exceptions', '**', '*.rb')].sort.each { |f| require f }

    # Load concerns before job classes that use them
    concerns = Dir[File.join(ext_worker, 'app', 'jobs', 'concerns', '**', '*.rb')].sort
    concerns.each { |f| require f }

    # Load job classes (excluding already-loaded concerns)
    Dir[File.join(ext_worker, 'app', 'jobs', '**', '*.rb')].sort.each do |f|
      require f unless concerns.include?(f)
    end

    # Load services
    Dir[File.join(ext_worker, 'app', 'services', '**', '*.rb')].sort.each { |f| require f }
  end
end