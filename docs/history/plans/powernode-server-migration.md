> **ARCHIVED 2026-05-01** — Preserved for historical context. See [current docs](../../README.md) for current state.

# Powernode System Migration Plan

**Feature Name**: Powernode System
**Menu Category**: System
**Source**: `/home/rett/Drive/Projects/powernode-server` (Rails 4.2.4)
**Target**: `/home/rett/Drive/Projects/powernode-platform` (Rails 8)
**Status**: Planning Phase
**Last Updated**: 2025-12-15

---

## Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [Source Application Analysis](#2-source-application-analysis)
3. [Model Conflict Analysis](#3-model-conflict-analysis)
4. [Migration Strategy](#4-migration-strategy)
5. [Phase Breakdown](#5-phase-breakdown)
6. [Implementation Checklist](#6-implementation-checklist)
7. [Open Questions](#7-open-questions)
8. [Progress Tracking](#8-progress-tracking)
9. [Frontend Navigation Structure](#9-frontend-navigation-structure)

---

## 1. Executive Summary

### Feature Naming
- **Feature Name**: Powernode System
- **Menu Location**: System category in navigation
- **Model Prefix**: `System::` namespace for all new infrastructure models
- **Permission Prefix**: `system.*` for infrastructure permissions

### Key Decisions (FINALIZED)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Scope** | Node infrastructure ONLY | Skip account/plan/user/invitation - already exists |
| **Model Namespace** | `System::` | Clean separation, no conflicts |
| **Agents** | Extend Worker model | Reuse existing authentication infrastructure |
| **Operations** | `System::Operation` | Separate from AuditLog (different purpose) |
| **Providers** | Pluggable architecture | Extensible for any cloud provider |
| **Puppet** | Skip (later enhancement) | Focus on core infrastructure first |
| **Pages** | Skip entirely | Not needed for this implementation |
| **File Storage** | Use FileObject/FileStorage | Existing infrastructure handles versioning |
| **Data Migration** | Start fresh | No legacy data to migrate |
| **Plan Limits** | Add to limits JSON | `node_limit`, `instance_limit` in Plan.limits |
| **User Fields** | Skip | authorized_keys/preferences not needed |

### Source Application Overview
The powernode-server is a **node infrastructure provisioning and lifecycle management platform** built on Rails 4.2.4. It provides:

- **Node Management**: Physical and cloud-based node provisioning
- **Cloud Provider Integration**: AWS and OpenStack support
- **Configuration Management**: Puppet module integration
- **Template System**: Node templates with platform/architecture hierarchy
- **Multi-tenant Architecture**: Account-scoped resources with delegation

### Key Statistics
| Metric | Source (powernode-server) | Target (powernode-platform) |
|--------|---------------------------|----------------------------|
| Rails Version | 4.2.4 | 8.x |
| Total Models | 41 | 180+ |
| Controllers | 31 | TBD |
| Primary Key Type | UUID v1 | UUID v7 |
| Authentication | Devise | Custom JWT |
| Authorization | CanCan (role-based) | Permission-based |
| File Uploads | Paperclip | ActiveStorage |
| Encryption | attr_encrypted | ActiveRecord Encryption |

### Migration Complexity Assessment
- **High Complexity**: Authentication/Authorization refactoring
- **Medium Complexity**: Model associations, file upload migration
- **Low Complexity**: New models without conflicts

---

## 2. Source Application Analysis

### 2.1 Model Inventory (41 Models)

#### Core Account & User Models
| Model | Associations | Migration Status |
|-------|--------------|------------------|
| `User` | belongs_to: account; has_many: account_delegations, accounts (through), invitation | ⚠️ CONFLICT |
| `Account` | belongs_to: agent, owner (User), plan; has_many: users, nodes, providers, etc. | ⚠️ CONFLICT |
| `Plan` | belongs_to: account; has_many: accounts, pages | ⚠️ CONFLICT |
| `Invitation` | belongs_to: account, user | ⚠️ CONFLICT |
| `AccountDelegation` | belongs_to: account, user | ⚠️ CONFLICT |
| `CreditCard` | Stripe integration | ⚠️ REPLACED BY PaymentMethod |

#### Node Infrastructure Models (NEW - No Conflicts)
| Model | Associations | Purpose |
|-------|--------------|---------|
| `Node` | belongs_to: account, agent, node_template; has_many: node_instances, operations | Core node entity |
| `NodeInstance` | belongs_to: node, provider_*, has_many: node_modules, operations | Cloud/physical instance |
| `NodeModule` | belongs_to: account, node_platform; has_many: dependencies, subscriptions | Configuration module |
| `NodeTemplate` | belongs_to: account, node_platform; has_many: nodes, module_subscriptions | Node blueprint |
| `NodePlatform` | belongs_to: account, node_architecture, *_script; has_many: node_modules, templates | OS/platform definition |
| `NodeArchitecture` | belongs_to: account; has_many: node_platforms | System architecture |
| `NodeScript` | belongs_to: account | Build/init/sync scripts |
| `NodeModuleCategory` | belongs_to: account; has_many: node_modules | Module categorization |
| `NodeModuleCopyPath` | belongs_to: account | Module deployment paths |
| `NodeModuleSubscription` | belongs_to: node, node_module | Node-module join |
| `NodeModuleDependency` | belongs_to: node_module, dependency | Module dependencies |
| `NodeMountPoint` | belongs_to: account, node_module | Filesystem mounts |
| `NodeMountPointSubscription` | belongs_to: node_instance, node_mount_point | Instance-mount join |
| `NodeTemplateModuleSubscription` | belongs_to: node_template, node_module | Template-module join |
| `NodeModulePuppetModuleSubscription` | belongs_to: node_module, puppet_module | Module-puppet join |

#### Provider & Cloud Models (NEW - No Conflicts)
| Model | Associations | Purpose |
|-------|--------------|---------|
| `Provider` | belongs_to: account; has_many: provider_regions | Cloud provider (AWS/OpenStack) |
| `ProviderRegion` | belongs_to: account, provider; has_many: zones, networks | Geographic region |
| `ProviderAvailabilityZone` | belongs_to: account, provider_region | Availability zone |
| `ProviderConnection` | belongs_to: account; encrypted: secret_key | Provider credentials |
| `ProviderInstanceType` | belongs_to: account; has_many: region_subscriptions | Compute instance types |
| `ProviderNetwork` | belongs_to: account, provider_region; has_many: subnets | Virtual network |
| `ProviderNetworkSubnet` | belongs_to: provider_network, availability_zone | Network subnet |
| `ProviderVolume` | belongs_to: account, region, volume_type; has_many: members | Storage volume |
| `ProviderVolumeType` | belongs_to: account, mount_script | Storage type |
| `ProviderVolumeMember` | belongs_to: provider_volume, account | Volume attachment |
| `ProviderVolumeSnapshot` | belongs_to: provider_volume | Volume snapshot |
| `ProviderRegionInstanceTypeSubscription` | Join table | Region-instance type |
| `ProviderRegionVolumeTypeSubscription` | Join table | Region-volume type |

#### Puppet & Content Models (NEW - No Conflicts)
| Model | Associations | Purpose |
|-------|--------------|---------|
| `PuppetModule` | belongs_to: account; has_many: puppet_resources | Puppet module |
| `PuppetResource` | belongs_to: puppet_module | Puppet resource |

#### Operations & Utility Models
| Model | Associations | Migration Status |
|-------|--------------|------------------|
| `Operation` | belongs_to: account, operable (polymorphic) | ⚠️ SIMILAR TO AuditLog |
| `Agent` | belongs_to: account; has_many: accounts | ⚠️ CONFLICTS WITH AiAgent |
| `Page` | belongs_to: account, pageable (polymorphic) | ⚠️ CONFLICT |
| `PageResource` | belongs_to: page | ⚠️ CONFLICT |
| `Ability` | CanCan authorization | ⚠️ REPLACED BY Permission |

### 2.2 Database Schema Comparison

#### ID Strategy
| Aspect | Source | Target | Migration Path |
|--------|--------|--------|----------------|
| Primary Key | UUID v1 (`uuid_generate_v1()`) | UUID v7 | Generate new UUIDv7 on import |
| Foreign Keys | UUID references | UUID references | Maintain referential integrity |
| Indexes | Standard Rails | Optimized for UUIDv7 | Recreate during migration |

#### Encrypted Fields
| Source Field | Encryption Method | Target Equivalent |
|--------------|-------------------|-------------------|
| Node.ssh_key | attr_encrypted (IV + salt) | ActiveRecord Encryption |
| Node.ssh_host_key | attr_encrypted | ActiveRecord Encryption |
| NodeInstance.key | attr_encrypted | ActiveRecord Encryption |
| ProviderConnection.secret_key | attr_encrypted | ActiveRecord Encryption |
| Agent.encrypted_key | SCrypt::Password | ActiveRecord Encryption |

#### JSON Columns
| Model | Column | Content | Notes |
|-------|--------|---------|-------|
| User | roles | Array of role strings | Convert to UserRole joins |
| User | authorized_keys | SSH keys | Move to dedicated model? |
| User | preferences | User settings | Merge with target User |
| Plan | default_roles | Role assignments | Convert to permissions |
| Plan | options | Feature flags | Map to Plan.features |
| Account | (various) | Settings | Merge with Account.settings |
| NodeModule | mask, file_spec, package_spec, dependency_spec | Specs | Keep as JSON |
| ProviderRegion | capabilities | Region features | Keep as JSON |

### 2.3 Authorization Model Comparison

#### Source (CanCan Role-Based)
```ruby
# User roles (JSON array)
["global_admin", "account_admin", "node_manager", "provider_publisher"]

# Ability.rb patterns
can :manage, :all if user.has_role?(:global_admin)
can :manage, Node if user.has_any_role?(:node_admin, :node_manager)
can :read, Node if user.has_role?(:node_publisher)
```

#### Target (Permission-Based)
```ruby
# Permission format: resource.action
["nodes.create", "nodes.read", "nodes.update", "nodes.delete", "nodes.manage"]

# Controller pattern
before_action -> { authorize_permission!('nodes.manage') }
```

#### Role-to-Permission Mapping Required
| Source Role | Target Permissions |
|-------------|-------------------|
| `global_admin` | `system.admin` (grants all) |
| `account_admin` | `accounts.manage`, `users.manage`, `billing.manage` |
| `account_manager` | `accounts.read`, `billing.read`, `users.read` |
| `node_admin` | `nodes.manage`, `node_instances.manage`, `node_modules.manage` |
| `node_manager` | `nodes.create`, `nodes.read`, `nodes.update`, `node_instances.*` |
| `node_publisher` | `nodes.read`, `node_modules.read` |
| `provider_admin` | `providers.manage`, `provider_regions.manage`, `provider_connections.manage` |
| `provider_manager` | `providers.*` (except delete) |
| `provider_publisher` | `providers.read`, `provider_regions.read` |
| `puppet_admin` | `puppet_modules.manage`, `puppet_resources.manage` |
| `puppet_manager` | `puppet_modules.*` |
| `puppet_publisher` | `puppet_modules.read` |

### 2.4 Controller Analysis

#### Source Controllers to Migrate (31 total)
| Controller | Actions | Priority | Notes |
|------------|---------|----------|-------|
| `api/agent_v1/agent_api_controller` | RESTful + file ops | HIGH | Agent communication API |
| `api/node_v1/node_api_controller` | Node self-service | HIGH | Node bootstrapping |
| `nodes_controller` | CRUD + control | HIGH | Core node management |
| `node_instances_controller` | Edit/Show/Update | HIGH | Instance management |
| `node_modules_controller` | CRUD + deps + download | HIGH | Module management |
| `node_templates_controller` | CRUD + import/export | MEDIUM | Template management |
| `node_platforms_controller` | CRUD | MEDIUM | Platform management |
| `node_architectures_controller` | CRUD + download | MEDIUM | Architecture management |
| `node_scripts_controller` | CRUD | MEDIUM | Script management |
| `node_module_categories_controller` | CRUD | LOW | Category management |
| `node_module_copy_paths_controller` | CRUD | LOW | Copy path management |
| `node_mount_points_controller` | CRUD | LOW | Mount point management |
| `providers_controller` | CRUD | HIGH | Provider management |
| `provider_regions_controller` | CRUD | HIGH | Region management |
| `provider_connections_controller` | CRUD | HIGH | Connection management |
| `provider_availability_zones_controller` | CRUD | MEDIUM | Zone management |
| `provider_instance_types_controller` | CRUD | MEDIUM | Instance types |
| `provider_networks_controller` | CRUD | MEDIUM | Network management |
| `provider_network_subnets_controller` | CRUD | MEDIUM | Subnet management |
| `provider_volumes_controller` | CRUD | MEDIUM | Volume management |
| `provider_volume_types_controller` | CRUD | LOW | Volume types |
| `operations_controller` | CRUD + control | HIGH | Operation tracking |
| `puppet_modules_controller` | CRUD | MEDIUM | Puppet modules |
| `agents_controller` | CRUD | HIGH | Agent management |
| `accounts_controller` | Billing + delegation | SKIP | Use existing |
| `users_controller` | CRUD | SKIP | Use existing |
| `invitations_controller` | CRUD | SKIP | Use existing |
| `plans_controller` | CRUD | SKIP | Use existing |
| `pages_controller` | CRUD + resources | EVALUATE | May extend existing |
| `registrations_controller` | Devise custom | SKIP | Use existing auth |

---

## 3. Model Conflict Analysis

### 3.1 Direct Name Conflicts

| Conflicting Model | Source Purpose | Target Purpose | Resolution Options |
|-------------------|----------------|----------------|-------------------|
| **User** | Devise auth, roles (JSON), authorized_keys | JWT auth, permission-based, 2FA | **A)** Extend target User with source fields **B)** Keep separate (rename source) |
| **Account** | Multi-tenant container, Stripe integration, agent association | Multi-tenant container, settings, termination workflow | **A)** Extend target Account **B)** Merge carefully |
| **Plan** | Billing plan with limits (node/user/instance), Stripe sync | Billing plan with features/limits JSON, trial support | **A)** Extend target Plan with node limits **B)** Keep separate |
| **Invitation** | User invitation with recipient email | User invitation with token, sent_at, accepted_at | **A)** Extend target Invitation **B)** Merge |
| **AccountDelegation** | User delegation with expiration | User delegation with expiration | **A)** Use existing (nearly identical) |
| **Page** | Polymorphic content pages with resources | CMS pages with author, published_at | **A)** Extend with polymorphic support **B)** Rename source to `ResourcePage` |
| **PageResource** | Media attachments to pages | Does not exist | **A)** Add to target **B)** Use FileObject instead |

