namespace :security do
  desc "Run security audit with Brakeman"
  task :brakeman do
    puts "Running Brakeman security scan..."
    system("bundle exec brakeman -q --no-pager")
  end

  desc "Run bundle audit for vulnerable gems"
  task :bundle_audit do
    puts "Running bundle audit..."
    system("bundle exec bundle-audit check --update")
  end

  desc "Run all security checks"
  task all: [ :brakeman, :bundle_audit ] do
    puts "All security checks completed!"
  end

  desc "Generate security report"
  task :report do
    puts "Generating security report..."

    # Create reports directory
    FileUtils.mkdir_p("tmp/security_reports")

    # Run Brakeman with JSON output
    system("bundle exec brakeman -o tmp/security_reports/brakeman.json")

    # Run bundle audit with JSON output
    system("bundle exec bundle-audit check --format json --output tmp/security_reports/bundle-audit.json 2>/dev/null || true")

    puts "Security reports generated in tmp/security_reports/"
  end
end
