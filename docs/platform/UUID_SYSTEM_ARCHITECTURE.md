# UUIDv7 System Architecture

This document describes the comprehensive UUIDv7 implementation across the Powernode platform.

## Overview

Powernode uses UUIDv7 (UUID Version 7) as the primary key format for all database models. UUIDv7 provides the benefits of traditional UUIDs while maintaining chronological ordering, making them ideal for database primary keys and distributed systems.

## Architecture Components

### 1. UuidGenerator Concern

**Location**: `app/models/concerns/uuid_generator.rb`

The `UuidGenerator` concern is the core component that provides UUIDv7 generation functionality:

```ruby
module UuidGenerator
  extend ActiveSupport::Concern

  included do
    self.primary_key = 'id'
    # Override the default UUID generation to use UUIDv7
    before_create :generate_uuid_v7, if: -> { id.blank? }
  end

  private

  def generate_uuid_v7
    self.id = UUID7.generate if id.blank?
  end
end
```

**Key Features**:
- Automatically generates UUIDv7 for all new records
- Only generates if ID is blank (allows manual ID assignment)
- Uses the UUID7 gem for proper v7 format generation
- Chronologically sortable UUIDs with millisecond precision

### 2. ApplicationRecord Integration

**Location**: `app/models/application_record.rb`

All models inherit UUIDv7 generation by default:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  # Include UuidGenerator by default for all models
  # This ensures all models use UUIDv7 format for primary keys
  include UuidGenerator
end
```

**Benefits**:
- **Default Behavior**: All new models automatically use UUIDv7
- **Consistency**: No need to remember to add UUID generation to new models
- **Platform-wide Standard**: Ensures uniform ID format across all tables

### 3. Database Schema

**ID Column Configuration**:
```ruby
create_table :example_table, id: :uuid do |t|
  # PostgreSQL native UUID type
  # No default value - Rails handles generation
  t.timestamps
end
```

**Foreign Key Configuration**:
```ruby
t.references :parent, null: false, foreign_key: true, type: :uuid
```

**Key Points**:
- Uses PostgreSQL native `uuid` type (not `string`)
- No database-level default UUID generation
- Rails application layer controls UUID generation
- Foreign keys properly typed as UUID

## UUIDv7 Format

### Structure
```
UUIDv7: 0198ebd9-6018-7c94-ad91-9eb1cf7745d5
         └─timestamp─┘ └ver─┘ └─────random─────┘
```

### Components
- **Timestamp** (48 bits): Unix timestamp with millisecond precision
- **Version** (4 bits): Always "7" for UUIDv7
- **Random** (74 bits): Cryptographically random data

### Benefits
1. **Chronological Ordering**: Natural database index ordering
2. **Global Uniqueness**: Collision-resistant across distributed systems
3. **Database Performance**: Better B-tree index performance than UUIDv4
4. **Sortability**: Can sort by creation time using string comparison

## Implementation Details

### Dependencies

**Gemfile**:
```ruby
gem 'uuid7', '~> 0.1'  # UUIDv7 generation
```

### Model Integration

All models in the system include UUIDv7 by default through ApplicationRecord inheritance:

```ruby
class ExampleModel < ApplicationRecord
  # UuidGenerator included automatically
  # No additional configuration needed
end
```

### Manual Override (if needed):
```ruby
class SpecialModel < ApplicationRecord
  # Override the default behavior if needed
  before_create :custom_id_generation
  
  private
  
  def custom_id_generation
    # Custom logic here
  end
end
```

## Migration Strategy

### Database Conversion

1. **Schema Update**: Convert all ID columns from `string` to `uuid` type
2. **Data Migration**: Convert existing string UUIDs to proper UUID format
3. **Application Update**: Add UuidGenerator to all models
4. **Verification**: Ensure all new records use UUIDv7 format

### Migration Examples

**Creating new table**:
```ruby
class CreateNewTable < ActiveRecord::Migration[8.0]
  def change
    create_table :new_table, id: :uuid do |t|
      t.string :name, null: false
      t.references :parent, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end
  end
