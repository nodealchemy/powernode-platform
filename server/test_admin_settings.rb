begin
  # Test admin settings update
  puts "Testing admin settings update..."
  
  # Load current settings
  current_settings = SystemSettingsService.load_settings
  puts "Current copyright text: #{current_settings[:copyright_text]}"
  
  # Test update
  new_settings = { copyright_text: "© {year} Powernode Platform Test Update #{Time.current.to_i}" }
  updated_settings = SystemSettingsService.update_settings(new_settings)
  puts "Updated settings successfully: #{updated_settings[:copyright_text]}"
  
  # Verify persistence
  reloaded_settings = SystemSettingsService.load_settings
  puts "Reloaded copyright text: #{reloaded_settings[:copyright_text]}"
  
  puts "✅ Admin settings update test: SUCCESS"
  
rescue StandardError => e
  puts "❌ Admin settings update test failed: #{e.class.name}: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.join("\n")
end