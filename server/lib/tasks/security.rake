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

  desc "Lift the DDoS IP block on one address. Usage: rails 'security:unblock_ip[<ip>]'"
  task :unblock_ip, [ :ip ] => :environment do |_t, args|
    require "ipaddr"

    raw = args[:ip].to_s.strip
    abort "Usage: rails 'security:unblock_ip[<ip>]'" if raw.empty?

    abort "Give a single address, not a CIDR range: #{raw.inspect}" if raw.include?("/")

    ip = begin
      IPAddr.new(raw).to_s
    rescue IPAddr::Error
      abort "Not an IP address: #{raw.inspect}"
    end

    # IpBlockStore fails open (nil on a Redis outage), which would otherwise
    # read as "was not blocked" at exactly the moment nothing was done.
    abort "Redis is unreachable; the block was NOT lifted for #{ip}" unless ::Security::IpBlockStore.with(&:ping)

    was_blocked = ::Security::IpBlockStore.unblock!(ip)

    # Account is required by AuditLog; the platform's oldest account is the
    # operator's own in core mode. A missing account must not undo the unblock.
    audited = false
    begin
      account = ::Account.order(:created_at).first
      if account
        ::AuditLog.create!(
          account: account, user: nil, action: "ip_block_lifted", source: "system",
          resource_type: "IpBlock", resource_id: account.id, ip_address: ip,
          severity: "medium", risk_level: "medium",
          metadata: { "ip" => ip, "was_blocked" => was_blocked, "via" => "rake security:unblock_ip",
                      "operator" => (ENV["SUDO_USER"].presence || ENV["USER"].presence || "unknown") }
        )
        audited = true
      end
    rescue StandardError => e
      Rails.logger.warn("[DDoS] unblock_ip audit failed for #{ip}: #{e.class}: #{e.message}")
    end
    warn "WARNING: no audit row was written (no account, or the audit insert failed); see the Rails log" unless audited
    Rails.logger.warn("[DDoS] IP block lifted via rake: IP=#{ip} found=#{was_blocked}")

    puts(was_blocked ? "IP block lifted for #{ip}" : "#{ip} was not blocked")
  end
end
