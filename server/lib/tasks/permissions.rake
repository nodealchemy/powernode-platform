# frozen_string_literal: true

namespace :permissions do
  desc "Verify admin user has proper permissions setup"
  task verify_admin: :environment do
    # Load permissions configuration
    require Rails.root.join('config', 'permissions')
    puts "\n" + "=" * 80
    puts "🔍 PERMISSIONS STRUCTURE AUDIT"
    puts "=" * 80

    # Find admin user
    admin_user = User.find_by(email: 'admin@powernode.org')

    if admin_user.nil?
      puts "❌ Admin user not found (admin@powernode.org)"
      exit 1
    end

    puts "\n✅ Admin User Found:"
    puts "   Email: #{admin_user.email}"
    puts "   ID: #{admin_user.id}"
    puts "   Created: #{admin_user.created_at}"

    # Check roles
    puts "\n📋 Assigned Roles:"
    if admin_user.roles.empty?
      puts "   ❌ No roles assigned!"
      exit 1
    end

    admin_user.roles.each do |role|
      puts "   ✓ #{role.name} (#{role.display_name})"
      puts "     Type: #{role.role_type}"
      puts "     Permissions: #{role.permissions.count}"
      puts "     Has system.admin: #{role.permissions.exists?(name: 'system.admin') ? '✓' : '✗'}"
    end

    # Check for super_admin role
    super_admin_role = admin_user.roles.find_by(name: 'super_admin')
    if super_admin_role.nil?
      puts "\n⚠️  WARNING: Admin user does not have super_admin role!"
    else
      puts "\n✅ Super Admin Role Verified:"
      puts "   Display Name: #{super_admin_role.display_name}"
      puts "   System Role: #{super_admin_role.is_system?}"
      puts "   Immutable: #{super_admin_role.immutable?}"
    end

    # Verify system.admin permission
    has_system_admin = admin_user.roles.joins(:permissions)
                                  .exists?(permissions: { name: 'system.admin' })

    if has_system_admin
      puts "\n✅ System Admin Permission: ACTIVE"
      puts "   This grants programmatic access to ALL permissions"
    else
      puts "\n❌ System Admin Permission: NOT FOUND"
      puts "   Admin user will not have access to all permissions!"
      exit 1
    end

    # Count total permissions in system
    total_permissions = Permission.count
    puts "\n📊 Permission Statistics:"
    puts "   Total Permissions: #{total_permissions}"

    # Group by category
    categories = Permission.pluck(:name).map { |name| name.split('.').first }.uniq
    puts "   Permission Categories: #{categories.count}"
    categories.sort.each do |category|
      count = Permission.where("name LIKE ?", "#{category}.%").count
      puts "     - #{category}: #{count} permissions"
    end

    # Test permission check
    puts "\n🧪 Testing Permission Access:"
    test_permissions = [
      'users.manage',
      'admin.access',
      'billing.manage',
      'system.admin',
      'storage.manage',
      'admin.storage.manage'
    ]

    test_permissions.each do |perm|
      has_perm = admin_user.has_permission?(perm)
      puts "   #{has_perm ? '✓' : '✗'} #{perm}"
    end

    # Verify all roles are properly configured
    puts "\n🔧 Role Configuration Validation:"
    Permissions::ROLES.each do |role_name, config|
      db_role = Role.find_by(name: role_name)
      if db_role.nil?
        puts "   ⚠️  Role '#{role_name}' defined in config but not in database"
        next
      end

      config_perms = config[:permissions] || []
      db_perms = db_role.permissions.pluck(:name)

      if db_role.name == 'super_admin'
        # Super admin should only have system.admin permission
        if db_perms == ['system.admin']
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
    puts "\nSummary:"
    puts "  Admin User: #{admin_user.email}"
    puts "  Super Admin Role: #{super_admin_role ? '✓ Assigned' : '✗ Missing'}"
    puts "  System Admin Permission: #{has_system_admin ? '✓ Active' : '✗ Inactive'}"
    puts "  Total Permissions: #{total_permissions}"
    puts "  Permission Categories: #{categories.count}"
    puts "\n"
  end

  desc "List all permissions in the system"
  task list: :environment do
    puts "\n📋 All System Permissions:"
    puts "=" * 80

    permissions = Permission.order(:name)
    current_category = nil

    permissions.each do |perm|
      category = perm.name.split('.').first

      if category != current_category
        puts "\n#{category.upcase}:"
        current_category = category
      end

      puts "  • #{perm.name}"
      puts "    #{perm.description}" if perm.description.present?
    end

    puts "\n" + "=" * 80
    puts "Total: #{permissions.count} permissions"
    puts "=" * 80
  end

  desc "Show permission distribution across roles"
  task distribution: :environment do
    puts "\n📊 Permission Distribution Across Roles:"
    puts "=" * 80

    roles = Role.includes(:permissions).order(:role_type, :name)

    roles.group_by(&:role_type).each do |role_type, type_roles|
      puts "\n#{role_type.upcase} ROLES:"
      type_roles.each do |role|
        has_system_admin = role.permissions.exists?(name: 'system.admin')
        perm_count = role.permissions.count

        puts "\n  #{role.display_name} (#{role.name})"
        puts "    Permissions: #{perm_count}"
        puts "    System Role: #{role.is_system?}"
        puts "    Immutable: #{role.immutable?}"

        if has_system_admin
          puts "    🔑 Has system.admin (grants all permissions)"
        elsif perm_count > 0
          puts "    Permissions:"
          role.permissions.pluck(:name).sort.each do |perm|
            puts "      • #{perm}"
          end
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

    # Check for orphaned role_permissions
    orphaned_role_perms = RolePermission.left_joins(:role, :permission)
                                        .where(roles: { id: nil })
                                        .or(RolePermission.left_joins(:role, :permission)
                                        .where(permissions: { id: nil }))
                                        .count

    if orphaned_role_perms > 0
      issues << "Found #{orphaned_role_perms} orphaned role_permission records"
    end

    # Check for orphaned user_roles
    orphaned_user_roles = UserRole.left_joins(:user, :role)
                                   .where(users: { id: nil })
                                   .or(UserRole.left_joins(:user, :role)
                                   .where(roles: { id: nil }))
                                   .count

    if orphaned_user_roles > 0
      issues << "Found #{orphaned_user_roles} orphaned user_role records"
    end

    # Check for permissions not in config
    config_perms = Permissions::ALL_PERMISSIONS.keys
    db_perms = Permission.pluck(:name)
    orphaned_perms = db_perms - config_perms

    if orphaned_perms.any?
      issues << "Found #{orphaned_perms.count} permissions in database not in config: #{orphaned_perms.join(', ')}"
    end

    # Check for roles not in config
    config_roles = Permissions::ROLES.keys.map(&:to_s)
    db_roles = Role.pluck(:name)
    orphaned_roles = db_roles - config_roles

    if orphaned_roles.any?
      issues << "Found #{orphaned_roles.count} roles in database not in config: #{orphaned_roles.join(', ')}"
    end

    # Check for users with no roles
    users_without_roles = User.left_joins(:user_roles).where(user_roles: { id: nil }).count
    if users_without_roles > 0
      issues << "Found #{users_without_roles} users with no roles assigned"
    end

    # Report results
    if issues.empty?
      puts "\n✅ No integrity issues found!"
      puts "\n   Permissions: #{Permission.count}"
      puts "   Roles: #{Role.count}"
      puts "   Users: #{User.count}"
      puts "   User Roles: #{UserRole.count}"
      puts "   Role Permissions: #{RolePermission.count}"
    else
      puts "\n⚠️  Found #{issues.count} integrity issues:\n"
      issues.each_with_index do |issue, index|
        puts "   #{index + 1}. #{issue}"
      end
    end

    puts "\n" + "=" * 80
    puts "Integrity Check Complete"
    puts "=" * 80
  end
end