### 3.2 Semantic Conflicts

| Source Model | Similar Target Model | Difference | Resolution |
|--------------|---------------------|------------|------------|
| **Agent** | **AiAgent** | Infrastructure agent vs AI agent | **Rename source to `InfraAgent`** |
| **Operation** | **AuditLog** | Task tracking vs change tracking | **Keep both - different purposes** |
| **CreditCard** | **PaymentMethod** | Single card vs multiple methods | **Use PaymentMethod** |
| **Ability** | **Permission** | CanCan vs custom | **Convert to permissions** |

### 3.3 Association Conflicts

#### User Associations
| Source Association | Target Association | Conflict Level |
|--------------------|-------------------|----------------|
| `belongs_to :account` | `belongs_to :account` | ✅ Compatible |
| `has_many :account_delegations` | `has_many :account_delegations` | ✅ Compatible |
| `has_one :invitation` | (none) | ⚠️ Add to target |
| `roles` (JSON) | `has_many :roles through: :user_roles` | ❌ Convert |
| `authorized_keys` (JSON) | (none) | ⚠️ New field or model |
| `preferences` (JSON) | (none) | ⚠️ Add to target |

#### Account Associations
| Source Association | Target Association | Conflict Level |
|--------------------|-------------------|----------------|
| `belongs_to :owner (User)` | (none) | ⚠️ Add to target |
| `belongs_to :agent` | (none - different Agent) | ⚠️ Add as infra_agent |
| `belongs_to :plan` | `has_one :subscription -> plan` | ⚠️ Different pattern |
| `has_many :nodes, providers, etc.` | (none) | ✅ Add new |
| State machine (trialing/active/delinquent) | (none - uses Subscription) | ⚠️ Evaluate merge |

