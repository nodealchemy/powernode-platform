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

# HTTP client for direct AI provider calls
require 'httparty'

# Auto-require core files first
require_relative '../app/services/worker_jwt'
require_relative '../app/services/backend_api_client'
require_relative '../app/services/web_auth_api_client'
require_relative '../app/middleware/sidekiq_web_auth'
require_relative '../app/controllers/jobs_controller'

# AI LLM client for direct provider calls (bypassing server proxy)
require_relative '../app/services/ai/llm/client'
require_relative '../app/services/ai/embedding_service'
require_relative '../app/services/credential_resolver'

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

# Load extension worker modules dynamically from extensions/*/extension.json.
# Skip slugs marked disabled in config/extensions_state.json so a disabled
# extension's worker code is never required.
extensions_dir = File.expand_path('../../extensions', __dir__)
disabled_extensions = begin
  state_file = File.expand_path('../../config/extensions_state.json', __dir__)
  if File.exist?(state_file)
    Array(JSON.parse(File.read(state_file))['disabled']).map(&:to_s)
  else
    []
  end
rescue JSON::ParserError, IOError, SystemCallError => e
  warn "[Worker] Failed to read #{state_file}: #{e.message}"
  []
end

if Dir.exist?(extensions_dir)
  Dir.children(extensions_dir).sort.each do |slug|
    next if disabled_extensions.include?(slug)

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

    # Load shared lib (math kernel, markov classes, etc.)
    ext_lib = File.join(extensions_dir, slug, 'lib')
    if Dir.exist?(ext_lib)
      Dir[File.join(ext_lib, '**', '*.rb')].sort.each { |f| require f }
    end

    # Load optional gem dependencies
    deps_file = File.join(ext_worker, 'config', 'gem_dependencies.rb')
    load deps_file if File.exist?(deps_file)

    # Load exceptions first (used by jobs and services)
    Dir[File.join(ext_worker, 'app', 'exceptions', '**', '*.rb')].sort.each { |f| require f }

    # Load services (ordered: concerns → base → rest)
    svc_dir = File.join(ext_worker, 'app', 'services')
    if Dir.exist?(svc_dir)
      Dir[File.join(svc_dir, '**', 'concerns', '*.rb')].sort.each { |f| require f }
      Dir[File.join(svc_dir, '**', 'base.rb')].sort.each { |f| require f }
      Dir[File.join(svc_dir, '**', '*.rb')].sort.each do |f|
        require f unless f.include?('/concerns/') || f.end_with?('/base.rb')
      end
    end

    # Load job concerns before job classes that use them
    concerns = Dir[File.join(ext_worker, 'app', 'jobs', 'concerns', '**', '*.rb')].sort
    concerns.each { |f| require f }

    # Load job classes (excluding already-loaded concerns)
    Dir[File.join(ext_worker, 'app', 'jobs', '**', '*.rb')].sort.each do |f|
      require f unless concerns.include?(f)
    end
  end
end