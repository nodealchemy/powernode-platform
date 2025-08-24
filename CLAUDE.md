# CLAUDE.md

Development guidance for **Powernode** subscription platform.

## Project Overview & Architecture

**Powernode** - Subscription lifecycle management platform:
- **Backend**: Rails 8 API (`./server`) - JWT auth, UUID keys, audit logging
- **Frontend**: React TypeScript (`./frontend`) - Theme-aware, Tailwind CSS
- **Worker**: Sidekiq standalone service (`./worker`) - API-only communication
- **Database**: PostgreSQL with consolidated schema
- **Payments**: Stripe, PayPal with PCI compliance
- **Testing**: RSpec (203+ tests), Jest/Cypress

**ALWAYS REFERENCE TODO.md FOR CURRENT PROGRESS AND STATUS**

### Core Models & Relations
- **Account** → User (many), Subscription (one)
- **Subscription** → Plan, Payments, Invoices  
- **User** → Roles (`resource.action` format), Permissions, Invitations

### Git Configuration
- **IMPORTANT**: Clean commit messages without Claude attribution
- Use conventional commits: `feat:`, `fix:`, `docs:`, etc.
- Git-Flow enforced: `develop` → `feature/*` → `release/*` → `main`

## Git-Flow & Semantic Versioning (ENFORCED)

### Git-Flow Model (MANDATORY)
**Current Version**: `0.0.1` → `0.1.0` (next release)

**Branch Structure**:
- `main` - Production releases only (2 PR reviews required)
- `develop` - Integration branch (1 PR review required)
- `feature/ISSUE-description` - New features
- `release/v1.2.0` - Release preparation
- `hotfix/v1.2.1-description` - Production fixes

```bash
# Git-flow commands
git flow feature start ISSUE-feature-name
git flow feature finish ISSUE-feature-name
git flow release start v1.2.0
git flow release finish v1.2.0
git flow hotfix start v1.2.1-critical-fix
git flow hotfix finish v1.2.1-critical-fix
```

### Semantic Versioning (SemVer 2.0.0)
**Format**: `MAJOR.MINOR.PATCH[-PRERELEASE]`

**Version Rules**:
- **MAJOR** (X.0.0): Breaking changes, API incompatibility
- **MINOR** (0.X.0): New features, backward compatible  
- **PATCH** (0.0.X): Bug fixes, backward compatible
- **PRERELEASE**: `alpha`, `beta`, `rc` tags

**Conventional Commits**:
- `feat:` → MINOR version bump
- `fix:` → PATCH version bump
- `feat!:` or `BREAKING CHANGE:` → MAJOR version bump
- `docs:`, `style:`, `refactor:`, `test:`, `chore:` → PATCH version bump

```bash
# Version management
git describe --tags --abbrev=0           # Check current version
npm version patch|minor|major            # Bump version
npm version prerelease --preid=alpha    # Pre-release version

# Examples
feat(auth): implement OAuth2 integration  # MINOR bump
fix(billing): resolve renewal bug         # PATCH bump
feat!: redesign authentication API       # MAJOR bump
```

### Release Process
**Pre-Release Checklist**:
- [ ] All features merged to develop
- [ ] All tests passing (backend + frontend)
- [ ] Security audit completed
- [ ] Performance benchmarks met
- [ ] Documentation updated

**Release Tagging**:
```bash
git tag -a v1.2.0 -m "Release v1.2.0

Features:
- New payment gateway integration
- Enhanced user management

Breaking Changes:
- API endpoint restructuring

Migration Guide:
- Update API calls to new endpoints"
```

**Deployment Strategy**:
- `main` → Production
- `develop` → Staging
- `feature/*` → Development/Preview
- `release/*` → Pre-production testing

**Quality Gates**: Tests pass → Security scans → Performance benchmarks → Manual approval

### Database Schema (CONSOLIDATED)
**CRITICAL**: Streamlined migrations with UUID strategy.

#### Current Structure
1. **20250101000001_create_powernode_schema.rb** - Core platform tables
2. **20250101000002_create_additional_features.rb** - Extended features

**UUID Strategy**: `string :id, limit: 36` (current), `gen_random_uuid()` (new tables)
**Extensions**: `pgcrypto`, `uuid-ossp` enabled

```bash
# Database reset commands
rails db:drop db:create db:migrate db:seed
rm -f db/schema.rb && rails db:migrate  # Fresh start

# CRITICAL: Always update worker token after database reset
rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); 
if worker && worker.token.present?
  File.write('worker/.env', File.read('worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\"))
  puts \"✅ Updated worker/.env with system worker token: #{worker.token[0..10]}...\"
else
  puts \"❌ No system worker token found - check seeds.rb\"
end"
```

**Core Tables**: accounts, users, plans/subscriptions, payments/invoices, workers/volumes, kb_articles, notifications/audit_logs

## Development Workflow

### Process Management (CRITICAL)
**NEVER start servers manually** - Always use management scripts with screen sessions.

```bash
# Essential commands
$POWERNODE_ROOT/scripts/auto-dev.sh ensure    # Start all services
$POWERNODE_ROOT/scripts/auto-dev.sh status    # Health check

# Individual services
backend-manager.sh start|stop|status|logs
worker-manager.sh start|stop|status|start-web|stop-web  
frontend-manager.sh start|stop|status|logs

# Service endpoints
# Backend: http://localhost:3000
# Worker Web: http://localhost:4567/sidekiq  
# Frontend: http://localhost:3002
```

**Claude Auto-Start**: Servers auto-start when user requests testing/development work.
**Startup Sequence**: Backend → Worker → Frontend → Health check

### Development Commands
```bash
# Database with automatic worker token update
cd server && rails db:create db:migrate db:seed && rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); if worker && worker.token.present?; File.write('worker/.env', File.read('worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\")); puts \"✅ Updated worker token\"; end"

# Testing  
cd server && bundle exec rspec        # Backend (203+ tests)
cd frontend && npm test              # Frontend

# Project tracking
# Use TODO.md with: [ ] [🔄] [✅] [❌] [⚠️]
```