#### Plan Associations
| Source Association | Target Association | Conflict Level |
|--------------------|-------------------|----------------|
| `belongs_to :account` | (none) | ⚠️ Evaluate need |
| `user_limit, node_limit, instance_limit` | `limits` (JSON) | ⚠️ Merge into JSON |
| `default_roles` (JSON) | (none) | ⚠️ Convert to permissions |
| Stripe fields | Stripe fields | ✅ Compatible |

---

## 4. Migration Strategy

### 4.1 Recommended Approach

**Strategy: Incremental Extension**

1. **Extend existing models** where overlap exists (User, Account, Plan, Invitation)
2. **Create new models** for unique functionality (Node*, Provider*, Puppet*)
3. **Rename conflicting models** where semantics differ (Agent → InfraAgent)
4. **Convert authorization** from roles to permissions
5. **Migrate file uploads** from Paperclip to ActiveStorage
6. **Modernize encryption** from attr_encrypted to ActiveRecord Encryption

### 4.2 Model Naming Decisions

| Source Model | Target Model Name | Rationale |
|--------------|-------------------|-----------|
| User | User (extended) | Core model, extend with new fields |
| Account | Account (extended) | Core model, extend with new associations |
| Plan | Plan (extended) | Core model, add node/instance limits |
| Invitation | Invitation (extended) | Nearly identical, minor extension |
| AccountDelegation | AccountDelegation | Use existing |
| Agent | **InfraAgent** | Avoid conflict with AiAgent |
| Page | **NodePage** or extend Page | TBD - depends on polymorphic needs |
| PageResource | **NodePageResource** or FileObject | TBD |
| Operation | **InfraOperation** | Different from AuditLog |
| CreditCard | (skip - use PaymentMethod) | Redundant |
| Ability | (skip - convert to Permission) | Different pattern |
| Node | Node (new) | No conflict |
| NodeInstance | NodeInstance (new) | No conflict |
| (all other Node* models) | (same names) | No conflicts |
| Provider | Provider (new) | No conflict |
| (all other Provider* models) | (same names) | No conflicts |
| PuppetModule | PuppetModule (new) | No conflict |
| PuppetResource | PuppetResource (new) | No conflict |

