# frozen_string_literal: true

puts "Seeding Knowledge Base permissions..."

# Knowledge Base Permissions
kb_permissions = [
  {
    name: 'kb.read',
    description: 'View published knowledge base articles',
    category: 'resource'
  },
  {
    name: 'kb.write',
    description: 'Create and edit knowledge base articles',
    category: 'resource'
  },
  {
    name: 'kb.manage',
    description: 'Full knowledge base management including categories, comments, and analytics',
    category: 'admin'
  },
  {
    name: 'kb.admin',
    description: 'Administrative access to knowledge base system settings',
    category: 'admin'
  }
]

kb_permissions.each do |perm_attrs|
  permission = Permission.find_or_create_by(name: perm_attrs[:name]) do |p|
    p.description = perm_attrs[:description]
    p.category = perm_attrs[:category]
  end
  
  if permission.persisted?
    puts "  ✓ Permission '#{permission.name}' created/found"
  else
    puts "  ✗ Failed to create permission '#{perm_attrs[:name]}': #{permission.errors.full_messages.join(', ')}"
  end
end

# Update existing roles to include KB permissions
puts "\nUpdating roles with Knowledge Base permissions..."

# System Admin should have all KB permissions
system_admin_role = Role.find_by(name: 'system.admin')
if system_admin_role
  kb_permissions.each do |perm_attrs|
    permission = Permission.find_by(name: perm_attrs[:name])
    if permission && !system_admin_role.permissions.include?(permission)
      system_admin_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to system.admin role"
    end
  end
end

# Account Manager should have read and write permissions
account_manager_role = Role.find_by(name: 'account.manager')
if account_manager_role
  %w[kb.read kb.write].each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !account_manager_role.permissions.include?(permission)
      account_manager_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to account.manager role"
    end
  end
end

# Account Member should have read permission
account_member_role = Role.find_by(name: 'account.member')
if account_member_role
  permission = Permission.find_by(name: 'kb.read')
  if permission && !account_member_role.permissions.include?(permission)
    account_member_role.permissions << permission
    puts "  ✓ Added '#{permission.name}' to account.member role"
  end
end

# Create a Content Manager role specifically for KB management
content_manager_role = Role.find_or_create_by(name: 'content.manager') do |role|
  role.display_name = 'Content Manager'
  role.description = 'Manages knowledge base content and documentation'
  role.is_system = false
  role.role_type = 'user'
end

if content_manager_role.persisted?
  puts "  ✓ Role 'content.manager' created/found"
  
  # Add KB permissions to content manager
  %w[kb.read kb.write kb.manage].each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !content_manager_role.permissions.include?(permission)
      content_manager_role.permissions << permission
      puts "    ✓ Added '#{permission.name}' to content.manager role"
    end
  end
else
  puts "  ✗ Failed to create content.manager role: #{content_manager_role.errors.full_messages.join(', ')}"
end

puts "\nKnowledge Base permissions seeding completed!"
puts "\nPermissions summary:"
puts "  • kb.read: View published articles (all users)"
puts "  • kb.write: Create/edit articles (content creators)" 
puts "  • kb.manage: Full content management (content managers)"
puts "  • kb.admin: System administration (system admins only)"
puts "\nRoles with KB access:"
puts "  • system.admin: All permissions"
puts "  • account.manager: Read + Write"  
puts "  • account.member: Read only"
puts "  • content.manager: Read + Write + Manage"