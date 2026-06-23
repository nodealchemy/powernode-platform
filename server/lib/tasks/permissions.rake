# frozen_string_literal: true

namespace :permissions do
  desc "Verify admin user has proper permissions setup"
  task verify_admin: :environment do
    puts "\n" + "=" * 80
    puts "🔍 PERMISSIONS STRUCTURE AUDIT"
    puts "=" * 80

    admin_user = User.find_by(email: "admin@powernode.org")
    if admin_user.nil?
      puts "❌ Admin user not found (admin@powernode.org)"
      exit 1
    end

    puts "\n✅ Admin User Found:"
    puts "   Email: #{admin_user.email}"
    puts "   ID: #{admin_user.id}"

    puts "\n📋 Assigned Roles:"
    if admin_user.roles.empty?
      puts "   ❌ No roles assigned!"
      exit 1
    end

    admin_user.roles.each do |role|
      puts "   ✓ #{role.name} (#{role.display_name})"
      puts "     Type: #{role.role_type}"
      puts "     Permissions: #{role.role_permissions.count}"
      puts "     Has system.admin: #{role.has_permission?('system.admin') ? '✓' : '✗'}"
    end

    super_admin_role = admin_user.roles.find_by(name: "super_admin")
    if super_admin_role.nil?
      puts "\n⚠️  WARNING: Admin user does not have super_admin role!"
    else
      puts "\n✅ Super Admin Role Verified (system: #{super_admin_role.is_system?}, immutable: #{super_admin_role.immutable?})"
    end

    has_system_admin = admin_user.has_permission?("system.admin")
    if has_system_admin
      puts "\n✅ System Admin Permission: ACTIVE (grants programmatic access to ALL permissions)"
    else
      puts "\n❌ System Admin Permission: NOT FOUND"
      exit 1
    end

    puts "\n📊 Permission Statistics:"
    puts "   Total Permissions (catalog): #{Permissions.all_permissions.size}"
    categories = Permissions.all_permissions.keys.map { |name| name.split(".").first }.uniq
    puts "   Permission Categories: #{categories.count}"
    categories.sort.each do |category|
      count = Permissions.all_permissions.keys.count { |n| n.start_with?("#{category}.") }
      puts "     - #{category}: #{count} permissions"
    end

    puts "\n🧪 Testing Permission Access:"
    %w[users.manage admin.access billing.manage system.admin storage.manage admin.storage.manage].each do |perm|
      puts "   #{admin_user.has_permission?(perm) ? '✓' : '✗'} #{perm}"
    end

    puts "\n🔧 Role Configuration Validation (global roles vs catalog):"
    Permissions.all_roles.each do |role_name, _config|
      db_role = Role.find_by(name: role_name.to_s, account_id: nil)
      if db_role.nil?
        puts "   ⚠️  Role '#{role_name}' defined in config but not in database"
        next
      end

      config_perms = Permissions.permissions_for_role(role_name.to_s)
      db_perms = db_role.role_permissions.pluck(:permission_name)

      if db_role.name == "super_admin"
        if db_perms == [ "system.admin" ]
          puts "   ✓ #{role_name}: Correctly configured with system.admin"
        else
          puts "   ⚠️  #{role_name}: Has #{db_perms.count} permissions (should have only system.admin)"
        end
      else
        missing = config_perms - db_perms
        extra = db_perms - config_perms
        if missing.empty? && extra.empty?
          puts "   ✓ #{role_name}: #{db_perms.count} permissions (in sync)"
        else
          puts "   ⚠️  #{role_name}: Out of sync"
          puts "       Missing: #{missing.join(', ')}" if missing.any?
          puts "       Extra: #{extra.join(', ')}" if extra.any?
        end
      end
    end

    puts "\n" + "=" * 80
    puts "✅ AUDIT COMPLETE"
    puts "=" * 80
  end

  desc "List all permissions in the system (the code-defined catalog)"
  task list: :environment do
    puts "\n📋 All System Permissions:"
    puts "=" * 80

    current_category = nil
    Permissions.all_permissions.keys.sort.each do |name|
      category = name.split(".").first
      if category != current_category
        puts "\n#{category.upcase}:"
        current_category = category
      end
      puts "  • #{name}"
      desc = Permissions.permission_description(name)
      puts "    #{desc}" if desc.present?
    end

    puts "\n" + "=" * 80
    puts "Total: #{Permissions.all_permissions.size} permissions"
    puts "=" * 80
  end

  desc "Show permission distribution across roles"
  task distribution: :environment do
    puts "\n📊 Permission Distribution Across Roles:"
    puts "=" * 80

    roles = Role.order(:role_type, :name)
    roles.group_by(&:role_type).each do |role_type, type_roles|
      puts "\n#{role_type.to_s.upcase} ROLES:"
      type_roles.each do |role|
        names = role.role_permissions.pluck(:permission_name)
        scope = role.account_id ? "[account #{role.account_id}]" : "[global]"

        puts "\n  #{role.display_name} (#{role.name}) #{scope}"
        puts "    Permissions: #{names.size}"
        puts "    System Role: #{role.is_system?} | Immutable: #{role.immutable?}"

        if names.include?("system.admin")
          puts "    🔑 Has system.admin (grants all permissions)"
        elsif names.any?
          puts "    Permissions:"
          names.sort.each { |perm| puts "      • #{perm}" }
        else
          puts "    ⚠️  No permissions assigned"
        end
      end
    end

    puts "\n" + "=" * 80
    puts "Total Roles: #{roles.count}"
    puts "=" * 80
  end

  desc "Verify permission system integrity"
  task verify: :environment do
    puts "\n🔍 Verifying Permission System Integrity:"
    puts "=" * 80

    issues = []
    catalog = Permissions.all_permissions.keys

    # Orphaned role_permissions: role missing, or grant name not in the catalog
    orphaned_missing_role = RolePermission.left_joins(:role).where(roles: { id: nil }).count
    issues << "Found #{orphaned_missing_role} role_permission records with a missing role" if orphaned_missing_role > 0

    unknown_grants = RolePermission.distinct.pluck(:permission_name).reject { |n| catalog.include?(n) }
    issues << "Found #{unknown_grants.count} grants whose permission is not in the catalog: #{unknown_grants.join(', ')}" if unknown_grants.any?

    # Orphaned user_roles
    orphaned_user_roles = UserRole.left_joins(:user, :role)
                                   .where(users: { id: nil })
                                   .or(UserRole.left_joins(:user, :role).where(roles: { id: nil }))
                                   .count
    issues << "Found #{orphaned_user_roles} orphaned user_role records" if orphaned_user_roles > 0

    # GLOBAL roles not in config (account-scoped custom roles are expected, not flagged)
    # all_roles = core + enabled-extension roles, so extension roles aren't orphans.
    orphaned_roles = Role.global.pluck(:name) - Permissions.all_roles.keys.map(&:to_s)
    issues << "Found #{orphaned_roles.count} GLOBAL roles not in config: #{orphaned_roles.join(', ')}" if orphaned_roles.any?

    # Users with no roles
    users_without_roles = User.left_joins(:user_roles).where(user_roles: { id: nil }).count
    issues << "Found #{users_without_roles} users with no roles assigned" if users_without_roles > 0

    if issues.empty?
      puts "\n✅ No integrity issues found!"
      puts "\n   Permissions (catalog): #{Permissions.all_permissions.size}"
      puts "   Roles: #{Role.count} (#{Role.global.count} global, #{Role.account_scoped.count} account-scoped)"
      puts "   Users: #{User.count} | User Roles: #{UserRole.count} | Role Permissions: #{RolePermission.count}"
    else
      puts "\n⚠️  Found #{issues.count} integrity issues:\n"
      issues.each_with_index { |issue, i| puts "   #{i + 1}. #{issue}" }
    end

    puts "\n" + "=" * 80
    puts "Integrity Check Complete"
    puts "=" * 80
  end
end
