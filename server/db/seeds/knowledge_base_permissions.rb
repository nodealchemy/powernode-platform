# frozen_string_literal: true

puts "Seeding Knowledge Base permissions..."

# NOTE: Knowledge Base permissions are now integrated into the main permissions.rb system
# This seed file ensures proper role assignments for KB functionality

# Update existing roles to include KB permissions
puts "\nUpdating roles with Knowledge Base permissions..."

# System Admin should have all KB permissions
system_admin_role = Role.find_by(name: 'super_admin')
if system_admin_role
  puts "  ✓ Super admin role found - has all permissions programmatically"
else
  puts "  ⚠ Super admin role not found"
end

# Admin should have admin KB permissions
admin_role = Role.find_by(name: 'admin') 
if admin_role
  kb_admin_permissions = %w[admin.kb.read admin.kb.manage admin.kb.moderate admin.kb.analytics admin.kb.settings]
  kb_admin_permissions.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !admin_role.permissions.include?(permission)
      admin_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to admin role"
    elsif !permission
      puts "  ⚠ Permission '#{perm_name}' not found in system"
    end
  end
end

# Owner should have content management permissions
owner_role = Role.find_by(name: 'owner')
if owner_role
  kb_owner_permissions = %w[kb.read kb.create kb.edit kb.publish kb.manage_categories admin.kb.read admin.kb.manage admin.kb.analytics]
  kb_owner_permissions.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !owner_role.permissions.include?(permission)
      owner_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to owner role"
    elsif !permission
      puts "  ⚠ Permission '#{perm_name}' not found in system"
    end
  end
end

# Manager should have content creation permissions
manager_role = Role.find_by(name: 'manager')
if manager_role
  kb_manager_permissions = %w[kb.read kb.create kb.edit kb.publish kb.manage_categories]
  kb_manager_permissions.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !manager_role.permissions.include?(permission)
      manager_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to manager role"
    elsif !permission
      puts "  ⚠ Permission '#{perm_name}' not found in system"
    end
  end
end

# Content Manager should have full content permissions
content_manager_role = Role.find_by(name: 'content_manager')
if content_manager_role
  kb_content_permissions = %w[kb.read kb.create kb.edit kb.delete kb.publish kb.manage_categories kb.moderate_comments]
  kb_content_permissions.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !content_manager_role.permissions.include?(permission)
      content_manager_role.permissions << permission
      puts "  ✓ Added '#{permission.name}' to content_manager role"
    elsif !permission
      puts "  ⚠ Permission '#{perm_name}' not found in system"
    end
  end
else
  puts "  ⚠ Content manager role not found - will be created from permissions.rb"
end

# Member should have read permission
member_role = Role.find_by(name: 'member')
if member_role
  permission = Permission.find_by(name: 'kb.read')
  if permission && !member_role.permissions.include?(permission)
    member_role.permissions << permission
    puts "  ✓ Added '#{permission.name}' to member role"
  elsif !permission
    puts "  ⚠ Permission 'kb.read' not found in system"
  end
end

puts "\nKnowledge Base permissions seeding completed!"
puts "\nPermission Summary:"
puts "  📚 Resource Permissions:"
puts "    • kb.read - View published articles"
puts "    • kb.create - Create new articles"
puts "    • kb.edit - Edit existing articles"
puts "    • kb.delete - Delete articles"
puts "    • kb.publish - Publish articles"
puts "    • kb.manage_categories - Manage categories"
puts "    • kb.moderate_comments - Moderate comments"
puts ""
puts "  🛠️ Admin Permissions:"
puts "    • admin.kb.read - View all content"
puts "    • admin.kb.manage - Manage system"
puts "    • admin.kb.moderate - Moderate all content"
puts "    • admin.kb.analytics - Access analytics"
puts "    • admin.kb.settings - Configure settings"
puts ""
puts "  👥 Role Assignments:"
puts "    • super_admin: All permissions (programmatic)"
puts "    • admin: All admin KB permissions"
puts "    • owner: Content + admin permissions"
puts "    • manager: Content creation permissions"
puts "    • content_manager: Full content permissions"
puts "    • member: Read permission only"