### Git Workflow & Cleanup
**Pre-Commit Cleanup (MANDATORY)**:
```bash
find . -name "*.tmp" -o -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.swp" -o -name "*.swo" -o -name "*~" | xargs rm -f 2>/dev/null; cd frontend && rm -rf .next/ dist/ build/ coverage/ .nyc_output/ node_modules/.cache/ && cd ../server && rm -rf tmp/cache/ tmp/pids/ tmp/sessions/ tmp/sockets/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd ../worker && rm -rf tmp/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd .. && git status --porcelain
```

**Commit Pattern**: Complete work → Run cleanup → Test/lint → Commit


## Directory Structure (CRITICAL)

**MANDATORY**: Follow standardized structure - moving files outside conventions is prohibited.

### Project Layout
```
powernode-platform/
├── server/     # Rails 8 API (app/controllers/api/v1/, models/, services/, jobs/, spec/)
├── frontend/   # React TypeScript (src/features/, shared/, pages/, assets/)
├── worker/     # Sidekiq service (app/jobs/, services/, controllers/)
├── scripts/    # Development and deployment scripts
├── docs/       # Project documentation
└── .github/    # GitHub workflows and templates
```

### Frontend Organization (Feature-Based)
```
src/
├── features/           # Business domains (auth/, billing/, users/, analytics/, admin/)
│   └── [feature]/
│       ├── components/ # Feature-specific components
│       ├── hooks/      # Feature-specific hooks  
│       ├── services/   # Feature-specific API calls
│       ├── types/      # Feature-specific TypeScript types
│       └── utils/      # Feature-specific utilities
├── shared/             # Cross-feature reusables
│   ├── components/     # UI primitives (ui/, layout/, forms/, data-display/)
│   ├── hooks/          # Reusable hooks
│   ├── services/       # Shared API services
│   ├── types/          # Global TypeScript types
│   └── utils/          # Utility functions
├── pages/              # Route-based components (public/, app/, admin/)
└── assets/             # Static assets (images/, fonts/, styles/)
```

### File Naming & Import Rules
- **Components**: PascalCase.tsx (UserProfile.tsx)
- **Hooks**: camelCase starting with 'use' (useUserProfile.ts) 
- **Services**: camelCase ending with 'Api' (userApi.ts)
- **Types**: PascalCase (User.ts, ApiResponse.ts)

```typescript
// ✅ CORRECT imports with path aliases
import { Button } from '@/shared/components/ui/Button';
import { useAuth } from '@/features/auth/hooks/useAuth';

// ❌ WRONG - avoid deep relative imports  
import { Button } from '../../../shared/components/ui/Button';
```

### Migration Strategy
Phase 1: Establish structure → Phase 2: Move files by feature → Phase 3: Update imports → Phase 4: Remove old structure

## Enforced Design Patterns (CRITICAL)

### 1. Theme-Aware Styling (MANDATORY)
**NEVER** use hardcoded colors - **ALWAYS** use theme classes for light/dark compatibility.

```typescript
// ❌ FORBIDDEN - Hardcoded colors
'bg-red-50', 'text-green-600', 'bg-white', 'text-black', 'border-gray-300'

// ✅ REQUIRED - Theme classes
'bg-theme-error-background', 'text-theme-success', 'bg-theme-surface', 'text-theme-primary'
```

**Theme Class System**:
- **Status**: `text-theme-success/warning/error/info`, `bg-theme-*-background`, `border-theme-*-border`
- **Base**: `bg-theme-background/surface`, `text-theme-primary/secondary/tertiary`, `border-theme`
- **Interactive**: `bg-theme-interactive-primary`, `text-theme-link`, `border-theme-focus`

**EXCEPTION**: `text-white` is allowed ONLY on colored backgrounds (buttons, badges, interactive elements):
```typescript
// ✅ ALLOWED - text-white on colored backgrounds
'bg-theme-interactive-primary text-white'  // Primary button
'bg-theme-success text-white'              // Success button
'bg-gradient-to-br from-theme-interactive-primary to-theme-success ... text-white'  // Gradient backgrounds

// ❌ FORBIDDEN - text-white on non-colored backgrounds
'bg-theme-surface text-white'  // Never use white text on surface backgrounds
```

**Theme Management**:
- Logged out: Light theme only
- Logged in: User can toggle light/dark
- Responsive: `px-4 sm:px-6 lg:px-8`, headers `h-16`
- Accessibility: ARIA labels, keyboard nav, WCAG AA contrast

### 2. Navigation Structure (MANDATORY)
**CRITICAL**: Simple flat navigation - NO submenu/children arrays allowed.

```typescript
// ❌ FORBIDDEN - No children arrays
{ id: 'billing', children: [...] }  // NEVER DO THIS

// ✅ REQUIRED - Flat navigation with categories
{
  id: 'dashboard', name: 'Dashboard', href: '/app', icon: Home,
  permissions: [], category: 'main', order: 1
}
```

**Navigation Rules**:
- **Structure**: Flat top-level items only in `frontend/src/config/navigation.tsx`
- **Categories**: main, account, analytics, business, content, system, admin
- **Sub-functionality**: Use internal tabs/sections within pages
- **Permissions**: Use permissions array + roles fallback
- **Icons**: Consistent emoji usage (`🏠`, `📊`, `⚙️`, `👥`, `🔧`)

### 3. Page Design Pattern (MANDATORY)
**CRITICAL**: All pages use PageContainer with consolidated actions.

```typescript
// PageContainer implementation
export const SystemPage: React.FC = () => {
  const getPageActions = (): PageAction[] => {
    const baseActions = [{ id: 'refresh', label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw }];
    if (activeTab === 'workers') {
      baseActions.push({ id: 'create-worker', label: 'Create Worker', onClick: create, variant: 'primary', icon: Plus, permission: 'workers.create' });
    }
    return baseActions;
  };

  return (
    <PageContainer title="System Management" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
      {/* Tab content */}
    </PageContainer>
  );
};
```

**Page Design Rules**:
- **PageContainer**: ALL app pages use PageContainer component
- **Actions**: Consolidated in PageContainer only (NEVER in page content)
- **Breadcrumbs**: Page-level only (not individual tabs)
- **Tabs**: Use consistent tab navigation with emoji icons
- **Event Communication**: Parent-child action communication via events/context