### 4.3 Permission Mapping

#### New Permission Categories
```
# Node Management
nodes.create, nodes.read, nodes.update, nodes.delete, nodes.manage
node_instances.create, node_instances.read, node_instances.update, node_instances.delete, node_instances.manage
node_modules.create, node_modules.read, node_modules.update, node_modules.delete, node_modules.manage
node_templates.create, node_templates.read, node_templates.update, node_templates.delete, node_templates.manage
node_platforms.create, node_platforms.read, node_platforms.update, node_platforms.delete, node_platforms.manage
node_architectures.create, node_architectures.read, node_architectures.update, node_architectures.delete, node_architectures.manage
node_scripts.create, node_scripts.read, node_scripts.update, node_scripts.delete, node_scripts.manage

# Provider Management
providers.create, providers.read, providers.update, providers.delete, providers.manage
provider_regions.create, provider_regions.read, provider_regions.update, provider_regions.delete, provider_regions.manage
provider_connections.create, provider_connections.read, provider_connections.update, provider_connections.delete, provider_connections.manage
provider_networks.create, provider_networks.read, provider_networks.update, provider_networks.delete, provider_networks.manage
provider_volumes.create, provider_volumes.read, provider_volumes.update, provider_volumes.delete, provider_volumes.manage

# Puppet Management
puppet_modules.create, puppet_modules.read, puppet_modules.update, puppet_modules.delete, puppet_modules.manage
puppet_resources.create, puppet_resources.read, puppet_resources.update, puppet_resources.delete, puppet_resources.manage

# Infrastructure Operations
infra_operations.create, infra_operations.read, infra_operations.update, infra_operations.delete, infra_operations.manage
infra_agents.create, infra_agents.read, infra_agents.update, infra_agents.delete, infra_agents.manage
```

