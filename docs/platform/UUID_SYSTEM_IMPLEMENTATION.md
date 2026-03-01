# UUIDv7 System Implementation

## Implementation Status: COMPLETE

**Date Completed**: August 27, 2025
**Models Using UUIDv7**: 327+ (all models)
**Database Schema**: Native PostgreSQL UUID types
**Default Behavior**: All models inherit UUIDv7 generation via ApplicationRecord

## Overview

Powernode uses UUIDv7 (UUID Version 7) as the default primary key format for all database models. This provides chronologically sortable, globally unique identifiers with optimal database performance.

## Key Components

### 1. UuidGenerator Concern

- **Location**: `app/models/concerns/uuid_generator.rb`
- **Functionality**: Automatic UUIDv7 generation for all new records
- **Integration**: Included in ApplicationRecord by default
- **Dependencies**: UUID7 gem for proper v7 format generation

### 2. ApplicationRecord Integration

- All models automatically inherit UUIDv7 generation
- No configuration required for new models
- Consistent platform standard across all 359 tables

### 3. Database Schema

- **Type**: Native PostgreSQL `uuid` columns (not string-based)
- **Performance**: Optimized for B-tree indexing and sorting
- **Foreign Keys**: All relationships use proper UUID type constraints

## Technical Specifications

### UUID Format

```
UUIDv7: 0198ebd9-6018-7c94-ad91-9eb1cf7745d5
         |--timestamp--| |ver| |----random----|
```

**Benefits**:
- **Chronological Ordering**: Natural creation-time sorting
- **Global Uniqueness**: Collision-resistant across distributed systems
- **Database Performance**: Better index performance than UUIDv4
- **Timestamp Embedded**: Millisecond-precision creation time

### Dependencies

```ruby
# Gemfile
gem 'uuid7', '~> 0.1'
```

## Model Coverage (327+)

### By Namespace

| Namespace | Models | Examples |
|-----------|--------|----------|
| Top-level | 120+ | User, Account, Plan, Subscription, Invoice, Payment, Role, Permission |
| `Ai::` | 135 | Agent, Workflow, Provider, Memory, Knowledge, Skill, Team |
| `Devops::` | 41 | Pipeline, Runner, Repository, Deployment, GitProvider |
| `KnowledgeBase::` | 8 | Article, Category, Tag, Comment, Attachment |
| `FileManagement::` | 7 | FileUpload, StorageBackend |
| `Chat::` | 5 | Conversation, Message, Attachment |
| `Account::` | 3 | Delegation, Setting |
| `DataManagement::` | 3 | RetentionPolicy, SanitizationRule |
| `Database::` | 2 | Connection, QueryHistory |
| `Monitoring::` | 2 | HealthCheck, ServiceStatus |
| `Shared::` | 1 | FeatureGate |

## Developer Quick Reference

- All models automatically use UUIDv7 — no configuration needed
- Use `type: :uuid` for foreign key references in migrations
- IDs are chronologically sortable
- Use `t.references :parent, type: :uuid` in migrations (index included automatically)

## Migration Patterns

```ruby
# New table
create_table :items, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps
end

# Adding UUID column
add_column :items, :external_id, :uuid
```

## Documentation

- [UUID System Architecture](../../server/docs/UUID_SYSTEM_ARCHITECTURE.md) — Technical implementation details
- [UUID Development Guidelines](../../server/docs/UUID_DEVELOPMENT_GUIDELINES.md) — Developer best practices
- [UuidGenerator Concern](../../server/app/models/concerns/uuid_generator.rb) — Source code