### 4. API Service Pattern (MANDATORY)
**Standardized pattern for all API services**:

```typescript
import { api } from './api';

export interface ServiceItem { id: string; name: string; }

export const serviceNameApi = {
  async getItems(page = 1, perPage = 20): Promise<ServiceItem[]> {
    const response = await api.get(`/items?page=${page}&per_page=${perPage}`);
    return response.data;
  },
  async createItem(data: Partial<ServiceItem>): Promise<ServiceItem> {
    const response = await api.post('/items', data);
    return response.data;
  }
};
```

**API Service Rules**:
- Import: `import { api } from './api'`
- Export: `export const serviceNameApi = { ... }`
- Methods: Standard CRUD operations (getItems, getItem, createItem, updateItem, deleteItem)
- Returns: Always `response.data`
- TypeScript: Proper interfaces and return types

### 5. Global Notification System (MANDATORY)
**CRITICAL**: All user feedback uses global notifications - NO local message state.

```typescript
// ✅ CORRECT - Global notifications
import { useNotification } from '../../hooks/useNotification';

const { showNotification } = useNotification();
const handleUpdate = async () => {
  try {
    await api.updateSomething();
    showNotification('Settings updated successfully', 'success');
  } catch (error) {
    showNotification('Failed to update settings', 'error');
  }
};

// ❌ FORBIDDEN - Local message state
const [successMessage, setSuccessMessage] = useState('');  // NEVER DO THIS
```

**Notification Rules**:
- **Global Only**: Never use `useState` for success/error messages
- **Message Types**: `success`, `error`, `warning`, `info`
- **Local Alerts OK**: Data loading errors, form validation, page instructions, empty states
- **Consistency**: All messages appear in same location as login/logout

### 6. File Organization (MANDATORY)
**Feature-based organization with strict naming conventions**:

```
src/
├── features/           # Business domains (auth/, billing/, users/)
│   └── [feature]/
│       ├── components/ # Feature-specific components
│       ├── hooks/      # Feature-specific hooks
│       ├── services/   # Feature-specific API calls
│       ├── types/      # Feature-specific TypeScript types
│       └── utils/      # Feature-specific utilities
├── shared/             # Cross-feature reusables
│   ├── components/     # UI primitives (ui/, layout/, forms/)
│   ├── hooks/          # Reusable hooks
│   ├── services/       # Shared API services
│   └── types/          # Global TypeScript types
└── pages/              # Route-based components (public/, app/, admin/)
```

**File Naming Rules**:
- **Components**: PascalCase.tsx (UserProfile.tsx)
- **Hooks**: camelCase starting with 'use' (useUserProfile.ts)
- **Services**: camelCase ending with 'Api' (userApi.ts)
- **Types**: PascalCase (User.ts, ApiResponse.ts)
- **Imports**: Use path aliases (`@/shared/components/ui/Button`)

### 7. Permission-Based Access Control (CRITICAL)
**ABSOLUTE RULE**: NEVER use role-based access control - ONLY permission-based access control.

**FORBIDDEN PATTERNS**:
```typescript
// ❌ NEVER DO THIS - Role-based access control
const canManage = user?.roles?.includes('account.manager');
const isAdmin = user?.role === 'admin';
if (user.roles.includes('system.admin')) { /* ... */ }

// ❌ NEVER DO THIS - Mixed role/permission checks
const canAccess = user?.roles?.includes('admin') || user?.permissions?.includes('users.read');
```

**MANDATORY PATTERNS**:
```typescript
// ✅ ALWAYS DO THIS - Permission-based access control ONLY
const canManageUsers = user?.permissions?.includes('users.manage');
const canUpdateBilling = user?.permissions?.includes('billing.update');
const canDeleteResources = user?.permissions?.includes('resources.delete');

// ✅ Multiple permission checks
const canManageTeam = user?.permissions?.includes('users.manage') || 
                     user?.permissions?.includes('team.manage') ||
                     user?.permissions?.includes('users.update');
```

**Permission System Rules**:
- **Format**: `resource.action` (e.g., `users.create`, `billing.read`, `team.manage`)
- **Access Control**: ALL frontend access decisions based on permissions ONLY
- **No Role Checks**: Never check user roles for access control
- **Permission Validation**: Backend validates permissions through role hierarchy
- **UI Controls**: Disable/hide UI elements based on permissions only

**Standard Permissions**:
- **User Management**: `users.create`, `users.read`, `users.update`, `users.delete`, `users.manage`
- **Team Management**: `team.manage`, `team.invite`, `team.remove`
- **Billing**: `billing.read`, `billing.update`, `billing.manage`, `invoices.create`
- **System Admin**: `system.admin`, `accounts.manage`, `settings.update`
- **Content**: `pages.create`, `pages.update`, `content.manage`

### 8. Component Composition Patterns (MANDATORY)
**Standard component patterns for consistency**:

```typescript
// ✅ CORRECT - Standard component structure
export const ComponentName: React.FC<ComponentProps> = ({ prop1, prop2 }) => {
  // Hooks first
  const [state, setState] = useState();
  const { contextValue } = useContext();
  
  // Effects second
  useEffect(() => {}, []);
  
  // Handlers third
  const handleAction = () => {};
  
  // Render
  return <div>{/* content */}</div>;
};
```

**Component Rules**:
- **Props Interface**: Always define TypeScript interface for props
- **Hooks Order**: useState → useContext → useEffect → custom hooks
- **Event Handlers**: Prefix with `handle` (handleClick, handleSubmit)
- **Loading States**: Use consistent loading indicators
- **Empty States**: Always provide empty state UI
- **Error Boundaries**: Wrap feature components in error boundaries

### 9. Form Patterns (MANDATORY)
**Consistent form handling across the application**:

```typescript
// ✅ CORRECT - Standard form pattern
const [formData, setFormData] = useState<FormData>(initialData);
const [errors, setErrors] = useState<FormErrors>({});
const [submitting, setSubmitting] = useState(false);

const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();
  setSubmitting(true);
  try {
    await api.submitForm(formData);
    showNotification('Success!', 'success');
  } catch (error) {
    showNotification('Failed', 'error');
  } finally {
    setSubmitting(false);
  }
};
```

