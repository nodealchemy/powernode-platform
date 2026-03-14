# Database Schema Validation Checklist

**Purpose**: Prevent future schema-serialization mismatches  
**When to Use**: Before deploying schema changes, when adding new serializers  

## Pre-Deployment Schema Validation

### 1. Migration Validation
```bash
# Verify migration runs cleanly
rails db:migrate:status
rails db:migrate
rails db:rollback STEP=1
rails db:migrate
```

### 2. Model-Database Alignment Check
```bash
# Verify all model attributes exist in database
rails runner "
  [User, Account, Plan, Subscription, Invoice, Payment, PaymentMethod].each do |model|
    puts \"#{model.name}: #{model.column_names.sort}\"
  end
"
```

### 3. Factory Validation
```bash
# Test all factories can create records
rails runner "
  FactoryBot.factories.map(&:name).each do |factory_name|
    begin
      FactoryBot.create(factory_name)
      puts \"✅ #{factory_name}\"
    rescue => e
      puts \"❌ #{factory_name}: #{e.message}\"
    end
  end
"
```

### 4. Serialization Validation
```bash
# Test serializers don't reference missing columns
rails runner "
  # Test Page serialization
  page = Page.first || FactoryBot.create(:page)
  puts 'Page serialization: ' + (page.rendered_content ? '✅' : '❌')
  
  # Test RevenueSnapshot serialization
  snapshot = RevenueSnapshot.first || FactoryBot.create(:revenue_snapshot)
  puts 'Analytics serialization: ' + (snapshot.total_customers_count ? '✅' : '❌')
  
  # Test Invoice serialization
  invoice = Invoice.first || FactoryBot.create(:invoice)
  puts 'Invoice serialization: ' + (invoice.tax_rate ? '✅' : '❌')
"
```

## New Serializer Checklist

When adding new serializers, verify:

### 1. Column Existence
- [ ] All referenced columns exist in database
- [ ] Column types match expected usage
- [ ] Foreign key relationships properly defined

### 2. Association Verification
- [ ] `belongs_to` associations have corresponding foreign key columns
- [ ] `has_many` associations reference existing tables
- [ ] Association names match actual column names

### 3. Method Dependencies
- [ ] Custom serializer methods don't reference missing columns
- [ ] Computed fields have all required source columns
- [ ] Conditional serialization has proper null checks

## Schema Change Best Practices

### 1. Migration-First Development
```ruby
# Always create migration first
rails generate migration AddColumnToModel column_name:type

# Then update model
class Model < ApplicationRecord
  # Add validations, associations, etc.
end

# Finally update factories
FactoryBot.define do
  factory :model do
    column_name { "value" }
  end
end
```

### 2. Serialization-Safe Patterns
```ruby
# Safe: Check for column existence
def serialized_field
  object.respond_to?(:field) ? object.field : nil
end

# Safe: Use try for optional associations
def related_data
  object.association&.some_field
end

# Unsafe: Direct reference without checks
def unsafe_field
  object.missing_field # Will raise NoMethodError
end
```

### 3. Factory Safety Patterns
```ruby
# Safe: Optional attributes
factory :model do
  required_field { "value" }
  
  trait :with_optional do
    optional_field { "optional_value" }
  end
end

# Safe: Association creation
factory :model do
  association :parent, factory: :parent_model
end

# Unsafe: Setting non-existent attributes
factory :model do
  non_existent_field { "value" } # Will raise error
end
```

## Quick Diagnostic Commands

### Find Missing Columns
```bash
# Search for potential missing column references
grep -r "object\." app/serializers/
grep -r "\.column_name" spec/factories/
```

### Verify Database Constraints
```bash
# Check all constraints are valid
rails runner "
  ActiveRecord::Base.connection.execute('
    SELECT conname, pg_get_constraintdef(oid) 
    FROM pg_constraint 
    WHERE contype = \"c\"
  ').each { |row| puts \"#{row['conname']}: #{row['pg_get_constraintdef']}\" }
"
```

### Test Suite Health Check
```bash
# Quick test suite sampling
bundle exec rspec spec/models/ --format progress | tail -1
bundle exec rspec spec/controllers/ --format progress | tail -1
bundle exec rspec spec/requests/ --format progress | tail -1
```

## Emergency Schema Issue Resolution

If schema issues are discovered in production:

### 1. Immediate Assessment
```bash
# Check for missing columns in logs
grep "NoMethodError.*undefined method" production.log

# Identify affected serializers
grep -r "missing_column" app/serializers/
```

### 2. Hotfix Strategy
```ruby
# Temporary serializer fix
def safe_field
  object.respond_to?(:field) ? object.field : "default_value"
end
```

### 3. Permanent Resolution
1. Create migration for missing columns
2. Update models and factories
3. Test thoroughly in staging
4. Deploy with proper rollback plan

## Success Metrics

Monitor these metrics to ensure schema health:

- **API Error Rate**: Should be minimal for serialization errors
- **Test Suite Stability**: Consistent pass rates without schema-related failures
- **Factory Reliability**: All factories should create valid records
- **Migration Success**: All migrations should run without constraint violations

---

**Remember**: Schema changes are infrastructure changes. Treat them with the same care as production deployments.