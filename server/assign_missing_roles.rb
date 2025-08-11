#!/usr/bin/env ruby

require_relative 'config/environment'

puts 'Assigning roles to users without roles...'
puts '=' * 45

# Find users without roles
users_without_roles = User.left_joins(:roles).where(roles: { id: nil })

puts "Found #{users_without_roles.count} users without roles"

users_without_roles.each do |user|
  puts "\nProcessing #{user.email} (#{user.account.name})..."
  
  # Get the account's subscription plan to determine default roles
  subscription = user.account.subscription
  plan = subscription&.plan
  
  if plan && plan.default_roles.present?
    # Assign default roles from the plan
    plan.default_roles.each do |role_name|
      role = Role.find_by(name: role_name)
      if role
        user.assign_role(role) unless user.roles.include?(role)
        puts "  ✅ Assigned #{role_name} role"
      else
        puts "  ❌ WARNING: Role '#{role_name}' not found"
      end
    end
  else
    # If no plan or default roles, assign Member role as fallback
    member_role = Role.find_by(name: 'Member')
    if member_role
      user.assign_role(member_role) unless user.roles.include?(member_role)
      puts "  ✅ Assigned Member role (fallback)"
    else
      puts "  ❌ ERROR: Member role not found"
    end
  end
  
  # Save the user to persist role assignments
  user.save!
  puts "  💾 Saved user with #{user.roles.count} role(s)"
end

puts "\n" + "=" * 45
puts "Completed role assignment for #{users_without_roles.count} users"

# Verify all users now have roles
remaining_users_without_roles = User.left_joins(:roles).where(roles: { id: nil }).count
if remaining_users_without_roles == 0
  puts "✅ SUCCESS: All users now have at least one role assigned"
else
  puts "❌ WARNING: #{remaining_users_without_roles} users still without roles"
end