**Form Rules**:
- **Validation**: Client-side validation before submission
- **Loading States**: Disable form during submission
- **Error Display**: Field-level error messages
- **Success Feedback**: Global notifications for success
- **Data Persistence**: Consider form data persistence for long forms

### 10. Responsive Design Patterns (MANDATORY)
**Mobile-first responsive design**:

```typescript
// ✅ CORRECT - Mobile-first responsive classes
'px-4 sm:px-6 lg:px-8'         // Padding
'grid-cols-1 md:grid-cols-2 lg:grid-cols-3'  // Grid
'text-sm sm:text-base lg:text-lg'  // Typography
'hidden sm:block'               // Visibility
'w-full sm:w-auto'             // Width
```

**Breakpoints**:
- **sm**: 640px (tablets)
- **md**: 768px (small laptops)
- **lg**: 1024px (desktops)
- **xl**: 1280px (large desktops)
- **2xl**: 1536px (ultra-wide)

### Design Pattern Audit Commands
```bash
# Theme audit (excluding allowed text-white usage)
grep -r "bg-red-\|bg-green-\|bg-blue-\|bg-white\|text-black\|border-gray-" frontend/src/ | grep -v "text-white"

# Navigation audit
grep -c "children:" frontend/src/config/navigation.tsx  # Should return 0

# PageContainer audit
grep -r "export.*Page.*React.FC" frontend/src/pages/ | grep -v "PageContainer"  # Find non-compliant pages

# Notification audit
grep -r "useState.*[Ss]uccess.*[Mm]essage\|useState.*[Ee]rror.*[Mm]essage" frontend/src/  # Should be empty

# Form pattern audit
grep -r "handleSubmit" frontend/src/ | grep -v "e.preventDefault()"  # Find forms missing preventDefault

# Component structure audit
grep -r "React.FC" frontend/src/ | grep -v "interface.*Props"  # Find components without prop interfaces
```

### Navigation Standards (MANDATORY)
**CRITICAL**: Simple flat navigation - NO submenu/children arrays allowed.

#### Requirements
1. **NO SUBMENUS**: No `children` arrays or nested navigation
2. **FLAT STRUCTURE**: Top-level items only
3. **DIRECT LINKS**: Direct page/route links
4. **CATEGORIES**: Group by category (main, account, analytics, business, content, system, admin)

```typescript
// ❌ FORBIDDEN - No children arrays
{ id: 'billing', children: [...] }  // NEVER DO THIS

// ✅ REQUIRED - Flat navigation
{
  id: 'dashboard',
  name: 'Dashboard', 
  href: '/app',
  icon: Home,
  permissions: [],
  category: 'main',
  order: 1
}
```

**Categories**: main (Overview), account (Account Management), analytics (Analytics & Reports), business (Business Operations), content (Content Management), system (System Administration), admin (Platform Administration)

**Permission Logic**: Dashboard always visible, fallback to roles if no permissions, check permissions array first

```bash
# Audit commands
grep -c "children:" frontend/src/config/navigation.tsx  # Should return 0
grep -c "id: '" frontend/src/config/navigation.tsx      # Count items
```

### Page Design Pattern (MANDATORY)
**CRITICAL**: All pages use PageContainer with consistent patterns.

#### Requirements
1. **PageContainer**: All app pages use PageContainer component
2. **Breadcrumbs**: Navigation hierarchy (page-level only, not tabs)
3. **Actions**: Consolidated in PageContainer actions (never in page content)
4. **Icons**: Emoji icons for consistency (`🏠`, `📊`, `⚙️`, `👥`, `🔧`)
5. **Tabs**: Use tabbed navigation for multi-section pages

#### PageContainer Implementation
```typescript
// System page example with tab-specific actions
export const SystemPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState('overview');
  const [systemActions, setSystemActions] = useState<SystemPageActions>({});

  const getPageActions = (): PageAction[] => {
    const baseActions = [{
      id: 'refresh', label: 'Refresh', 
      onClick: () => systemActions.refreshWorkers?.() || window.location.reload(),
      variant: 'secondary', icon: RefreshCw
    }];

    // Add tab-specific actions
    if (activeTab === 'workers') {
      baseActions.push({
        id: 'create-worker', label: 'Create Worker',
        onClick: () => systemActions.createWorker?.(),
        variant: 'primary', icon: Plus, permission: 'workers.create'
      });
    }
    return baseActions;
  };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'System', icon: '🔧' }
  ];

  return (
    <SystemProvider actions={systemActions} onActionsChange={setSystemActions}>
      <PageContainer title="System Management" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
        {/* Tab content */}
      </PageContainer>
    </SystemProvider>
  );
};
```

#### Tab Navigation Pattern
```typescript
// Tab structure with emoji icons
const tabs = [
  { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
  { id: 'workers', label: 'Workers', icon: '🔧', path: '/workers' },
  { id: 'volumes', label: 'Volumes', icon: '💾', path: '/volumes' }
] as const;

// Tab navigation JSX
<div className="border-b border-theme mb-6">
  <div className="flex space-x-8 -mb-px">
    {tabs.map((tab) => (
      <button key={tab.id} onClick={() => handleTabChange(tab.id)}
        className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
          activeTab === tab.id ? 'border-theme-link text-theme-link' :
          'border-transparent text-theme-secondary hover:text-theme-primary'
        }`}>
        <span className="text-base">{tab.icon}</span>
        <span>{tab.label}</span>
      </button>
    ))}
  </div>
</div>

