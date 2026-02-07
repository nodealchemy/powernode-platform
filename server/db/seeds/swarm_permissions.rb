# frozen_string_literal: true

# Seed Docker Swarm management permissions

puts "Seeding Docker Swarm permissions..."

# The Permission model requires: resource, action, category (resource|admin|system)
# and auto-generates name as "resource.action"

swarm_permissions = [
  # Cluster Management
  { resource: "swarm.clusters", action: "read", description: "View Swarm clusters and connection status" },
  { resource: "swarm.clusters", action: "manage", description: "Create, update, and delete Swarm clusters" },

  # Service Management
  { resource: "swarm.services", action: "read", description: "View Swarm services and their status" },
  { resource: "swarm.services", action: "create", description: "Create new Swarm services" },
  { resource: "swarm.services", action: "update", description: "Update Swarm service configuration" },
  { resource: "swarm.services", action: "delete", description: "Delete Swarm services" },
  { resource: "swarm.services", action: "scale", description: "Scale Swarm services up or down" },
  { resource: "swarm.services", action: "rollback", description: "Rollback Swarm services to previous version" },

  # Stack Management
  { resource: "swarm.stacks", action: "read", description: "View Swarm stacks and compose definitions" },
  { resource: "swarm.stacks", action: "create", description: "Create new Swarm stacks" },
  { resource: "swarm.stacks", action: "update", description: "Update Swarm stack configuration" },
  { resource: "swarm.stacks", action: "delete", description: "Delete Swarm stacks" },
  { resource: "swarm.stacks", action: "deploy", description: "Deploy Swarm stacks to clusters" },

  # Node Management
  { resource: "swarm.nodes", action: "read", description: "View Swarm nodes and their status" },
  { resource: "swarm.nodes", action: "manage", description: "Promote, demote, drain, and remove Swarm nodes" },

  # Secrets Management
  { resource: "swarm.secrets", action: "read", description: "View Swarm secrets metadata" },
  { resource: "swarm.secrets", action: "manage", description: "Create and delete Swarm secrets" },

  # Configs Management
  { resource: "swarm.configs", action: "read", description: "View Swarm configs" },
  { resource: "swarm.configs", action: "manage", description: "Create and delete Swarm configs" },

  # Network Management
  { resource: "swarm.networks", action: "read", description: "View Swarm overlay networks" },
  { resource: "swarm.networks", action: "manage", description: "Create and delete Swarm networks" },

  # Volume Management
  { resource: "swarm.volumes", action: "read", description: "View Swarm volumes" },
  { resource: "swarm.volumes", action: "manage", description: "Create and delete Swarm volumes" },

  # Deployment Tracking
  { resource: "swarm.deployments", action: "read", description: "View Swarm deployment history" },

  # Events
  { resource: "swarm.events", action: "read", description: "View Swarm cluster events" },
  { resource: "swarm.events", action: "acknowledge", description: "Acknowledge Swarm events" },

  # Logs
  { resource: "swarm.logs", action: "read", description: "View Swarm service and container logs" }
]

# Admin-level permission
admin_permissions = [
  { resource: "swarm", action: "admin", description: "Administer Docker Swarm settings and configurations", category: "admin" }
]

# Create resource permissions
swarm_permissions.each do |perm_data|
  name = "#{perm_data[:resource]}.#{perm_data[:action]}"
  permission = Permission.find_or_initialize_by(
    resource: perm_data[:resource],
    action: perm_data[:action],
    category: "resource"
  )
  permission.name = name
  permission.description = perm_data[:description]
  permission.save!
  print "."
end

# Create admin permissions
admin_permissions.each do |perm_data|
  name = "admin.#{perm_data[:resource]}.#{perm_data[:action]}"
  permission = Permission.find_or_initialize_by(
    resource: perm_data[:resource],
    action: perm_data[:action],
    category: "admin"
  )
  permission.name = name
  permission.description = perm_data[:description]
  permission.save!
  print "."
end

puts "\nSeeded #{swarm_permissions.count + admin_permissions.count} Docker Swarm permissions."

# Assign permissions to default roles
puts "Assigning Docker Swarm permissions to roles..."

# Find or create roles
owner_role = Role.find_by(name: "owner") || Role.find_by(name: "account.owner")
admin_role = Role.find_by(name: "admin") || Role.find_by(name: "account.admin")
manager_role = Role.find_by(name: "manager") || Role.find_by(name: "account.manager")
member_role = Role.find_by(name: "member") || Role.find_by(name: "account.member")

all_permission_names = swarm_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" } +
                       admin_permissions.map { |p| "admin.#{p[:resource]}.#{p[:action]}" }

# Owner gets all permissions
if owner_role
  all_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless owner_role.permissions.include?(permission)
      owner_role.permissions << permission
    end
  end
  puts "  - Assigned all Docker Swarm permissions to owner role"
end

# Admin gets all permissions
if admin_role
  all_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless admin_role.permissions.include?(permission)
      admin_role.permissions << permission
    end
  end
  puts "  - Assigned all Docker Swarm permissions to admin role"
end

# Manager gets read/write but not admin
if manager_role
  manager_permission_names = swarm_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" }
  manager_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless manager_role.permissions.include?(permission)
      manager_role.permissions << permission
    end
  end
  puts "  - Assigned Docker Swarm read/write permissions to manager role"
end

# Member gets read-only permissions
if member_role
  read_permission_names = swarm_permissions.select { |p| p[:action] == "read" }.map { |p| "#{p[:resource]}.#{p[:action]}" }
  read_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless member_role.permissions.include?(permission)
      member_role.permissions << permission
    end
  end
  puts "  - Assigned Docker Swarm read permissions to member role"
end

puts "Docker Swarm permissions seeding complete."
