# UUIDv7 Development Guidelines

This document provides practical guidelines for developers working with the UUIDv7 system in Powernode.

## Quick Start

### Creating New Models

All new models automatically use UUIDv7 - no additional configuration needed:

```ruby
# Generate new model
rails generate model BlogPost title:string content:text user:references

# The generated model automatically includes UUIDv7:
class BlogPost < ApplicationRecord
  belongs_to :user  # Automatically uses UUID foreign key
  
  validates :title, presence: true
end
```

**Migration will be generated with proper UUID types**:
```ruby
class CreateBlogPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :blog_posts, id: :uuid do |t|
      t.string :title
      t.text :content
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end
  end
end
```

### Working with Existing Models

All models already use UUIDv7 - just use them normally:

```ruby
user = User.create!(first_name: "John", last_name: "Doe", email: "john@example.com")
puts user.id # => "0198ebd9-6018-7c94-ad91-9eb1cf7745d5" (UUIDv7 format)

# Associations work normally
plan = Plan.first
subscription = user.account.subscriptions.create!(plan: plan, quantity: 1)
puts subscription.id # => "0198ebd9-6019-7a12-bb33-4ed2cf8845d3" (UUIDv7 format)
```

## Working with UUIDs

### UUID Format Recognition

```ruby
def uuid_version(uuid_string)
  uuid_string.split('-')[2][0].to_i(16)
end

# Examples
uuid_version("0198ebd9-6018-7c94-ad91-9eb1cf7745d5") # => 7 (UUIDv7)
uuid_version("6ba7b810-9dad-11d1-80b4-00c04fd430c8") # => 1 (UUIDv1)
uuid_version("550e8400-e29b-41d4-a716-446655440000") # => 4 (UUIDv4)
```

### Chronological Ordering

UUIDv7s can be sorted chronologically:

```ruby
# Recent records will have "larger" UUIDs
recent_articles = KnowledgeBaseArticle.order(:id) # Ordered by creation time
latest_first = KnowledgeBaseArticle.order(id: :desc) # Newest first

# This works because UUIDv7 embeds timestamp in sortable format
```

### Manual ID Assignment

If you need to set IDs manually (rare cases):

```ruby
# This will skip automatic UUID generation
record = Model.new(id: "custom-uuid-here", other_attributes: "...")
record.save!

# Or for external system imports
Model.create!(id: imported_uuid, name: "Imported Record")
```

## Database Operations

### Migrations

**Creating tables**:
```ruby
class CreateNewFeature < ActiveRecord::Migration[8.0]
  def change
    create_table :new_feature, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      
      # Foreign keys - always specify type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid
      
      t.timestamps
    end
    
    # Indexes work normally with UUIDs
    add_index :new_feature, :name, unique: true
    add_index :new_feature, [:account_id, :created_at]
  end
end
```

**Adding foreign keys to existing tables**:
```ruby
class AddUserToExistingTable < ActiveRecord::Migration[8.0]
  def change
    # Always specify type: :uuid for references
    add_reference :existing_table, :user, null: false, foreign_key: true, type: :uuid
  end
end
```

**Complex migrations**:
```ruby
class CreateJoinTable < ActiveRecord::Migration[8.0]
  def change
    create_table :article_tags, id: :uuid do |t|
      t.references :article, null: false, foreign_key: { to_table: :knowledge_base_articles }, type: :uuid
      t.references :tag, null: false, foreign_key: { to_table: :knowledge_base_tags }, type: :uuid
      t.timestamps
    end
    
    # Composite indexes work well with UUIDs
    add_index :article_tags, [:article_id, :tag_id], unique: true
  end
end
```

### Querying with UUIDs

```ruby
# Find by UUID - works exactly the same
user = User.find("0198ebd9-6018-7c94-ad91-9eb1cf7745d5")

# Batch operations
User.where(id: ["uuid1", "uuid2", "uuid3"])

# Associations - no changes needed
user.subscriptions.includes(:plan)

# Joins work normally
User.joins(:account, :subscriptions).where(subscriptions: { status: 'active' })
```

## Testing

### Factories (FactoryBot)

Factories work automatically with UUIDs:

```ruby
# spec/factories/blog_posts.rb
FactoryBot.define do
  factory :blog_post do
    title { "Sample Blog Post" }
    content { "This is the content" }
    user # Associates with a user factory - UUID handled automatically
  end
end

# In tests
blog_post = create(:blog_post)
puts blog_post.id # UUIDv7 format
puts blog_post.user_id # UUIDv7 format
```

### Testing UUID Format

```ruby
# RSpec helper
RSpec.shared_examples "has uuid primary key" do
  it "generates UUIDv7 format ID" do
    record = create(described_class.name.underscore.to_sym)
    version = record.id.split('-')[2][0].to_i(16)
    expect(version).to eq(7)
  end
end

# Use in model specs
RSpec.describe BlogPost do
  include_examples "has uuid primary key"
end
```

### Fixtures vs Factories

**Prefer factories** for UUID models:
```ruby
# Good - Factories handle UUIDs automatically
let(:user) { create(:user) }
let(:blog_post) { create(:blog_post, user: user) }

# Avoid fixtures with UUIDs - harder to maintain
# fixtures/users.yml (not recommended for UUID models)
```