---

## 5. Phase Breakdown

### Phase 1: Foundation (Week 1-2)
**Goal**: Prepare target platform for migration

#### 1.1 Extend Existing Models
- [ ] Add infrastructure fields to User model
- [ ] Add infrastructure associations to Account model
- [ ] Add node/instance limits to Plan model
- [ ] Extend Invitation model if needed

#### 1.2 Create Infrastructure Agent Model
- [ ] Create `InfraAgent` model (renamed from Agent)
- [ ] Add InfraAgent-Account associations
- [ ] Implement authentication mechanism

#### 1.3 Create Permission Seeds
- [ ] Define all new permissions in seeds
- [ ] Create role templates for infrastructure management
- [ ] Test permission enforcement

### Phase 2: Node Infrastructure (Week 3-4)
**Goal**: Implement core node management

#### 2.1 Node Core Models
- [ ] Create Node model with encrypted fields
- [ ] Create NodeInstance model with encrypted key
- [ ] Create NodeTemplate model
- [ ] Create NodePlatform model
- [ ] Create NodeArchitecture model
- [ ] Create NodeScript model

#### 2.2 Node Module System
- [ ] Create NodeModule model with versioning
- [ ] Create NodeModuleCategory model
- [ ] Create NodeModuleCopyPath model
- [ ] Create NodeModuleSubscription join model
- [ ] Create NodeModuleDependency model
- [ ] Create NodeMountPoint model
- [ ] Create NodeMountPointSubscription join model
- [ ] Create NodeTemplateModuleSubscription join model

#### 2.3 Node Controllers & API
- [ ] Create Api::V1::NodesController
- [ ] Create Api::V1::NodeInstancesController
- [ ] Create Api::V1::NodeModulesController
- [ ] Create Api::V1::NodeTemplatesController
- [ ] Create remaining node controllers
- [ ] Create agent API namespace

### Phase 3: Provider Infrastructure (Week 5-6)
**Goal**: Implement cloud provider integration

#### 3.1 Provider Core Models
- [ ] Create Provider model
- [ ] Create ProviderRegion model
- [ ] Create ProviderAvailabilityZone model
- [ ] Create ProviderConnection model (encrypted)
- [ ] Create ProviderInstanceType model

#### 3.2 Provider Network Models
- [ ] Create ProviderNetwork model
- [ ] Create ProviderNetworkSubnet model

#### 3.3 Provider Storage Models
- [ ] Create ProviderVolume model
- [ ] Create ProviderVolumeType model
- [ ] Create ProviderVolumeMember model
- [ ] Create ProviderVolumeSnapshot model
- [ ] Create region subscription join tables

#### 3.4 Provider Controllers
- [ ] Create Api::V1::ProvidersController
- [ ] Create Api::V1::ProviderRegionsController
- [ ] Create remaining provider controllers

### Phase 4: Puppet & Operations (Week 7)
**Goal**: Implement Puppet integration and operations tracking

#### 4.1 Puppet Models
- [ ] Create PuppetModule model
- [ ] Create PuppetResource model
- [ ] Create NodeModulePuppetModuleSubscription join model

#### 4.2 Operations Model
- [ ] Create InfraOperation model (polymorphic)
- [ ] Implement status state machine
- [ ] Add scheduling support