// Routing handler
const handleTabChange = (tabId: string) => {
  const tab = tabs.find(t => t.id === tabId);
  if (tab) {
    const targetPath = tabId === 'overview' ? '/app/system' : `/app/system${tab.path}`;
    navigate(targetPath);
  }
};
```

#### Action Button Standards (MANDATORY)
**CRITICAL**: All actions consolidated in PageContainer - NEVER in page content.

**Requirements**:
1. **Only in PageContainer**: No action buttons anywhere else
2. **Consolidated**: All page + tab actions in PageContainer
3. **Base Actions**: Always show common actions (Refresh, etc.)
4. **Conditional**: Tab actions only when tab is active
5. **Permissions**: Include permission checking in action definitions

#### Event-Based Action Pattern
```typescript
// Parent page with consolidated actions
export const AccountPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState('users');

  const getPageActions = (): PageAction[] => {
    const baseActions = [{ id: 'refresh', label: 'Refresh', onClick: () => window.location.reload(), variant: 'secondary', icon: RefreshCw }];

    if (activeTab === 'invitations') {
      return [
        { id: 'send-invitation', label: 'Send New Invitation', 
          onClick: () => window.dispatchEvent(new CustomEvent('open-invite-modal')), 
          variant: 'primary', icon: UserPlus },
        ...baseActions
      ];
    }
    return baseActions;
  };

  return (
    <PageContainer title="Account Management" actions={getPageActions()}>
      {/* Tab content */}
    </PageContainer>
  );
};

// Child component listens for events
export const InvitationsPage: React.FC = () => {
  const [showModal, setShowModal] = useState(false);

  useEffect(() => {
    const handleOpen = () => setShowModal(true);
    window.addEventListener('open-invite-modal', handleOpen);
    return () => window.removeEventListener('open-invite-modal', handleOpen);
  }, []);

  return <div className="space-y-6">{/* Content only */}</div>;
};
```

**Benefits**: Consistent UX, context-aware actions, clean design, better discoverability, permission integration

**Examples**:
```typescript
// Single page actions
const pageActions = [{ id: 'refresh', label: 'Refresh', onClick: loadData, variant: 'secondary', icon: RefreshCw, disabled: loading }];

// Tabbed page with conditional actions
const getPageActions = () => {
  const base = [/* common actions */];
  if (activeTab === 'scheduled') base.push({ id: 'new-schedule', label: 'New Schedule', onClick: handleNewSchedule, variant: 'primary', icon: Plus });
  return base;
};
```

**Forbidden Patterns**:
```typescript
// ❌ NEVER place actions in page content, tab headers, or card headers
<Button onClick={handleAction}>Action</Button> // WRONG

// ✅ ONLY in PageContainer
<PageContainer actions={getPageActions()}>{/* content */}</PageContainer>
```

**Standards**:
- **Breadcrumbs**: Page-level only (not tabs) - `Dashboard > Account` not `Dashboard > Account > Audit Logs`
- **Icons**: Emoji consistency (`🏠`, `📊`, `⚙️`, `👥`, `🔧`), `text-base` for tabs

```bash
# Audit commands
grep -r "export.*Page.*React.FC" frontend/src/pages/ | grep -v "PageContainer"  # Find non-PageContainer pages
grep -r "border-b.*border-theme" frontend/src/pages/ | grep -v "space-x-8.*-mb-px"  # Find inconsistent tabs
```

### Context Pattern for Action Communication
```typescript
// SystemContext for registering child component actions
export const SystemProvider: React.FC<SystemProviderProps> = ({ children, actions, onActionsChange }) => {
  const actionsRef = useRef<SystemPageActions>(actions);
  const registerActions = useCallback((newActions: Partial<SystemPageActions>) => {
    actionsRef.current = { ...actionsRef.current, ...newActions };
    onActionsChange({ ...actionsRef.current });
  }, [onActionsChange]);

  return <SystemContext.Provider value={{ registerActions }}>{children}</SystemContext.Provider>;
};

// Child component registers actions
export const WorkersPage: React.FC = () => {
  const { registerActions } = useSystemContext();
  const refreshData = async () => { /* refresh logic */ };

  useEffect(() => {
    registerActions({ refreshWorkers: refreshData, createWorker: () => setShowCreateModal(true) });
  }, [registerActions]);

  return <div className="space-y-6">{/* Content only - no action buttons */}</div>;
};
```

### API Service Pattern (MANDATORY)
**Standardized pattern for all API services:**

```typescript
import { api } from './api';

export interface ServiceItem { id: string; name: string; }

export const serviceNameApi = {
  async getItems(page = 1, perPage = 20): Promise<ServiceItem[]> {
    const response = await api.get(`/items?page=${page}&per_page=${perPage}`);
    return response.data;
  },
  async getItem(id: string): Promise<ServiceItem> {
    const response = await api.get(`/items/${id}`);
    return response.data;
  },
  async createItem(data: Partial<ServiceItem>): Promise<ServiceItem> {
    const response = await api.post('/items', data);
    return response.data;
  },
  async updateItem(id: string, data: Partial<ServiceItem>): Promise<ServiceItem> {
    const response = await api.put(`/items/${id}`, data);
    return response.data;
  },
  async deleteItem(id: string): Promise<void> {
    await api.delete(`/items/${id}`);
  }
};
```

**Requirements**: Import `{ api }`, export `serviceNameApi`, use direct API calls, return `response.data`, proper TypeScript interfaces

### Global Notification System (MANDATORY)
**CRITICAL**: All user action feedback uses global notifications - NO local message state.

**Requirements**:
1. **NO local state**: Never `useState` for success/error messages
2. **Global notifications**: All transactional messages use global system
3. **Consistent UX**: Messages appear in same location as login/logout

```typescript
// ✅ CORRECT - Global notifications
import { useNotification } from '../../hooks/useNotification';

const { showNotification } = useNotification();
const handleUpdate = async () => {
  try {
    await api.updateSomething();
    showNotification('Settings updated successfully', 'success');
  } catch (error) {
    showNotification('Failed to update settings', 'error');
  }
};

// ❌ WRONG - Local message state
const [successMessage, setSuccessMessage] = useState('');  // NEVER DO THIS
```

**Message Types**: `success` (operations), `error` (failures), `warning` (notices), `info` (updates)

**Local Alerts OK For**: Data loading errors, form validation, page instructions, empty states

```bash
# Audit commands
grep -r "useState.*[Ss]uccess.*[Mm]essage\|useState.*[Ee]rror.*[Mm]essage" frontend/src/  # Should be empty
grep -r "alert-theme-success\|alert-theme-error" frontend/src/  # Review these
```

## Security & Permissions

### Security Requirements
- **JWT Authentication**: 15min access tokens, 7-day refresh tokens, HMAC-SHA256
- **Email Verification**: Required before login, time-limited tokens
- **Password Security**: 12+ chars, complexity rules, history tracking, account lockout
- **PCI Compliance**: Secure payment data handling
- **Rate Limiting**: All endpoints protected

### Permission-Based Access Control System (CRITICAL)
**ABSOLUTE MANDATE**: Frontend access control MUST use permissions ONLY - NEVER roles.

**FORBIDDEN FRONTEND PATTERNS**:
```typescript
// ❌ NEVER DO THIS - Role-based frontend access control
const canManage = currentUser?.roles?.includes('account.manager');
const isSystemAdmin = currentUser?.role === 'system.admin';
if (user.roles.includes('billing.manager')) { return <AdminPanel />; }

