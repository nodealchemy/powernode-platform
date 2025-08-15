# frozen_string_literal: true

if Rails.env.test? || Rails.env.development?
  begin
    require "rspec/core/rake_task"

    # Clear existing test tasks to avoid conflicts
    Rake::Task[:test].clear if Rake::Task.task_defined?(:test)

    # Create new test task that runs RSpec
    RSpec::Core::RakeTask.new(:test) do |t|
      t.verbose = false
      t.rspec_opts = [ "--format progress" ]
      t.fail_on_error = true
    end

    # Also provide explicit rspec task
    RSpec::Core::RakeTask.new(:rspec) do |t|
      t.verbose = false
      t.fail_on_error = true
    end

    # Override default Rails test tasks
    namespace :test do
      task units: :test
      task functionals: :test
      task integration: :test
    end

    # Only show configuration message in verbose mode
    puts "✅ Configured rake test to run RSpec tests" if ENV["VERBOSE"]

  rescue LoadError => e
    puts "⚠️  RSpec not available: #{e.message}"
  end
end
