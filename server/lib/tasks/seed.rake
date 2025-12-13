namespace :db do
  namespace :seed do
    desc "Load comprehensive test data (for development/test environments only)"
    task test_data: :environment do
      if Rails.env.production?
        puts "❌ Cannot load test data in production environment!"
        exit 1
      end

      test_data_file = Rails.root.join("db", "seeds", "test_data.rb")

      if File.exist?(test_data_file)
        puts "📦 Loading test data for #{Rails.env} environment..."
        load test_data_file
        puts "✅ Test data loaded successfully!"
      else
        puts "❌ Test data file not found at db/seeds/test_data.rb"
        exit 1
      end
    end

    desc "Reset database and load all seeds including test data (development/test only)"
    task reset_with_test: :environment do
      if Rails.env.production?
        puts "❌ Cannot run reset_with_test in production environment!"
        exit 1
      end

      puts "⚠️  This will DELETE all data and reload seeds!"
      print "Are you sure? (y/N): "

      input = STDIN.gets.chomp
      unless input.downcase == "y"
        puts "Cancelled."
        exit 0
      end

      puts "\n🔄 Resetting database..."
      Rake::Task["db:drop"].invoke
      Rake::Task["db:create"].invoke
      Rake::Task["db:migrate"].invoke
      Rake::Task["db:seed"].invoke

      puts "\n✨ Database reset and seeded successfully!"
    end

    desc "Load minimal production seeds only (no test data)"
    task minimal: :environment do
      # Temporarily set environment to production to skip test data loading
      original_env = Rails.env
      Rails.env = "production"

      begin
        puts "🌱 Loading minimal seed data only..."
        load Rails.root.join("db", "seeds.rb")
        puts "✅ Minimal seed data loaded successfully!"
      ensure
        Rails.env = original_env
      end
    end
  end
end
