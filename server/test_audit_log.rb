begin
  user = User.first
  account = user.account if user
  
  if user && account
    puts "Testing AuditLog creation with user: #{user.email}"
    
    audit_log = AuditLog.create!(
      user: user,
      account: account,
      action: 'admin_settings_update',
      resource_type: 'SystemSettings',
      resource_id: 'system',
      source: 'admin_panel',
      ip_address: '127.0.0.1',
      user_agent: 'Test User Agent',
      metadata: {
        updated_fields: ['copyright_text'],
        rate_limiting_changed: false
      }
    )
    puts "AuditLog creation successful: #{audit_log.id}"
  else
    puts "No user or account found for testing"
  end
rescue StandardError => e
  puts "AuditLog creation failed: #{e.class.name}: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.join("\n")
end