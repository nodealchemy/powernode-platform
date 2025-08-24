# frozen_string_literal: true

namespace :roles do
  desc "Standardize all role names to match Permissions module configuration"
  task standardize: :environment do
    require_relative '../../config/permissions'
    
    puts "Starting role standardization..."
    
    # Mapping of potential old role names to standardized names
    role_mappings = {
      # Standard user roles
      'account.owner' => 'owner',
      'account_owner' => 'owner',
      'account.member' => 'member',
      'account_member' => 'member',
      'account.manager' => 'manager',
      'account_manager' => 'manager',
      
      # Admin roles
      'system.admin' => 'admin',
      'system_admin' => 'admin',
      'platform.admin' => 'admin',
      'super.admin' => 'super_admin',
      'superadmin' => 'super_admin',
      
      # Billing roles
      'billing.admin' => 'billing_admin',
      'billing_administrator' => 'billing_admin',
      'billing.manager' => 'billing_admin',
      
      # Worker roles
      'worker' => 'system_worker',
      'task.worker' => 'task_worker',
      'background_worker' => 'system_worker'
    }
    
    # First, ensure all standard roles exist
    puts "\n1. Creating/updating standard roles from Permissions module..."
    Permissions::ROLES.each do |name, config|
      role = Role.find_or_create_by!(name: name) do |r|
        r.display_name = config[:display_name]
        r.description = config[:description]
        r.role_type = config[:role_type]
        r.is_system = config[:role_type] == 'system'
      end
      
      # Update attributes if they've changed
      role.update!(
        display_name: config[:display_name],
        description: config[:description],
        role_type: config[:role_type],
        is_system: config[:role_type] == 'system'
      )
      
      # Sync permissions
      role.sync_permissions!(config[:permissions])
      
      puts "  ✓ Created/updated role: #{name} (#{config[:display_name]})"
    end
    
    # Update non-standard role names
    puts "\n2. Standardizing non-standard role names..."
    role_mappings.each do |old_name, new_name|
      old_role = Role.find_by(name: old_name)
      next unless old_role
      
      new_role = Role.find_by(name: new_name)
      
      if new_role
        # Migrate users from old role to new role
        old_role.user_roles.each do |user_role|
          unless new_role.users.include?(user_role.user)
            UserRole.create!(
              user: user_role.user,
              role: new_role,
              granted_by: user_role.granted_by,
              granted_at: user_role.granted_at || user_role.created_at
            )
            puts "  → Migrated user #{user_role.user.email} from #{old_name} to #{new_name}"
          end
        end
        
        # Migrate workers from old role to new role
        old_role.worker_roles.each do |worker_role|
          unless new_role.workers.include?(worker_role.worker)
            WorkerRole.create!(
              worker: worker_role.worker,
              role: new_role
            )
            puts "  → Migrated worker #{worker_role.worker.name} from #{old_name} to #{new_name}"
          end
        end
        
        # Delete the old role
        old_role.destroy!
        puts "  ✓ Deleted old role: #{old_name}"
      else
        # Just rename the role
        old_role.update!(name: new_name)
        puts "  ✓ Renamed role: #{old_name} → #{new_name}"
      end
    end
    
    # Clean up any roles not in the standard list
    puts "\n3. Checking for non-standard roles..."
    standard_role_names = Permissions::ROLES.keys
    Role.where.not(name: standard_role_names).each do |role|
      if role.users.any? || role.workers.any?
        puts "  ⚠ Warning: Role '#{role.name}' has #{role.users.count} users and #{role.workers.count} workers - manual review needed"
      else
        role.destroy!
        puts "  ✓ Deleted unused role: #{role.name}"
      end
    end
    
    # Verify final state
    puts "\n4. Final role configuration:"
    Role.order(:role_type, :name).each do |role|
      user_count = role.users.count
      worker_count = role.workers.count
      permission_count = role.permissions.count
      
      puts "  • #{role.name} (#{role.display_name})"
      puts "    Type: #{role.role_type}, Users: #{user_count}, Workers: #{worker_count}, Permissions: #{permission_count}"
    end
    
    puts "\n✅ Role standardization complete!"
  end
  
  desc "Display current role configuration"
  task status: :environment do
    require_relative '../../config/permissions'
    
    puts "\nCurrent Role Configuration:"
    puts "=" * 50
    
    # Show database roles
    puts "\nDatabase Roles:"
    Role.order(:role_type, :name).each do |role|
      puts "  #{role.name.ljust(20)} - #{role.display_name.ljust(25)} (#{role.role_type})"
      puts "    Users: #{role.users.count}, Workers: #{role.workers.count}, Permissions: #{role.permissions.count}"
    end
    
    # Show configured roles
    puts "\nConfigured Roles (from Permissions module):"
    Permissions::ROLES.each do |name, config|
      puts "  #{name.ljust(20)} - #{config[:display_name].ljust(25)} (#{config[:role_type]})"
      puts "    Permissions: #{config[:permissions].count}"
    end
    
    # Show discrepancies
    puts "\nDiscrepancies:"
    db_role_names = Role.pluck(:name).to_set
    config_role_names = Permissions::ROLES.keys.map(&:to_s).to_set
    
    missing_in_db = config_role_names - db_role_names
    extra_in_db = db_role_names - config_role_names
    
    if missing_in_db.any?
      puts "  Roles in config but not in database:"
      missing_in_db.each { |name| puts "    - #{name}" }
    end
    
    if extra_in_db.any?
      puts "  Roles in database but not in config:"
      extra_in_db.each { |name| puts "    - #{name}" }
    end
    
    if missing_in_db.empty? && extra_in_db.empty?
      puts "  ✓ No discrepancies found"
    end
  end
end