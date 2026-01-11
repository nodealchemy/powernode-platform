# frozen_string_literal: true

require_relative "../../config/permissions"

namespace :marketplace do
  desc "Setup marketplace permissions and roles"
  task setup: :environment do
    puts "Setting up marketplace permissions and roles..."

    # Create or update the developer role
    developer_role = Role.find_or_create_by(name: "developer") do |role|
      role.display_name = "App Developer"
      role.description = "App developer with marketplace publishing capabilities"
      role.role_type = "user"
    end

    # Assign permissions to developer role
    developer_permissions = [
      "user.read", "user.edit_self",
      "team.read",
      "billing.read", "billing.update",
      "plans.read",
      "page.read",
      "analytics.read", "analytics.export",
      "report.read", "report.generate",
      "api.read", "api.write", "api.manage_keys",
      "webhook.read", "webhook.create", "webhook.update",
      "invoice.read", "invoice.download",
      "audit.read",
      # Full marketplace permissions
      "app.read", "app.create", "app.update", "app.delete", "app.publish",
      "app.manage_features", "app.manage_plans", "app.read_analytics",
      "listing.read", "listing.create", "listing.update", "listing.delete",
      "subscription.read", "subscription.create", "subscription.manage",
      "subscription.cancel", "subscription.upgrade", "subscription.read_usage",
      "review.read", "review.create", "review.update", "review.delete", "review.moderate"
    ]

    developer_permissions.each do |permission_name|
      permission = Permission.find_or_create_by(name: permission_name) do |p|
        p.description = Permissions::ALL_PERMISSIONS[permission_name] || "#{permission_name.humanize}"
      end

      RolePermission.find_or_create_by(
        role_id: developer_role.id,
        permission_id: permission.id
      )
    end

    # Update existing roles with marketplace permissions
    member_role = Role.find_by(name: "member")
    if member_role
      marketplace_member_permissions = [
        "app.read",
        "listing.read",
        "subscription.read", "subscription.create", "subscription.manage", "subscription.cancel",
        "subscription.read_usage",
        "review.read"
      ]

      marketplace_member_permissions.each do |permission_name|
        permission = Permission.find_or_create_by(name: permission_name) do |p|
          p.description = Permissions::ALL_PERMISSIONS[permission_name] || "#{permission_name.humanize}"
        end

        RolePermission.find_or_create_by(
          role_id: member_role.id,
          permission_id: permission.id
        )
      end
      puts "Updated member role with marketplace permissions"
    end

    manager_role = Role.find_by(name: "manager")
    if manager_role
      marketplace_manager_permissions = [
        "app.read", "app.create", "app.update", "app.delete", "app.publish",
        "app.manage_features", "app.manage_plans", "app.read_analytics",
        "listing.read", "listing.create", "listing.update", "listing.delete",
        "subscription.read", "subscription.create", "subscription.manage",
        "subscription.cancel", "subscription.upgrade", "subscription.read_usage",
        "review.read", "review.create", "review.update", "review.delete", "review.moderate"
      ]

      marketplace_manager_permissions.each do |permission_name|
        permission = Permission.find_or_create_by(name: permission_name) do |p|
          p.description = Permissions::ALL_PERMISSIONS[permission_name] || "#{permission_name.humanize}"
        end

        RolePermission.find_or_create_by(
          role_id: manager_role.id,
          permission_id: permission.id
        )
      end
      puts "Updated manager role with marketplace permissions"
    end

    # Ensure admin roles have marketplace admin permissions
    admin_role = Role.find_by(name: "admin")
    if admin_role
      admin_marketplace_permissions = [
        "admin.marketplace.read", "admin.marketplace.manage", "admin.marketplace.export",
        "admin.app.read", "admin.app.update", "admin.app.delete", "admin.app.approve", "admin.app.suspend",
        "admin.listing.read", "admin.listing.update", "admin.listing.delete", "admin.listing.approve", "admin.listing.feature",
        "admin.review.read", "admin.review.moderate", "admin.review.delete",
        "admin.subscription.read", "admin.subscription.manage"
      ]

      admin_marketplace_permissions.each do |permission_name|
        permission = Permission.find_or_create_by(name: permission_name) do |p|
          p.description = Permissions::ALL_PERMISSIONS[permission_name] || "#{permission_name.humanize}"
        end

        RolePermission.find_or_create_by(
          role_id: admin_role.id,
          permission_id: permission.id
        )
      end
      puts "Updated admin role with marketplace admin permissions"
    end

    puts "Marketplace permissions and roles setup complete!"
    puts "Created/updated roles:"
    puts "- developer: App developer with marketplace publishing capabilities"
    puts "- member: Basic user with marketplace browsing and subscription management"
    puts "- manager: Manager with full app creation and management"
    puts "- admin: Administrator with marketplace administration capabilities"
  end

  desc "List marketplace permissions"
  task list_permissions: :environment do
    puts "Marketplace Resource Permissions:"
    Permissions::RESOURCE_PERMISSIONS.select { |k, _| k.start_with?("app.", "subscription.", "review.", "listing.") }.each do |name, desc|
      puts "  #{name}: #{desc}"
    end

    puts "\nMarketplace Admin Permissions:"
    Permissions::ADMIN_PERMISSIONS.select { |k, _| k.start_with?("admin.marketplace.", "admin.app.", "admin.listing.", "admin.review.", "admin.subscription.") }.each do |name, desc|
      puts "  #{name}: #{desc}"
    end
  end

  desc "Validate marketplace permissions"
  task validate: :environment do
    puts "Validating marketplace permissions configuration..."

    # Check if all marketplace permissions are defined
    marketplace_perms = [
      "app.read", "app.create", "app.update", "app.delete", "app.publish",
      "subscription.read", "subscription.create", "subscription.manage",
      "listing.read", "listing.create", "listing.update",
      "review.read", "review.create", "review.moderate",
      "admin.marketplace.read", "admin.app.approve", "admin.listing.feature"
    ]

    missing_permissions = marketplace_perms.reject { |p| Permissions.permission_exists?(p) }

    if missing_permissions.any?
      puts "❌ Missing permissions:"
      missing_permissions.each { |p| puts "  - #{p}" }
    else
      puts "✅ All marketplace permissions are defined"
    end

    # Check role assignments
    %w[member manager developer admin].each do |role_name|
      role = Role.find_by(name: role_name)
      if role
        marketplace_perms_for_role = role.permissions.where(name: marketplace_perms).count
        puts "✅ Role '#{role_name}' has #{marketplace_perms_for_role} marketplace permissions"
      else
        puts "❌ Role '#{role_name}' not found"
      end
    end
  end
end