// ❌ NEVER DO THIS - Mixed role/permission checks
const hasAccess = user.roles.includes('admin') || user.permissions.includes('read');
```

**MANDATORY FRONTEND PATTERNS**:
```typescript
// ✅ ALWAYS DO THIS - Permission-based access control ONLY
const canManageUsers = currentUser?.permissions?.includes('users.manage');
const canViewBilling = currentUser?.permissions?.includes('billing.read');
const canCreateContent = currentUser?.permissions?.includes('pages.create');

// ✅ Component access control
const canAccessAdminPanel = currentUser?.permissions?.includes('admin.access');
if (!canAccessAdminPanel) return <AccessDenied />;

// ✅ UI element control
<Button disabled={!currentUser?.permissions?.includes('users.create')}>
  Create User
</Button>
```

#### Backend Role System (For Permission Assignment Only)
**Backend roles exist ONLY to assign permissions - frontend NEVER checks roles**

**Standard Roles** (Backend assignment only):
- **`system.admin`**: Grants all permissions across system
- **`account.manager`**: Grants account-scoped permissions
- **`account.member`**: Grants basic user permissions  
- **`billing.manager`**: Grants billing management permissions

**Permission Categories**:
- **User Management**: `users.create`, `users.read`, `users.update`, `users.delete`, `users.manage`, `team.manage`
- **Billing Operations**: `billing.read`, `billing.update`, `billing.manage`, `invoices.create`, `payments.process`
- **System Administration**: `admin.access`, `system.admin`, `accounts.manage`, `settings.update`  
- **Content Management**: `pages.create`, `pages.update`, `pages.delete`, `content.manage`
- **Analytics**: `analytics.read`, `analytics.export`, `reports.generate`

#### Implementation Rules
1. **Frontend**: Check `currentUser.permissions.includes('permission.name')` ONLY
2. **Backend**: Roles assign permissions, controllers validate permissions
3. **API Responses**: Always include `permissions` array in user objects
4. **UI Controls**: Disable/hide elements based on permissions
5. **Navigation**: Filter menu items by permissions, not roles

## Backend & Worker Architecture (ENFORCED)

### 1. Rails API Patterns (MANDATORY)
**Standardized patterns for 63 controllers and 75 models**:

```ruby
# ✅ CORRECT - Controller pattern
class Api::V1::ResourcesController < ApplicationController
  include AuditLogging
  before_action :set_resource, only: [:show, :update]
  
  def show
    render json: {
      success: true,
      data: resource_data(@resource)
    }, status: :ok
  end
  
  def update
    if @resource.update(resource_params)
      render json: {
        success: true,
        data: resource_data(@resource),
        message: "Resource updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Resource update failed",
        details: @resource.errors.full_messages
      }, status: :unprocessable_content
    end
  end
  
  private
  
  def resource_params
    params.require(:resource).permit(:name, :status)
  end
  
  def resource_data(resource)
    {
      id: resource.id,
      name: resource.name,
      status: resource.status,
      created_at: resource.created_at,
      updated_at: resource.updated_at
    }
  end
end
```

**Rails Controller Rules**:
- **API Versioning**: All controllers in `Api::V1` namespace
- **Response Format**: Consistent `{success: boolean, data: object, error?: string}` structure
- **Status Codes**: Use semantic HTTP status codes (`unprocessable_content` not `unprocessable_entity`)
- **Includes**: Use concerns (`AuditLogging`, `Authentication`) for cross-cutting functionality
- **Private Methods**: `set_resource`, `resource_params`, `resource_data` pattern
- **Error Handling**: Include `details` with validation errors

### 2. Rails Model Patterns (MANDATORY)
**Standardized patterns for ActiveRecord models**:

```ruby
# ✅ CORRECT - Model pattern
class Account < ApplicationRecord
  # Associations first
  has_many :users, dependent: :destroy
  has_one :subscription, dependent: :destroy
  belongs_to :default_volume, class_name: 'Volume', optional: true
  
  # Validations second
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :status, presence: true, inclusion: { in: %w[active suspended cancelled] }
  
  # Scopes third
  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
  
  # Callbacks fourth
  before_validation :normalize_subdomain
  after_create :log_account_creation
  after_update :log_account_updates
  
  # Instance methods fifth
  def active?
    status == "active"
  end
  
  def manager
    users.where(role: "account.manager").first
  end
  
  private
  
  # Private methods last
  def normalize_subdomain
    # Implementation
  end
end
```

**Rails Model Rules**:
- **Structure Order**: Associations → Validations → Scopes → Callbacks → Public methods → Private methods
- **UUID Keys**: All models use UUID primary keys (string, limit: 36)
- **Audit Logging**: Include audit callbacks (`log_*_creation`, `log_*_updates`)
- **Status Methods**: Boolean methods for status checks (`active?`, `suspended?`)
- **Dependent**: Always specify `:dependent` option on associations
- **Optional**: Use `optional: true` for nullable belongs_to relationships

### 3. Service Layer Patterns (MANDATORY)
**Business logic delegation to worker services**:

```ruby
# ✅ CORRECT - Backend service delegates to worker
class BillingService
  include ActiveModel::Model
  
  attr_accessor :subscription, :account, :user
  
  def create_subscription_with_payment(plan:, payment_method:, **options)
    Rails.logger.info "Delegating subscription creation to worker service"
    
    job_data = {
      plan_id: plan.id,
      payment_method_id: payment_method.id,
      account_id: account.id
    }.merge(options)
    
    begin
      WorkerJobService.enqueue_billing_job('create_subscription_with_payment', job_data)
      { success: true, message: "Subscription creation queued for processing" }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to delegate billing job: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
