# frozen_string_literal: true

# Seed Supply Chain permissions

puts "Seeding Supply Chain permissions..."

# The Permission model requires: resource, action, category (resource|admin|system)
# and auto-generates name as "resource.action"

supply_chain_permissions = [
  # SBOM Management
  { resource: "supply_chain.sboms", action: "read", description: "View SBOMs and components" },
  { resource: "supply_chain.sboms", action: "write", description: "Create, update, and delete SBOMs" },
  { resource: "supply_chain.sboms", action: "export", description: "Export SBOMs in various formats" },

  # Vulnerability Management
  { resource: "supply_chain.vulnerabilities", action: "read", description: "View vulnerabilities and CVE data" },
  { resource: "supply_chain.vulnerabilities", action: "write", description: "Manage vulnerability status and remediation" },
  { resource: "supply_chain.vulnerabilities", action: "suppress", description: "Suppress or dismiss vulnerabilities" },

  # Attestation Management
  { resource: "supply_chain.attestations", action: "read", description: "View attestations and provenance" },
  { resource: "supply_chain.attestations", action: "write", description: "Create and manage attestations" },
  { resource: "supply_chain.attestations", action: "sign", description: "Sign attestations with signing keys" },

  # Signing Key Management
  { resource: "supply_chain.signing_keys", action: "read", description: "View signing keys (public info only)" },
  { resource: "supply_chain.signing_keys", action: "write", description: "Create and manage signing keys" },
  { resource: "supply_chain.signing_keys", action: "rotate", description: "Rotate and revoke signing keys" },

  # Container Security
  { resource: "supply_chain.containers", action: "read", description: "View container images and scans" },
  { resource: "supply_chain.containers", action: "write", description: "Manage container images and policies" },
  { resource: "supply_chain.containers", action: "scan", description: "Trigger container vulnerability scans" },
  { resource: "supply_chain.containers", action: "quarantine", description: "Quarantine and release container images" },

  # Image Policy Management
  { resource: "supply_chain.policies", action: "read", description: "View image and license policies" },
  { resource: "supply_chain.policies", action: "write", description: "Create and manage policies" },

  # License Compliance
  { resource: "supply_chain.licenses", action: "read", description: "View licenses and compliance status" },
  { resource: "supply_chain.licenses", action: "write", description: "Manage license policies and violations" },
  { resource: "supply_chain.licenses", action: "exception", description: "Grant license violation exceptions" },

  # Vendor Risk Management
  { resource: "supply_chain.vendors", action: "read", description: "View vendors and risk assessments" },
  { resource: "supply_chain.vendors", action: "write", description: "Create and manage vendors" },
  { resource: "supply_chain.vendors", action: "assess", description: "Conduct vendor risk assessments" },
  { resource: "supply_chain.vendors", action: "questionnaires", description: "Send and review vendor questionnaires" },

  # Scan Templates (Marketplace)
  { resource: "supply_chain.templates", action: "read", description: "View scan templates" },
  { resource: "supply_chain.templates", action: "write", description: "Create and manage scan templates" },
  { resource: "supply_chain.templates", action: "publish", description: "Publish templates to marketplace" },

  # Reports
  { resource: "supply_chain.reports", action: "read", description: "View and download reports" },
  { resource: "supply_chain.reports", action: "write", description: "Generate compliance reports" },

  # CVE Monitoring
  { resource: "supply_chain.monitoring", action: "read", description: "View CVE monitors and alerts" },
  { resource: "supply_chain.monitoring", action: "write", description: "Configure CVE monitoring" },

  # General Permissions
  { resource: "supply_chain", action: "read", description: "View all supply chain data (read-only access)" },
  { resource: "supply_chain", action: "write", description: "Manage supply chain data (full access)" }
]

# Admin-level permission
admin_permissions = [
  { resource: "supply_chain", action: "admin", description: "Administer supply chain settings and configurations", category: "admin" }
]

# Create resource permissions
supply_chain_permissions.each do |perm_data|
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

puts "\nSeeded #{supply_chain_permissions.count + admin_permissions.count} Supply Chain permissions."

# Assign permissions to default roles
puts "Assigning Supply Chain permissions to roles..."

# Find or create roles
owner_role = Role.find_by(name: "owner") || Role.find_by(name: "account.owner")
admin_role = Role.find_by(name: "admin") || Role.find_by(name: "account.admin")
manager_role = Role.find_by(name: "manager") || Role.find_by(name: "account.manager")
member_role = Role.find_by(name: "member") || Role.find_by(name: "account.member")

all_permission_names = supply_chain_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" } +
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
  puts "  - Assigned all Supply Chain permissions to owner role"
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
  puts "  - Assigned all Supply Chain permissions to admin role"
end

# Manager gets read/write but not admin
if manager_role
  manager_permission_names = supply_chain_permissions.map { |p| "#{p[:resource]}.#{p[:action]}" }
  manager_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless manager_role.permissions.include?(permission)
      manager_role.permissions << permission
    end
  end
  puts "  - Assigned Supply Chain read/write permissions to manager role"
end

# Member gets read-only permissions
if member_role
  read_permission_names = supply_chain_permissions.select { |p| p[:action] == "read" }.map { |p| "#{p[:resource]}.#{p[:action]}" }
  read_permission_names.each do |name|
    permission = Permission.find_by(name: name)
    next unless permission

    unless member_role.permissions.include?(permission)
      member_role.permissions << permission
    end
  end
  puts "  - Assigned Supply Chain read permissions to member role"
end

puts "Supply Chain permissions seeding complete."
