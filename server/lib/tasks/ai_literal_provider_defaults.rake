# frozen_string_literal: true

namespace :ai do
  desc "E3b: clear shipped literal provider default_models that are absent from the synced catalog. " \
       "Prints the count and a sample; acts only with CONFIRM=<current count>."
  task clear_literal_provider_defaults: :environment do
    outcome = Ai::Providers::LiteralDefaultCleanup.operator_run(confirm: ENV["CONFIRM"])
    exit(1) if outcome.status == :mismatch
  end
end