```

**Service Rules**:
- **Delegation**: Complex operations (>100ms) delegated to worker service
- **Include ActiveModel::Model**: For service objects
- **Logging**: Use `Rails.logger` with descriptive messages
- **Error Handling**: Catch worker service errors and return structured responses
- **Return Format**: Consistent `{success: boolean, message/error: string}` format
- **Job Enqueueing**: Use `WorkerJobService` for job delegation

### 4. Worker Service Architecture (MANDATORY)
**35+ background jobs with API-only communication**:

```ruby
# ✅ CORRECT - Worker job pattern
class VolumeSyncJob < BaseJob
  sidekiq_options queue: 'volumes', retry: 2
  
  def execute(args)
    volume_id = args['volume_id']
    sync_type = args['sync_type'] || 'full'
    
    logger.info "Starting sync for volume #{volume_id} (type: #{sync_type})"
    
    begin
      case sync_type
      when 'full'
        sync_configuration(volume_id)
        sync_usage(volume_id)
      when 'usage'
        sync_usage(volume_id)
      end
      
      {
        volume_id: volume_id,
        sync_type: sync_type,
        synced_at: Time.current.iso8601,
        success: true
      }
    rescue => e
      logger.error "Sync failed for volume #{volume_id}: #{e.message}"
      { volume_id: volume_id, error: e.message, success: false }
    end
  end
  
  private
  
  def sync_usage(volume_id)
    stats = VolumeService.instance.stats(volume_id)
    response = api_client.post("/volumes/#{volume_id}/usage_snapshots", stats)
    
    unless response.success?
      logger.error "Failed to create usage snapshot: #{response.error}"
    end
  end
end
```

**Worker Job Rules**:
- **Inheritance**: All jobs inherit from `BaseJob` (not `ApplicationJob`)
- **Method**: Use `execute(args)` method (not `perform`)
- **API Communication**: Use `api_client` for all backend communication
- **No Database**: No direct ActiveRecord access - API calls only
- **Logging**: Use `logger` (not `Rails.logger`) for worker-specific logging
- **Error Handling**: Rescue exceptions and return structured error responses
- **Return Values**: Always return hash with success status and relevant data
- **Queue Configuration**: Use `sidekiq_options` for queue and retry settings

### 5. API Client Patterns (MANDATORY)
**Standardized worker-to-backend communication**:

```ruby
# ✅ CORRECT - API client usage
class BackendApiClient
  def get_account(account_id)
    get("/api/v1/accounts/#{account_id}")
  end
  
  def create_report(report_data)
    post("/api/v1/reports", report_data)
  end
  
  def update_report_status(request_id, status)
    patch("/api/v1/reports/requests/#{request_id}", { status: status })
  end
end

class ApiResponse
  def initialize(success, data, error = nil)
    @success = success
    @data = data
    @error = error
  end
  
  def success?
    @success
  end
end
```

**API Client Rules**:
- **HTTP Methods**: Standard REST methods (GET, POST, PATCH, PUT, DELETE)
- **Response Wrapper**: Use `ApiResponse` class for consistent response handling
- **Error Handling**: Structured error responses with status codes
- **Authentication**: Service-to-service JWT tokens
- **Retry Logic**: Built-in retry with exponential backoff
- **Timeout**: Reasonable timeouts for all requests

### 6. Code Standards (MANDATORY)
**Ruby code quality and consistency**:

```ruby
# ✅ REQUIRED at top of all files
# frozen_string_literal: true

# ✅ CORRECT logging
Rails.logger.info "User #{user.id} performed action"    # Backend
logger.info "Processing job for volume #{volume_id}"    # Worker

# ❌ FORBIDDEN debugging code
puts "Debug info"     # Never commit
p variable            # Never commit
print "Status"        # Never commit
```

**Code Quality Rules**:
- **Frozen Strings**: All files must start with `# frozen_string_literal: true`
- **Logging**: Use appropriate logger (`Rails.logger` in backend, `logger` in worker)
- **No Debug Code**: Never commit `puts`, `p`, `print`, or console debugging
- **Consistent JSON**: Use structured JSON responses across all endpoints
- **Error Messages**: User-friendly error messages with technical details in logs



## Quick Reference - CRITICAL Requirements

### 🚨 ABSOLUTE PROHIBITIONS
**Frontend**:
1. **NO role-based access control**: ONLY permission-based access control allowed
2. **NO hardcoded colors**: Use `bg-theme-*`, `text-theme-*` classes only (Exception: `text-white` on colored backgrounds)
3. **NO submenu navigation**: Flat navigation structure only - no `children` arrays
4. **NO action buttons in page content**: ALL actions in PageContainer only
5. **NO local success/error state**: Global notifications only
6. **NO relative imports**: Use path aliases (`@/shared/`, `@/features/`)
7. **NO inline styles**: All styling via Tailwind classes
8. **NO console.log**: Use proper logging utilities
9. **NO any types**: Proper TypeScript types required

**CRITICAL - Permission-Based Access Control**:
- **NEVER**: `currentUser?.roles?.includes('admin')` or `user.role === 'manager'`
- **NEVER**: `if (user.roles.includes('system.admin'))` for access control
- **NEVER**: Mixed role/permission checks for access decisions
- **ALWAYS**: `currentUser?.permissions?.includes('users.manage')` for access control

**Backend**:
9. **NO direct database access in worker**: Use API client only
10. **NO puts/p/print in code**: Use proper logging (Rails.logger/logger)
11. **NO missing frozen_string_literal**: All Ruby files must include pragma
12. **NO ApplicationJob inheritance**: Worker jobs inherit from BaseJob
13. **NO perform method in worker**: Use execute method instead
14. **NO unstructured API responses**: Use {success, data, error} format
15. **NO manual server starts**: Use management scripts only
16. **NO Claude attribution**: Clean commit messages only

