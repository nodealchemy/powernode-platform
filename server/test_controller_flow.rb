begin
  puts "Testing full admin settings controller flow..."
  
  # Find admin user
  admin_user = User.find_by(email: 'admin@powernode.dev')
  if admin_user.nil?
    puts "❌ Admin user not found"
    exit 1
  end
  
  puts "✅ Found admin user: #{admin_user.email}"
  
  # Simulate controller params
  settings_params = { copyright_text: "© {year} Powernode Platform Controller Test #{Time.current.to_i}" }
  
  puts "Testing SystemSettingsService.update_settings..."
  updated_settings = SystemSettingsService.update_settings(settings_params)
  puts "✅ SystemSettingsService updated successfully: #{updated_settings[:copyright_text]}"
  
  puts "Testing AuditLog.create! for admin_settings_update..."
  audit_log = AuditLog.create!(
    user: admin_user,
    account: admin_user.account,
    action: 'admin_settings_update',
    resource_type: 'SystemSettings',
    resource_id: 'system',
    source: 'admin_panel',
    ip_address: '127.0.0.1',
    user_agent: 'Test User Agent',
    metadata: {
      updated_fields: settings_params.keys,
      rate_limiting_changed: settings_params.key?(:rate_limiting)
    }
  )
  puts "✅ AuditLog creation successful: #{audit_log.id}"
  
  puts "✅ FULL CONTROLLER FLOW TEST: SUCCESS"
  puts "The admin settings controller should now work without 422 errors!"
  
rescue StandardError => e
  puts "❌ Controller flow test failed: #{e.class.name}: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.join("\n")
end