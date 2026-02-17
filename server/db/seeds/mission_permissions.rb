# frozen_string_literal: true

puts "Seeding Mission permissions..."

mission_permissions = [
  { resource: "ai.missions", action: "read", description: "View missions and mission details" },
  { resource: "ai.missions", action: "manage", description: "Create, manage, and approve missions" }
]

mission_permissions.each do |perm_data|
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

puts "\nSeeded #{mission_permissions.count} Mission permissions."

# Assign to roles
owner_role = Role.find_by(name: "owner") || Role.find_by(name: "account.owner")
admin_role = Role.find_by(name: "admin") || Role.find_by(name: "account.admin")
manager_role = Role.find_by(name: "manager") || Role.find_by(name: "account.manager")
member_role = Role.find_by(name: "member") || Role.find_by(name: "account.member")

all_names = mission_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" }
read_names = mission_permissions.select { |p| p[:action] == "read" }.map { |p| "#{p[:resource]}.#{p[:action]}" }

[owner_role, admin_role, manager_role].compact.each do |role|
  all_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission
    role.permissions << permission unless role.permissions.include?(permission)
  end
end

if member_role
  read_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission
    member_role.permissions << permission unless member_role.permissions.include?(permission)
  end
end

puts "Mission permissions seeding complete."
