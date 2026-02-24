# frozen_string_literal: true

# Marketing Permissions Seed
# Creates 13 marketing-related permissions for campaign, content, calendar,
# email list, social, and analytics access control.

puts "\n  Seeding Marketing permissions..."

marketing_permissions = {
  'marketing.campaigns.read'    => 'View marketing campaigns and their status',
  'marketing.campaigns.manage'  => 'Create, update, and delete marketing campaigns',
  'marketing.campaigns.execute' => 'Launch, pause, and resume marketing campaigns',
  'marketing.content.approve'   => 'Approve marketing content for publication',
  'marketing.calendar.read'     => 'View the marketing calendar and scheduled events',
  'marketing.calendar.manage'   => 'Create, update, and delete marketing calendar entries',
  'marketing.email_lists.read'  => 'View email lists and subscriber counts',
  'marketing.email_lists.manage' => 'Create, update, and delete email lists and subscribers',
  'marketing.social.read'       => 'View social media accounts and scheduled posts',
  'marketing.social.manage'     => 'Create, update, and delete social media posts and connections',
  'marketing.analytics.read'    => 'View marketing analytics, conversion rates, and ROI metrics',
  'admin.marketing.manage'      => 'Full administrative control over marketing features',
  'admin.marketing.settings'    => 'Configure marketing integrations and global settings'
}

created = 0

marketing_permissions.each do |name, description|
  Permission.find_or_create_from_name!(name, description)
  created += 1
end

puts "  ✅ Marketing permissions: #{created} ensured"

# Assign marketing permissions to relevant roles
admin_role = Role.find_by(name: 'admin')
if admin_role
  marketing_admin_perms = %w[
    admin.marketing.manage
    admin.marketing.settings
    marketing.campaigns.read
    marketing.campaigns.manage
    marketing.campaigns.execute
    marketing.content.approve
    marketing.calendar.read
    marketing.calendar.manage
    marketing.email_lists.read
    marketing.email_lists.manage
    marketing.social.read
    marketing.social.manage
    marketing.analytics.read
  ]

  marketing_admin_perms.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !admin_role.permissions.include?(permission)
      admin_role.permissions << permission
    end
  end
  puts "  ✅ Admin role updated with marketing permissions"
end

owner_role = Role.find_by(name: 'owner')
if owner_role
  marketing_owner_perms = %w[
    marketing.campaigns.read
    marketing.campaigns.manage
    marketing.campaigns.execute
    marketing.content.approve
    marketing.calendar.read
    marketing.calendar.manage
    marketing.email_lists.read
    marketing.email_lists.manage
    marketing.social.read
    marketing.social.manage
    marketing.analytics.read
  ]

  marketing_owner_perms.each do |perm_name|
    permission = Permission.find_by(name: perm_name)
    if permission && !owner_role.permissions.include?(permission)
      owner_role.permissions << permission
    end
  end
  puts "  ✅ Owner role updated with marketing permissions"
end
