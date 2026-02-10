# frozen_string_literal: true

namespace :powernode do
  desc "Interactive setup for first-time Powernode installation"
  task setup: :environment do
    if Account.exists?
      puts "Setup already completed. An account already exists."
      puts "To reset, drop and recreate the database first."
      next
    end

    puts "=" * 60
    puts "  Powernode Self-Hosted Setup"
    puts "=" * 60
    puts ""

    # Ensure permissions and roles are seeded
    unless Permission.exists?
      puts "Syncing permissions and roles..."
      Permission.sync_from_config!
      Role.sync_from_config!
    end

    # Ensure Self-Hosted plan exists
    plan = Plan.find_or_create_by!(name: "Self-Hosted") do |p|
      p.description = "Self-hosted installation with all features enabled"
      p.price_cents = 0
      p.currency = "USD"
      p.billing_interval = "monthly"
      p.trial_period_days = 0
      p.is_public = false
      p.slug = "self-hosted"
      p.features = {
        "community_access" => true, "dashboard_access" => true, "mobile_responsive" => true,
        "email_notifications" => true, "basic_reporting" => true, "standard_support" => true,
        "basic_analytics" => true, "email_support" => true, "advanced_analytics" => true,
        "priority_support" => true, "api_access" => true, "custom_branding" => true,
        "data_export" => true, "team_collaboration" => true, "webhook_integrations" => true,
        "custom_fields" => true, "advanced_filters" => true, "custom_integrations" => true,
        "dedicated_support" => true, "white_label" => true, "sso_integration" => true,
        "advanced_security" => true, "audit_logs" => true, "sla_guarantees" => true,
        "marketplace_publish_enabled" => true, "marketplace_publish_limit" => nil
      }
      p.limits = {
        "max_users" => 1, "max_api_keys" => 100, "max_webhooks" => 100,
        "max_workers" => 100, "max_repositories" => 9999
      }
    end

    # Get admin details from env or prompt
    admin_name = ENV["POWERNODE_ADMIN_NAME"].presence
    admin_email = ENV["POWERNODE_ADMIN_EMAIL"].presence
    admin_password = ENV["POWERNODE_ADMIN_PASSWORD"].presence

    unless admin_email
      print "Admin email: "
      admin_email = $stdin.gets&.strip
    end

    unless admin_name
      print "Admin name: "
      admin_name = $stdin.gets&.strip
    end

    unless admin_password
      print "Admin password (min 8 chars): "
      admin_password = $stdin.gets&.strip
    end

    if admin_email.blank? || admin_password.blank?
      puts "Error: Email and password are required."
      next
    end

    ActiveRecord::Base.transaction do
      account = Account.create!(
        name: admin_name.presence || "Powernode",
        subdomain: "admin"
      )

      user = account.users.create!(
        name: admin_name.presence || "Admin",
        email: admin_email,
        password: admin_password,
        email_verified_at: Time.current
      )

      # Assign super_admin role
      super_admin = Role.find_by(name: "super_admin")
      user.roles << super_admin if super_admin && !user.roles.include?(super_admin)

      # Create active subscription
      account.create_subscription!(
        plan: plan,
        status: "active",
        quantity: 1,
        current_period_start: Time.current,
        current_period_end: 100.years.from_now
      )

      puts ""
      puts "Setup complete!"
      puts "  Account: #{account.name}"
      puts "  Email:   #{user.email}"
      puts "  Plan:    #{plan.name}"
      puts ""
      puts "You can now log in at your Powernode instance."
    end
  end
end