#### 4.3 Controllers
- [ ] Create Api::V1::PuppetModulesController
- [ ] Create Api::V1::InfraOperationsController

### Phase 5: File Migration & ActiveStorage (Week 8)
**Goal**: Migrate Paperclip attachments to ActiveStorage

#### 5.1 ActiveStorage Setup
- [ ] Configure ActiveStorage for infrastructure files
- [ ] Create storage service configurations

#### 5.2 File Attachment Migration
- [ ] Migrate NodeArchitecture attachments (kernel, ramdisk, image)
- [ ] Migrate NodeInstance attachments (image)
- [ ] Migrate NodeModule attachments (data)
- [ ] Migrate PuppetModule attachments (data)
- [ ] Migrate PageResource attachments (data)

### Phase 6: Frontend Integration (Week 9-10)
**Goal**: Create React frontend components

#### 6.1 Node Management UI
- [ ] Create node list/detail pages
- [ ] Create node instance management
- [ ] Create node module management
- [ ] Create node template management

#### 6.2 Provider Management UI
- [ ] Create provider configuration pages
- [ ] Create region/zone management
- [ ] Create network configuration UI
- [ ] Create volume management UI

#### 6.3 Operations UI
- [ ] Create operations dashboard
- [ ] Create operation detail/control views

### Phase 7: Data Migration & Testing (Week 11-12)
**Goal**: Migrate existing data and comprehensive testing

#### 7.1 Data Migration Scripts
- [ ] Create migration rake tasks
- [ ] Handle UUID conversion (v1 → v7)
- [ ] Migrate encrypted fields
- [ ] Migrate file attachments
- [ ] Validate data integrity

#### 7.2 Testing
- [ ] Unit tests for all new models
- [ ] Integration tests for controllers
- [ ] API contract tests
- [ ] Permission enforcement tests
- [ ] End-to-end tests

---

## 6. Implementation Checklist

### Models to Create (New)
- [ ] InfraAgent (renamed from Agent)
- [ ] InfraOperation (renamed from Operation)
- [ ] Node
- [ ] NodeInstance
- [ ] NodeModule
- [ ] NodeModuleCategory
- [ ] NodeModuleCopyPath
- [ ] NodeModuleSubscription
- [ ] NodeModuleDependency
- [ ] NodeModulePuppetModuleSubscription
- [ ] NodeMountPoint
- [ ] NodeMountPointSubscription
- [ ] NodePlatform
- [ ] NodeArchitecture
- [ ] NodeScript
- [ ] NodeTemplate
- [ ] NodeTemplateModuleSubscription
- [ ] Provider
- [ ] ProviderRegion
- [ ] ProviderAvailabilityZone
- [ ] ProviderConnection
- [ ] ProviderInstanceType
- [ ] ProviderNetwork
- [ ] ProviderNetworkSubnet
- [ ] ProviderVolume
- [ ] ProviderVolumeType
- [ ] ProviderVolumeMember
- [ ] ProviderVolumeSnapshot
- [ ] ProviderRegionInstanceTypeSubscription
- [ ] ProviderRegionVolumeTypeSubscription
- [ ] PuppetModule
- [ ] PuppetResource
- [ ] NodePage (if needed - TBD)
- [ ] NodePageResource (if needed - TBD)

### Models to Extend (Existing)
- [ ] User - add authorized_keys, preferences
- [ ] Account - add owner_id, infra_agent association
- [ ] Plan - add node_limit, instance_limit to limits JSON

### Controllers to Create
- [ ] Api::V1::NodesController
- [ ] Api::V1::NodeInstancesController
- [ ] Api::V1::NodeModulesController
- [ ] Api::V1::NodeModuleCategoriesController
- [ ] Api::V1::NodeModuleCopyPathsController
- [ ] Api::V1::NodeMountPointsController
- [ ] Api::V1::NodePlatformsController
- [ ] Api::V1::NodeArchitecturesController
- [ ] Api::V1::NodeScriptsController
- [ ] Api::V1::NodeTemplatesController
- [ ] Api::V1::ProvidersController
- [ ] Api::V1::ProviderRegionsController
- [ ] Api::V1::ProviderAvailabilityZonesController
- [ ] Api::V1::ProviderConnectionsController
- [ ] Api::V1::ProviderInstanceTypesController
- [ ] Api::V1::ProviderNetworksController
- [ ] Api::V1::ProviderNetworkSubnetsController
- [ ] Api::V1::ProviderVolumesController
- [ ] Api::V1::ProviderVolumeTypesController
- [ ] Api::V1::PuppetModulesController
- [ ] Api::V1::InfraAgentsController
- [ ] Api::V1::InfraOperationsController
- [ ] Api::AgentV1::* (Agent API namespace)
- [ ] Api::NodeV1::* (Node API namespace)

