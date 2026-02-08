# frozen_string_literal: true

namespace :parallel do
  desc "Full setup: create parallel test databases, load schema, and seed permissions"
  task setup: :environment do
    Rake::Task["parallel:create"].invoke
    Rake::Task["parallel:prepare"].invoke
    Rake::Task["parallel:seed_permissions"].invoke
  end

  desc "Seed permissions into all parallel test databases"
  task seed_permissions: :environment do
    require Rails.root.join("config", "permissions")

    count = ENV.fetch("PARALLEL_TEST_PROCESSORS") {
      Parallel.processor_count
    }.to_i

    base_config = ActiveRecord::Base.configurations.configs_for(env_name: "test").first.configuration_hash

    count.times do |i|
      env_number = i == 0 ? "" : (i + 1).to_s
      db_name = "powernode_test#{env_number}"

      puts "Seeding permissions in #{db_name}..."
      ActiveRecord::Base.establish_connection(base_config.merge(database: db_name))
      Role.sync_from_config!
    end

    # Restore original connection
    ActiveRecord::Base.establish_connection(base_config)
    puts "Done seeding permissions in all parallel test databases."
  end
end