### ✅ MANDATORY PATTERNS
**Frontend**:
1. **Permission-Based Access Control**: `currentUser?.permissions?.includes('users.manage')` for ALL access decisions
2. **PageContainer**: All app pages use PageContainer with consolidated actions
3. **Theme Classes**: `bg-theme-surface`, `text-theme-primary`, `border-theme`
4. **API Services**: Standard pattern with `serviceNameApi = { getItems, createItem, ... }`
5. **Component Structure**: Props interface → Hooks → Effects → Handlers → Render
6. **Form Handling**: preventDefault → Validation → API call → Global notification
7. **Mobile-First**: Start with mobile styles, add breakpoint modifiers
8. **File Organization**: Feature-based with `components/`, `hooks/`, `services/`, `types/`

**Backend**:
9. **Controller Pattern**: `Api::V1` namespace, standard response format, include concerns
10. **Model Structure**: Associations → Validations → Scopes → Callbacks → Methods
11. **Service Delegation**: Complex operations delegated to worker service
12. **Worker Jobs**: Inherit BaseJob, use execute method, API-only communication
13. **API Responses**: `{success: boolean, data: object, error?: string}` format
14. **UUID Strategy**: All models use UUID primary keys (string, limit: 36)
15. **Frozen Strings**: All Ruby files start with `# frozen_string_literal: true`
16. **Error Handling**: Structured responses with user-friendly messages

**Universal**:
17. **Conventional Commits**: `feat:`, `fix:`, `docs:` with semantic versioning
18. **Git-Flow**: `develop` → `feature/*` → `release/*` → `main`
19. **Permission-Based Authorization**: Use permissions, not roles, for access control

### 🔧 Quick Commands
```bash
# Development
$POWERNODE_ROOT/scripts/auto-dev.sh ensure    # Start all services
cd server && rails db:migrate db:seed         # Database setup
cd server && bundle exec rspec               # Run backend tests

# Git Flow
git flow feature start ISSUE-description
git flow release start v1.2.0
npm version patch|minor|major

# Audits
# Permission-Based Access Control Audits (CRITICAL)
grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ | grep -v "member\.roles\?.*map\|formatRole\|getRoleColor"  # Find role-based access checks (should be empty)
grep -r "currentUser.*roles\?\." frontend/src/ | grep -v "member\.roles\|user\.roles.*map\|formatRole"  # Find user role access (should be empty for access control)
grep -r "user.*roles.*admin\|user.*role.*manager" frontend/src/ | grep -v "display\|format\|badge"  # Find hardcoded role checks (should be empty)
grep -r "permissions.*includes" frontend/src/ | wc -l  # Count permission-based checks (should be > 0)

# Frontend Design Pattern Audits
grep -r "bg-red-\|bg-white\|text-black\|border-gray-" frontend/src/ | grep -v "text-white"  # Hardcoded colors
grep -c "children:" frontend/src/config/navigation.tsx    # Should return 0
grep -r "useState.*[Ss]uccess.*[Mm]essage" frontend/src/  # Should be empty
grep -r "console.log" frontend/src/                       # Should be empty
grep -r ": any" frontend/src/ | grep -v "node_modules"   # Find any types

# Backend audits
grep -r "puts \|p \|print " server/app/                   # Should be empty (no debug code)
grep -L "frozen_string_literal" server/app/**/*.rb       # Files missing pragma
grep -r "< ApplicationJob" worker/app/jobs/              # Should be empty (use BaseJob)
grep -r "def perform" worker/app/jobs/                   # Should be empty (use execute)
grep -r "ActiveRecord" worker/app/                       # Should be empty (API-only)
grep -c "render json:.*success:" server/app/controllers/ # Count structured responses
```

## 📁 CLAUDE Documentation Organization (MANDATORY)

### Documentation Directory Structure
**CRITICAL**: All CLAUDE-generated documentation MUST be organized in appropriate subdirectories - NEVER save to root folder.

```
powernode-platform/
├── docs/                    # Platform-wide documentation
│   ├── platform/           # Platform architecture, migrations, system docs
│   ├── backend/            # Backend-specific technical documentation
│   ├── frontend/           # Frontend-specific technical documentation  
│   └── worker/             # Worker service documentation
├── server/docs/            # Backend implementation docs
├── frontend/docs/          # Frontend implementation docs
└── worker/docs/            # Worker implementation docs
```

### Document Categories & Placement Rules

**Platform-Level** (`docs/platform/`):
- System architecture documents
- Migration plans and completion reports
- Cross-component integration documentation
- WebSocket and authentication system docs
- Permission system documentation
- Multi-service coordination docs

**Backend-Specific** (`docs/backend/` or `server/docs/`):
- Rails API documentation
- Database schema and model documentation
- Service layer architecture
- Authentication and security implementation
- Backend testing strategies

**Frontend-Specific** (`docs/frontend/` or `frontend/docs/`):
- React architecture and patterns
- Component organization documentation
- Styling and theming guides
- Frontend testing documentation
- UI/UX implementation guides

**Worker-Specific** (`docs/worker/` or `worker/docs/`):
- Sidekiq job documentation
- Background processing architecture
- Queue management documentation
- Worker service integration

### File Organization Commands
```bash
# NEVER save documentation to root - use appropriate directories
# Platform docs
docs/platform/PERMISSION_SYSTEM_COMPLETE.md
docs/platform/MIGRATION_PHASE_1_IMPLEMENTATION.md
docs/platform/WEBSOCKET_STATUS_SOLUTION.md

# Frontend docs  
frontend/docs/CONTAINER_PATTERNS.md
frontend/docs/STYLING_IMPLEMENTATION_PLAN.md

# Backend docs
server/docs/PERMISSION_SYSTEM_V2_SUMMARY.md
server/docs/ROLE_STANDARDIZATION.md

# Worker docs
worker/docs/ # For worker-specific documentation
```

### Documentation Standards
- **Naming**: Use UPPERCASE with underscores for technical docs (FEATURE_IMPLEMENTATION.md)
- **Location**: Choose most specific directory possible (component-specific over platform-wide)
- **Cross-References**: Use relative paths when linking between docs
- **Version Control**: All documentation committed to appropriate directories

**ABSOLUTE RULE**: No `.md` files in project root except CLAUDE.md, TODO.md, CHANGELOG.md, and DEVELOPMENT.md