end
```

**Converting existing table**:
```ruby
class ConvertTableToUuid < ActiveRecord::Migration[8.0]
  def up
    # Drop existing table and recreate with UUID
    drop_table :example_table
    create_table :example_table, id: :uuid do |t|
      # Recreate columns
    end
  end
end
```

## Performance Considerations

### Database Performance
- **Index Performance**: UUIDv7 provides better B-tree index performance than UUIDv4
- **Storage Size**: 16 bytes per UUID (same as UUIDv4)
- **Insert Performance**: Chronological ordering reduces index fragmentation

### Application Performance
- **Generation Speed**: Fast UUID generation using optimized UUID7 gem
- **Memory Usage**: Minimal overhead from UuidGenerator concern
- **Startup Time**: No impact on application startup

## Verification and Testing

### UUID Format Verification
```ruby
# Verify UUIDv7 format
def check_uuid_format(uuid_string)
  version = uuid_string.split('-')[2][0].to_i(16)
  case version
  when 7 then 'UUIDv7'
  else "Unknown (v#{version})"
  end
end
```

### System-wide Verification
```ruby
# Check all models use UUIDv7
models_with_non_v7 = []
ApplicationRecord.descendants.each do |model|
  next unless model.table_exists?
  sample = model.first
  next unless sample
  
  version = sample.id.split('-')[2][0].to_i(16)
  models_with_non_v7 << model.name unless version == 7
end
```

## Best Practices

### Model Development
1. **Inherit from ApplicationRecord**: Automatic UUIDv7 inclusion
2. **Don't override ID generation**: Unless specifically needed
3. **Use UUID foreign keys**: Maintain consistency across relationships
4. **Test UUID format**: Verify v7 format in critical tests

### Database Design
1. **Use native UUID type**: Not string(36)
2. **Proper foreign key types**: Always specify `type: :uuid`
3. **Index considerations**: UUIDv7 works well with B-tree indexes
4. **Backup considerations**: UUIDs are universally unique across environments

### Development Workflow
1. **New models**: No special UUID configuration needed
2. **Existing models**: Already updated with UuidGenerator
3. **Testing**: Use factories that leverage automatic UUID generation
4. **Debugging**: UUID format indicates creation order

## Troubleshooting

### Common Issues

**Issue**: Model not generating UUIDv7
**Solution**: Verify it inherits from ApplicationRecord and has UUID ID column

**Issue**: Foreign key type mismatch
**Solution**: Ensure foreign key references use `type: :uuid`

**Issue**: Existing data with wrong UUID format
**Solution**: Run data migration to regenerate UUIDs for affected records

### Debugging Tools

```ruby
# Check model UUID configuration
Model.new.tap { |m| puts m.class.primary_key } # Should be 'id'
Model.create.id.split('-')[2][0] # Should be '7'

# Verify database schema
ActiveRecord::Base.connection.columns('table_name').find { |c| c.name == 'id' }.sql_type
# Should be 'uuid'
```

## Migration History

### Phase 1: Core Models (Completed)
- User, Account, Plan, Role, Permission, Subscription
- Knowledge Base models (Article, Category, Tag, etc.)

### Phase 2: Platform-wide Rollout (Completed)
- All remaining 50+ models updated
- ApplicationRecord integration for future models
- Documentation and guidelines created

## Future Considerations

### Monitoring
- Track UUID generation performance
- Monitor database index performance
- Verify UUID format compliance

### Enhancements
- Consider custom UUID prefixes for different model types
- Implement UUID validation helpers
- Add metrics for UUID generation patterns

---

**Implementation Status**: ✅ Complete  
**Total Models with UUIDv7**: 64/64  
**Database Schema**: Native PostgreSQL UUID type  
**Default Behavior**: All new models inherit UUIDv7 generation