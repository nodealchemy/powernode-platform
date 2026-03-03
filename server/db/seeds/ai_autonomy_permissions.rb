# frozen_string_literal: true

# Seed AI Autonomy permissions (Kill Switch, Goals, Intervention Policies,
# Proposals, Escalations, Feedback, Autonomy management)

puts "Seeding AI Autonomy permissions..."

autonomy_permissions = [
  # Kill Switch
  { resource: "ai.kill_switch", action: "manage", description: "Activate and deactivate the AI emergency kill switch" },

  # Agent Goals
  { resource: "ai.goals", action: "manage", description: "Create, update, and delete AI agent goals" },

  # Intervention Policies
  { resource: "ai.intervention_policies", action: "manage", description: "Configure AI intervention policies and notification preferences" },

  # Proposals
  { resource: "ai.proposals", action: "view", description: "View AI agent proposals" },
  { resource: "ai.proposals", action: "review", description: "Approve or reject AI agent proposals" },

  # Escalations
  { resource: "ai.escalations", action: "view", description: "View AI agent escalations" },
  { resource: "ai.escalations", action: "resolve", description: "Acknowledge and resolve AI agent escalations" },

  # Feedback
  { resource: "ai.feedback", action: "submit", description: "Submit feedback on AI agent performance" },
  { resource: "ai.feedback", action: "view", description: "View AI agent feedback history" },

  # Autonomy Management
  { resource: "ai.autonomy", action: "manage", description: "Manage AI agent autonomous behavior and duty cycles" },

  # Image Generation
  { resource: "ai.image", action: "generate", description: "Generate images using AI models (DALL-E)" }
]

autonomy_permissions.each do |perm_data|
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

# Assign ai.kill_switch.manage and ai.image.generate to owner and admin roles
%w[owner admin].each do |role_name|
  role = Role.find_by(name: role_name)
  next unless role

  %w[ai.kill_switch.manage ai.image.generate].each do |perm_name|
    perm = Permission.find_by(name: perm_name)
    next unless perm

    unless role.permissions.include?(perm)
      role.permissions << perm
      puts "\n  Assigned #{perm_name} to #{role_name} role"
    end
  end
end

puts "\nAI Autonomy permissions seeded!"
