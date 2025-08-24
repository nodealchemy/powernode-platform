# frozen_string_literal: true

module RoleHelpers
  def ensure_test_roles_exist
    # Create basic roles if they don't exist
    ['owner', 'admin', 'member', 'manager', 'super_admin', 'billing_admin'].each do |role_name|
      Role.find_or_create_by!(name: role_name) do |role|
        role.display_name = role_name.humanize
        role.role_type = case role_name
                        when 'admin', 'super_admin'
                          'admin'
                        else
                          'user'
                        end
        role.is_system = false
      end
    end
  end
  
  def ensure_dotted_roles_exist
    # Create dotted notation roles
    {
      'account.owner' => { display_name: 'Account Owner', role_type: 'user' },
      'account.manager' => { display_name: 'Account Manager', role_type: 'user' },
      'account.member' => { display_name: 'Account Member', role_type: 'user' },
      'system.admin' => { display_name: 'System Admin', role_type: 'admin' },
      'billing.admin' => { display_name: 'Billing Admin', role_type: 'user' }
    }.each do |role_name, attrs|
      Role.find_or_create_by!(name: role_name) do |role|
        role.display_name = attrs[:display_name]
        role.role_type = attrs[:role_type]
        role.is_system = true
      end
    end
  end
  
  def setup_test_permissions
    # Create basic test permissions
    ['users', 'accounts', 'billing', 'analytics'].each do |resource|
      ['create', 'read', 'update', 'delete', 'manage'].each do |action|
        Permission.find_or_create_by!(resource: resource, action: action) do |p|
          p.name = "#{resource}.#{action}"
          p.category = 'resource'
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include RoleHelpers
end