## API Development

### JSON Serialization

UUIDs serialize to strings automatically:

```ruby
# Controller
def show
  render_success(user: @user)
end

# JSON output
{
  "success": true,
  "data": {
    "user": {
      "id": "0198ebd9-6018-7c94-ad91-9eb1cf7745d5",
      "first_name": "John",
      "last_name": "Doe",
      "account_id": "0198ebd9-6017-7b22-aa44-3dc1bf7634e2"
    }
  }
}
```

### API Parameters

Handle UUID parameters like strings:

```ruby
class BlogPostsController < ApplicationController
  def show
    @blog_post = BlogPost.find(params[:id]) # UUID string works fine
  end
  
  def create
    @blog_post = BlogPost.new(blog_post_params)
    # user_id will be UUID string from params - Rails handles conversion
  end
  
  private
  
  def blog_post_params
    params.require(:blog_post).permit(:title, :content, :user_id)
  end
end
```

### Frontend Integration

JavaScript/TypeScript handles UUIDs as strings:

```typescript
interface BlogPost {
  id: string;  // UUIDv7 string
  title: string;
  content: string;
  user_id: string;  // UUIDv7 string
  created_at: string;
  updated_at: string;
}

// API calls work normally
const response = await api.get(`/api/v1/blog_posts/${postId}`);
```

## Performance Considerations

### Database Performance

**Good practices**:
```ruby
# UUIDv7s are naturally ordered - use this for pagination
def recent_posts(limit: 10)
  BlogPost.order(id: :desc).limit(limit)
end

# Indexes work well with UUIDv7
add_index :blog_posts, [:user_id, :id] # Composite index for user's posts by time
```

**Avoid**:
```ruby
# Don't rely on ID ordering for business logic
# Use explicit timestamp columns for business requirements
def posts_by_publish_date
  BlogPost.order(:published_at) # Good - explicit business logic
end

def posts_by_creation(limit = 10)
  BlogPost.order(:id).limit(limit) # OK but not semantic
end
```

### Memory and Storage

- UUIDs are 16 bytes in database (same as UUIDv4)
- String representation is 36 characters
- Performance impact is minimal compared to benefits

## Common Patterns

### Bulk Operations

```ruby
# Bulk create with UUIDs
records = [
  { title: "Post 1", content: "Content 1", user_id: user.id },
  { title: "Post 2", content: "Content 2", user_id: user.id }
]
BlogPost.insert_all(records) # IDs generated automatically

# Bulk update
BlogPost.where(user: user).update_all(status: 'published')
```

### Soft Deletes

```ruby
class BlogPost < ApplicationRecord
  # UUIDs work great with soft deletes
  scope :active, -> { where(deleted_at: nil) }
  
  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
```

### Polymorphic Associations

```ruby
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  # commentable_id will be UUID automatically
end

class BlogPost < ApplicationRecord
  has_many :comments, as: :commentable
end

# Usage
blog_post = BlogPost.first
comment = blog_post.comments.create!(content: "Great post!")
puts comment.commentable_id # UUIDv7 string
```

## Error Handling

### Common Errors

```ruby
# Invalid UUID format
begin
  User.find("invalid-uuid")
rescue ActiveRecord::RecordNotFound
  # Handle gracefully
end

# Type mismatches in development
begin
  BlogPost.create!(user_id: 123) # Integer instead of UUID
rescue ActiveRecord::StatementInvalid => e
  # Handle UUID type errors
end
```

### Validation

```ruby
class BlogPost < ApplicationRecord
  # Optional: Validate UUID format if accepting external IDs
  validates :external_reference_id, format: { 
    with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
    message: "must be a valid UUID"
  }, allow_blank: true
end
```

## Debugging

### Useful Console Commands

```ruby
# Check UUID version for a record
record = BlogPost.first
puts record.id.split('-')[2][0] # Should be "7"

# Verify chronological ordering
posts = BlogPost.limit(5).order(:id)
puts posts.map(&:id) # Should be in chronological order

# Check database column type
ActiveRecord::Base.connection.columns('blog_posts').find { |c| c.name == 'id' }.sql_type
# Should return "uuid"

# Verify all models have UUID primary key
ApplicationRecord.descendants.select(&:table_exists?).each do |model|
  pk_column = model.columns_hash[model.primary_key]
  puts "#{model.name}: #{pk_column.sql_type}"
end
```

### Development Tools

```ruby
# Add to development console helpers
def uuid_info(uuid_string)
  parts = uuid_string.split('-')
  version = parts[2][0].to_i(16)
  
  puts "UUID: #{uuid_string}"
  puts "Version: #{version}"
  puts "Timestamp portion: #{parts[0]}#{parts[1]}"
  puts "Is UUIDv7?: #{version == 7}"
end

# Usage in console
uuid_info(User.first.id)
```

---

**Quick Reference**:
- ✅ All models automatically use UUIDv7
- ✅ Use `type: :uuid` for foreign key references
- ✅ UUIDs work like normal primary keys in code
- ✅ Chronologically sortable by ID
- ✅ No special configuration needed for new models