### Permissions to Create
- [ ] Node permissions (7)
- [ ] NodeInstance permissions (7)
- [ ] NodeModule permissions (7)
- [ ] NodeTemplate permissions (7)
- [ ] NodePlatform permissions (7)
- [ ] NodeArchitecture permissions (7)
- [ ] NodeScript permissions (7)
- [ ] Provider permissions (7)
- [ ] ProviderRegion permissions (7)
- [ ] ProviderConnection permissions (7)
- [ ] ProviderNetwork permissions (7)
- [ ] ProviderVolume permissions (7)
- [ ] PuppetModule permissions (7)
- [ ] InfraAgent permissions (7)
- [ ] InfraOperation permissions (7)

### Migrations to Create
- [ ] Add infrastructure fields to users
- [ ] Add infrastructure fields to accounts
- [ ] Add infrastructure limits to plans
- [ ] Create infra_agents table
- [ ] Create infra_operations table
- [ ] Create nodes table
- [ ] Create node_instances table
- [ ] Create node_modules table
- [ ] Create node_module_categories table
- [ ] Create node_module_copy_paths table
- [ ] Create node_module_subscriptions table
- [ ] Create node_module_dependencies table
- [ ] Create node_mount_points table
- [ ] Create node_mount_point_subscriptions table
- [ ] Create node_platforms table
- [ ] Create node_architectures table
- [ ] Create node_scripts table
- [ ] Create node_templates table
- [ ] Create node_template_module_subscriptions table
- [ ] Create node_module_puppet_module_subscriptions table
- [ ] Create providers table
- [ ] Create provider_regions table
- [ ] Create provider_availability_zones table
- [ ] Create provider_connections table
- [ ] Create provider_instance_types table
- [ ] Create provider_networks table
- [ ] Create provider_network_subnets table
- [ ] Create provider_volumes table
- [ ] Create provider_volume_types table
- [ ] Create provider_volume_members table
- [ ] Create provider_volume_snapshots table
- [ ] Create provider_region_instance_type_subscriptions table
- [ ] Create provider_region_volume_type_subscriptions table
- [ ] Create puppet_modules table
- [ ] Create puppet_resources table
- [ ] Seed new permissions

---

## 7. Open Questions

### CRITICAL - Must Answer Before Implementation

#### Q1: User Model Extension
**Question**: How should we handle the `authorized_keys` field from the source User model?
**Options**:
- A) Add as JSON column to target User model
- B) Create separate `UserAuthorizedKey` model with has_many association
- C) Skip - not needed for this deployment

**Current Answer**: _PENDING_

---

#### Q2: Account Owner Association
**Question**: The source Account `belongs_to :owner (User)`. Should we add this to the target?
**Options**:
- A) Yes - add `owner_id` foreign key to Account
- B) No - use first user with `accounts.manage` permission
- C) Create `AccountOwnership` join table for flexibility

**Current Answer**: _PENDING_

---

#### Q3: Plan Limits Location
**Question**: Source Plan has `user_limit`, `node_limit`, `instance_limit` as separate columns. Target Plan has `limits` JSON. How to reconcile?
**Options**:
- A) Add to existing `limits` JSON: `{ ..., "node_limit": 10, "instance_limit": 50 }`
- B) Add as separate columns for query performance
- C) Create PlanLimit model for normalization

**Current Answer**: _PENDING_

---

#### Q4: Page Model Strategy
**Question**: Source Page is polymorphic (`pageable_type`, `pageable_id`). Target Page is CMS-focused. How to handle?
**Options**:
- A) Extend target Page with polymorphic support
- B) Create new `ResourcePage` model for infrastructure pages
- C) Skip - use different documentation approach

**Current Answer**: _PENDING_

---

#### Q5: Agent Naming
**Question**: Source has `Agent` for infrastructure agents. Target has `AiAgent` for AI agents. What to name the infrastructure agent?
**Options**:
- A) `InfraAgent` (infrastructure agent)
- B) `NodeAgent` (node-specific agent)
- C) `ProvisioningAgent` (provisioning-focused)
- D) `Agent` with `agent_type` column to differentiate

**Current Answer**: _PENDING_

---

#### Q6: Operation vs AuditLog
**Question**: Source `Operation` tracks infrastructure tasks with status/progress. Target `AuditLog` tracks data changes. Relationship?
**Options**:
- A) Create separate `InfraOperation` model (different purpose)
- B) Extend AuditLog with operation features
- C) Create `Job` model that links to AuditLog entries

**Current Answer**: _PENDING_

---

#### Q7: Provider Varieties
**Question**: Source supports AWS and OpenStack. Should we add more providers?
**Options**:
- A) Keep AWS and OpenStack only
- B) Add GCP, Azure, DigitalOcean support
- C) Make provider types pluggable/extensible

**Current Answer**: _PENDING_

---

