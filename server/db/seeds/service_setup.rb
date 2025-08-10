# Service Setup Seeds
# Creates initial services for the Powernode platform

puts "Setting up initial services..."

# Create a global worker service for background job processing
worker_service = Service.find_or_create_by(name: 'Powernode Worker') do |service|
  service.description = 'Global worker service for background job processing and scheduled tasks'
  service.permissions = 'admin'
  service.account = nil # Global service
  service.status = 'active'
  service.token = Service.send(:generate_secure_token)
end

if worker_service.persisted?
  puts "✅ Created/updated Powernode Worker service"
  puts "   - ID: #{worker_service.id}"
  puts "   - Token: #{worker_service.token}"
  puts "   - Permissions: #{worker_service.permissions}"
  puts "   - Status: #{worker_service.status}"
  
  # Log the service creation
  worker_service.record_activity!('service_setup', {
    setup_at: Time.current.iso8601,
    status: 'success',
    source: 'db:seed'
  })
  
  # Update environment file if it exists
  worker_env_file = Rails.root.join('..', 'worker', '.env')
  if File.exist?(worker_env_file)
    env_content = File.read(worker_env_file)
    
    # Update or add SERVICE_TOKEN
    if env_content.include?('SERVICE_TOKEN=')
      env_content.gsub!(/SERVICE_TOKEN=.*/, "SERVICE_TOKEN=#{worker_service.token}")
    else
      env_content += "\n# Service Authentication\nSERVICE_TOKEN=#{worker_service.token}\n"
    end
    
    File.write(worker_env_file, env_content)
    puts "   - Updated worker/.env with new service token"
  end
else
  puts "❌ Failed to create Powernode Worker service"
  worker_service.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end

# Create a sample readonly service for demonstration
readonly_service = Service.find_or_create_by(name: 'Sample Readonly Service') do |service|
  service.description = 'Example readonly service for API access'
  service.permissions = 'readonly'
  service.account = nil # Global service
  service.status = 'active'
  service.token = Service.send(:generate_secure_token)
end

if readonly_service.persisted?
  puts "✅ Created/updated Sample Readonly Service"
  puts "   - ID: #{readonly_service.id}"
  puts "   - Token: #{readonly_service.masked_token}"
  puts "   - Permissions: #{readonly_service.permissions}"
  puts "   - Status: #{readonly_service.status}"
  
  readonly_service.record_activity!('service_setup', {
    setup_at: Time.current.iso8601,
    status: 'success',
    source: 'db:seed'
  })
end

puts "\nService setup complete!"
puts "You can manage these services through the admin interface at:"
puts "  - Backend API: /api/v1/admin/services"
puts "  - Frontend: Admin Panel > Services"
puts "\nService tokens should be stored securely and used for API authentication."