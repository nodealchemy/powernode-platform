# frozen_string_literal: true

# Seed Docker Host Management permissions

puts "Seeding Docker Host Management permissions..."

docker_permissions = [
  # Host Management
  { resource: "docker.hosts", action: "read", description: "View Docker hosts and connection status" },
  { resource: "docker.hosts", action: "manage", description: "Create, update, and delete Docker hosts" },

  # Container Management
  { resource: "docker.containers", action: "read", description: "View Docker containers and their status" },
  { resource: "docker.containers", action: "create", description: "Create new Docker containers" },
  { resource: "docker.containers", action: "manage", description: "Start, stop, and restart Docker containers" },
  { resource: "docker.containers", action: "delete", description: "Remove Docker containers" },
  { resource: "docker.containers", action: "logs", description: "View Docker container logs" },
  { resource: "docker.containers", action: "exec", description: "Execute commands in Docker containers" },

  # Image Management
  { resource: "docker.images", action: "read", description: "View Docker images" },
  { resource: "docker.images", action: "pull", description: "Pull Docker images from registries" },
  { resource: "docker.images", action: "delete", description: "Remove Docker images" },
  { resource: "docker.images", action: "tag", description: "Tag Docker images" },

  # Network Management
  { resource: "docker.networks", action: "read", description: "View Docker networks" },
  { resource: "docker.networks", action: "manage", description: "Create and delete Docker networks" },

  # Volume Management
  { resource: "docker.volumes", action: "read", description: "View Docker volumes" },
  { resource: "docker.volumes", action: "manage", description: "Create and delete Docker volumes" },

  # Activity Tracking
  { resource: "docker.activities", action: "read", description: "View Docker activity history" },

  # Events
  { resource: "docker.events", action: "read", description: "View Docker host events" },
  { resource: "docker.events", action: "acknowledge", description: "Acknowledge Docker events" }
]

# Admin-level permission
admin_permissions = [
  { resource: "docker", action: "admin", description: "Administer Docker host settings and configurations", category: "admin" }
]

# Create resource permissions
docker_permissions.each do |perm_data|
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

puts "\nSeeded #{docker_permissions.count + admin_permissions.count} Docker Host Management permissions."

# Assign permissions to default roles
puts "Assigning Docker Host Management permissions to roles..."

owner_role = Role.find_by(name: "owner") || Role.find_by(name: "account.owner")
admin_role = Role.find_by(name: "admin") || Role.find_by(name: "account.admin")
manager_role = Role.find_by(name: "manager") || Role.find_by(name: "account.manager")
member_role = Role.find_by(name: "member") || Role.find_by(name: "account.member")

all_permission_names = docker_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" } +
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
  puts "  - Assigned all Docker permissions to owner role"
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
  puts "  - Assigned all Docker permissions to admin role"
end

# Manager gets read/write but not admin
if manager_role
  manager_permission_names = docker_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" }
  manager_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless manager_role.permissions.include?(permission)
      manager_role.permissions << permission
    end
  end
  puts "  - Assigned Docker read/write permissions to manager role"
end

# Member gets read-only permissions
if member_role
  read_permission_names = docker_permissions.select { |p| p[:action] == "read" }.map { |p| "#{p[:resource]}.#{p[:action]}" }
  read_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless member_role.permissions.include?(permission)
      member_role.permissions << permission
    end
  end
  puts "  - Assigned Docker read permissions to member role"
end

puts "Docker Host Management permissions seeding complete."