#### Q8: Encryption Strategy
**Question**: Source uses `attr_encrypted` with per-attribute IV. Target uses `ActiveRecord::Encryption`. Migration approach?
**Options**:
- A) Re-encrypt all data during migration (breaking change)
- B) Support both encryption methods temporarily
- C) Store source data as-is, encrypt only new records

**Current Answer**: _PENDING_

---

#### Q9: File Storage Strategy
**Question**: Source uses Paperclip with local filesystem + S3. Target uses ActiveStorage. Migration approach?
**Options**:
- A) Migrate all files to ActiveStorage during migration
- B) Keep legacy files in place, use ActiveStorage for new
- C) Use hybrid approach with migration over time

**Current Answer**: _PENDING_

---

#### Q10: API Versioning
**Question**: Source has `api/agent_v1` and `api/node_v1` namespaces. How to integrate?
**Options**:
- A) Create under existing `Api::V1` namespace
- B) Create separate `Api::AgentV1` and `Api::NodeV1` namespaces
- C) Create `Api::V1::Agent::*` and `Api::V1::Node::*` nested namespaces

**Current Answer**: _PENDING_

---

### MEDIUM PRIORITY

#### Q11: Account State Machine
**Question**: Source Account has AASM state machine (trialing → active ↔ delinquent). Target uses Subscription states. Reconcile?

#### Q12: Authorization Pattern
**Question**: Should new controllers use the existing authorization pattern or create an infrastructure-specific concern?

#### Q13: Devise Fields Migration
**Question**: Source User has Devise fields (confirmable, lockable, etc.). Target has custom JWT. Migrate Devise fields or skip?

#### Q14: Versioning System
**Question**: Source NodeModule uses `acts_as_versioned`. Implement in target or use alternative?

---

## 8. Progress Tracking

### Overall Status
| Phase | Status | Progress | Notes |
|-------|--------|----------|-------|
| Planning | 🟡 In Progress | 60% | Awaiting conflict resolution answers |
| Phase 1: Foundation | ⬜ Not Started | 0% | |
| Phase 2: Node Infrastructure | ⬜ Not Started | 0% | |
| Phase 3: Provider Infrastructure | ⬜ Not Started | 0% | |
| Phase 4: Puppet & Operations | ⬜ Not Started | 0% | |
| Phase 5: File Migration | ⬜ Not Started | 0% | |
| Phase 6: Frontend Integration | ⬜ Not Started | 0% | |
| Phase 7: Data Migration & Testing | ⬜ Not Started | 0% | |

### Decision Log
| Date | Question | Decision | Rationale |
|------|----------|----------|-----------|
| 2025-12-15 | Initial analysis | Complete | Comprehensive source/target analysis |
| | | | |

### Risk Register
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data loss during encryption migration | Medium | High | Test thoroughly, maintain backups |
| Permission mapping gaps | Low | Medium | Comprehensive mapping document |
| File attachment corruption | Low | High | Validate checksums during migration |
| API compatibility breaks | Medium | Medium | Version APIs, maintain backwards compat |

---

## 9. Frontend Navigation Structure

### Menu Category: System

The Powernode System features will be organized under the "System" navigation category.

#### Proposed Navigation Structure
```
System (Category)
├── Nodes
│   ├── All Nodes (list)
│   ├── Node Details (detail)
│   ├── Node Instances (sub-section)
│   └── Node Templates (sub-section)
├── Modules
│   ├── All Modules (list)
│   ├── Module Categories
│   └── Mount Points
├── Platforms
│   ├── All Platforms (list)
│   └── Architectures
├── Scripts (list)
├── Providers
│   ├── All Providers (list)
│   ├── Regions
│   ├── Connections
│   └── Networks
├── Storage
│   ├── Volumes
│   ├── Volume Types
│   └── Snapshots
├── Puppet
│   ├── Modules
│   └── Resources
├── Agents (list)
└── Operations (list/dashboard)
```

#### Permission-Based Menu Visibility
Each menu item will require appropriate `system.*` permissions:
- `system.nodes.read` - View nodes menu
- `system.providers.read` - View providers menu
- `system.puppet.read` - View puppet menu
- `system.operations.read` - View operations menu
- `system.agents.read` - View agents menu

#### Model Namespace Convention
To maintain organization, models will use the `System::` namespace:
- `System::Node`
- `System::NodeInstance`
- `System::Provider`
- `System::Agent` (instead of InfraAgent)
- `System::Operation`

This keeps all Powernode System models organized and prevents conflicts with existing models.

---

## Appendix A: Source Schema Reference

See source analysis for complete schema details.

## Appendix B: Target Schema Reference

See target inventory for complete schema details.

## Appendix C: Migration Scripts

_To be added during implementation_

---

**Document Version**: 1.0
**Created**: 2025-12-15
**Author**: Claude Code Migration Assistant
