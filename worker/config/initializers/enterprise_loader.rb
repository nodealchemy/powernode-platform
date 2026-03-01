# frozen_string_literal: true

# Load enterprise billing sidekiq schedules when the enterprise submodule is present
# NOTE: Enterprise worker code (jobs, concerns, services) is loaded from boot.rb.
# This initializer only handles sidekiq-scheduler schedule merging, which must
# happen during Sidekiq server startup.
enterprise_worker = File.expand_path("../../../../extensions/enterprise/worker", __dir__)

if Dir.exist?(enterprise_worker)
  billing_schedule = File.join(enterprise_worker, "config", "sidekiq_billing.yml")
  if File.exist?(billing_schedule) && defined?(Sidekiq)
    require "yaml"
    require "erb"
    billing_config = YAML.safe_load(ERB.new(File.read(billing_schedule)).result, permitted_classes: [Symbol])
    if billing_config && billing_config[:schedule]
      Sidekiq.configure_server do |config|
        config.on(:startup) do
          if defined?(SidekiqScheduler::Scheduler)
            existing = Sidekiq.schedule || {}
            Sidekiq.schedule = existing.merge(billing_config[:schedule])
          end
        end
      end
    end
  end
end
