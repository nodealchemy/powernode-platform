puts "=== DATABASE CHECK ==="
begin
  connection_active = ActiveRecord::Base.connection.active?
  puts "Database connection: #{connection_active ? 'OK' : 'FAILED'}"
rescue => e
  puts "Database connection: ERROR (#{e.message})"
end

begin
  model_count = ActiveRecord::Base.descendants.select { |model| model.table_exists? }.count
  puts "Model count: #{model_count} models"
rescue => e
  puts "Model count: ERROR (#{e.message})"
end

begin
  user_count = User.count
  puts "User count test: #{user_count} users found"
rescue => e
  puts "User count test: ERROR (#{e.message})"
end

puts "\n=== MODEL LOADING CHECK ==="
puts "Loading all models..."
Rails.application.eager_load!
puts "SUCCESS: All models loaded"

puts "\n=== ROUTES CHECK ==="
routes_count = Rails.application.routes.routes.count
puts "Routes loaded: #{routes_count} routes"

puts "\n=== CACHE CHECK ==="
begin
  Rails.cache.write('test_key', 'test_value')
  cached_value = Rails.cache.read('test_key')
  puts "Cache: #{cached_value == 'test_value' ? 'OK' : 'FAILED'}"
rescue => e
  puts "Cache: FAILED (#{e.message})"
end

puts "\n=== CONFIG CHECK ==="
puts "Environment: #{Rails.env}"
puts "JWT secret configured: #{Rails.application.config.jwt_secret_key.present? ? 'YES' : 'NO'}"
puts "Database config: #{ActiveRecord::Base.connection_db_config.database}"
