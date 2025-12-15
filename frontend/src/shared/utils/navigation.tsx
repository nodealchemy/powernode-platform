// Navigation Configuration
import {
  Home, BarChart3, Users, User, Settings, CreditCard,
  FileText, Package, UserCheck, Store, Smartphone,
  HelpCircle, LogOut, Bot, Brain, MessageSquare,
  HardDrive, Workflow, Activity, Server
} from 'lucide-react';
import { NavigationConfig } from '../types/navigation';

export const defaultNavigationConfig: NavigationConfig = {
  items: [
    {
      id: 'dashboard',
      name: 'Dashboard',
      href: '/app',
      icon: Home,
      description: 'Overview and quick actions',
      permissions: [],
      order: 1
    },
    {
      id: 'profile',
      name: 'My Profile',
      href: '/app/profile',
      icon: User,
      description: 'Personal information and preferences',
      permissions: [],
      order: 2
    },
    {
      id: 'team-members',
      name: 'Team Members',
      href: '/app/users',
      icon: Users,
      description: 'Manage your team members',
      permissions: ['team.read'],
      order: 3
    },
    {
      id: 'marketplace',
      name: 'Marketplace',
      href: '/app/marketplace',
      icon: Store,
      description: 'Browse apps, manage subscriptions, and create your own',
      permissions: [],
      order: 4
    }
  ],
  
  sections: [
    {
      id: 'ai',
      name: 'AI',
      items: [
        {
          id: 'ai-overview',
          name: 'Overview',
          href: '/app/ai',
          icon: Brain,
          description: 'AI system dashboard and quick actions',
          permissions: [],
          order: 1
        },
        {
          id: 'ai-providers',
          name: 'Providers',
          href: '/app/ai/providers',
          icon: Settings,
          description: 'Manage AI provider integrations',
          permissions: ['ai.providers.read'],
          order: 2
        },
        {
          id: 'ai-agents',
          name: 'Agents',
          href: '/app/ai/agents',
          icon: Bot,
          description: 'Create and manage AI agents',
          permissions: ['ai.agents.read'],
          order: 3
        },
        {
          id: 'ai-workflows',
          name: 'Workflows',
          href: '/app/ai/workflows',
          icon: Workflow,
          description: 'Design and execute AI workflows and templates',
          permissions: ['ai.workflows.read'],
          order: 4
        },
        {
          id: 'ai-conversations',
          name: 'Conversations',
          href: '/app/ai/conversations',
          icon: MessageSquare,
          description: 'AI-powered conversations',
          permissions: ['ai.conversations.read'],
          order: 6
        },
        {
          id: 'ai-analytics',
          name: 'Analytics',
          href: '/app/ai/analytics',
          icon: BarChart3,
          description: 'AI performance insights',
          permissions: ['ai.analytics.read'],
          order: 7
        },
        {
          id: 'ai-monitoring',
          name: 'Monitoring',
          href: '/app/ai/monitoring',
          icon: Activity,
          description: 'System health and alerts',
          permissions: ['ai.monitoring.view', 'admin.access'],
          order: 8
        },
        {
          id: 'ai-mcp',
          name: 'MCP Browser',
          href: '/app/ai/mcp',
          icon: Server,
          description: 'Browse MCP servers and tools',
          permissions: ['ai_orchestration.read', 'admin.access'],
          order: 9
        }
      ],
      permissions: ['ai.providers.read', 'ai.agents.read', 'ai.workflows.read', 'ai.conversations.read'],
      collapsible: true,
      defaultExpanded: true,
      order: 5
    },
    {
      id: 'business',
      name: 'Business',
      items: [
        {
          id: 'analytics',
          name: 'Analytics',
          href: '/app/business/analytics',
          icon: BarChart3,
          description: 'Revenue and growth metrics',
          permissions: [],
          order: 1
        },
        {
          id: 'customers',
          name: 'Customers',
          href: '/app/business/customers',
          icon: Users,
          description: 'Customer management and insights',
          permissions: [],
          order: 2
        },
        {
          id: 'plans',
          name: 'Plans',
          href: '/app/business/plans',
          icon: Package,
          description: 'Manage pricing and subscription tiers',
          permissions: [],
          order: 4
        },
        {
          id: 'billing',
          name: 'Billing',
          href: '/app/business/billing',
          icon: CreditCard,
          description: 'Invoices and payment processing',
          permissions: ['admin.billing.read'],
          order: 5
        },
        {
          id: 'reports',
          name: 'Reports',
          href: '/app/business/reports',
          icon: FileText,
          description: 'Financial and usage reports',
          permissions: ['analytics.read'],
          order: 6
        }
      ],
      collapsible: true,
      defaultExpanded: true,
      order: 10
    },
    {
      id: 'content',
      name: 'Content',
      items: [
        {
          id: 'pages',
          name: 'Pages',
          href: '/app/content/pages',
          icon: FileText,
          description: 'Manage content pages and documentation',
          permissions: ['page.read'],
          order: 1
        },
        {
          id: 'knowledge-base',
          name: 'Knowledge Base',
          href: '/app/content/kb',
          icon: HelpCircle,
          description: 'Browse articles, guides, and documentation',
          permissions: ['kb.read'],
          order: 2
        },
        {
          id: 'my-files',
          name: 'My Files',
          href: '/app/content/files',
          icon: HardDrive,
          description: 'Manage your personal files and uploads',
          permissions: ['files.read'],
          order: 3
        }
      ],
      permissions: ['page.read', 'kb.read', 'files.read'],
      collapsible: true,
      defaultExpanded: true,
      order: 16
    }
  ],
  
  userMenuItems: [
    {
      id: 'profile',
      name: 'My Profile',
      href: '/app/profile',
      icon: User,
      description: 'Personal information and preferences'
    },
    {
      id: 'account-settings',
      name: 'Account Settings',
      href: '/app/profile',
      icon: Settings,
      description: 'Account configuration and security'
    },
    {
      id: 'billing-center',
      name: 'Billing Center',
      href: '/app/business/billing',
      icon: CreditCard,
      description: 'Subscription and payment details'
    },
    {
      id: 'help-support',
      name: 'Help & Support',
      href: 'mailto:support@powernode.com',
      icon: HelpCircle,
      description: 'Get help and contact support',
      isExternal: true
    },
    {
      id: 'logout',
      name: 'Sign Out',
      href: '#logout',
      icon: LogOut,
      description: 'Sign out of your account'
    }
  ],
  
  quickActions: [
    {
      id: 'create-plan',
      name: 'Create Plan',
      href: '/app/business/plans/new',
      icon: Package,
      description: 'Set up a new subscription plan'
    },
    {
      id: 'invite-team',
      name: 'Invite Team Member',
      href: '/app/users',
      icon: UserCheck,
      description: 'Add someone to your team'
    },
    {
      id: 'view-analytics',
      name: 'View Analytics',
      href: '/app/business/analytics',
      icon: BarChart3,
      description: 'Check your latest metrics'
    },
    {
      id: 'create-app',
      name: 'Create App',
      href: '/app/marketplace/my-apps',
      icon: Smartphone,
      description: 'Build a new marketplace app',
      permissions: ['app.create']
    },
    {
      id: 'configure-payments',
      name: 'Configure Payments',
      href: '/app/admin/settings/payment-gateways',
      icon: CreditCard,
      description: 'Set up payment processing',
      permissions: ['admin.billing.manage_gateways']
    },
    {
      id: 'create-ai-agent',
      name: 'Create AI Agent',
      href: '/app/ai/agents',
      icon: Bot,
      description: 'Create a new AI agent for automation',
      permissions: ['ai.agents.create']
    },
    {
      id: 'ai-chat',
      name: 'Start AI Chat',
      href: '/app/ai/conversations',
      icon: MessageSquare,
      description: 'Start a new AI conversation',
      permissions: ['ai.conversations.create']
    }
  ]
};

// Admin-specific navigation overrides
export const adminNavigationOverrides = {
  sections: [
    {
      id: 'system',
      name: 'System',
      items: [
        {
          id: 'api-keys',
          name: 'API Keys',
          href: '/app/system/api-keys',
          icon: '🔑',
          description: 'Manage API keys and access tokens',
          permissions: ['api.manage_keys'],
          order: 1
        },
        {
          id: 'audit-logs',
          name: 'Audit Logs',
          href: '/app/system/audit-logs',
          icon: '📋',
          description: 'System audit and activity logs',
          permissions: ['admin.audit.read'],
          order: 2
        },
        {
          id: 'webhooks',
          name: 'Webhooks',
          href: '/app/system/webhooks',
          icon: '🔗',
          description: 'Manage webhook endpoints and events',
          permissions: ['webhook.read'],
          order: 3
        },
        {
          id: 'services',
          name: 'Services',
          href: '/app/system/services',
          icon: '🌐',
          description: 'Configure service routing, load balancing, and proxy settings',
          permissions: ['admin.settings.edit'],
          order: 4
        },
        {
          id: 'workers',
          name: 'Workers',
          href: '/app/system/workers',
          icon: '🤖',
          description: 'Manage background workers and job processing',
          permissions: ['system.workers.read'],
          order: 5
        },
        {
          id: 'storage',
          name: 'File Storage',
          href: '/app/system/storage',
          icon: HardDrive,
          description: 'Configure storage providers for file management',
          permissions: ['admin.storage.manage', 'admin.storage.read'],
          order: 6
        }
      ],
      permissions: ['webhook.read', 'admin.audit.read', 'api.manage_keys', 'admin.settings.edit', 'system.workers.read', 'admin.storage.manage', 'admin.storage.read'],
      collapsible: true,
      defaultExpanded: false,
      order: 18
    },
    {
      id: 'administration',
      name: 'Administration',
      items: [
        {
          id: 'admin-users',
          name: 'All Users',
          href: '/app/admin/users',
          icon: Users,
          description: 'Manage all system users',
          permissions: ['admin.user.read'],
          order: 1
        },
        {
          id: 'maintenance',
          name: 'Maintenance',
          href: '/app/admin/maintenance',
          icon: '🔧',
          description: 'System maintenance and health monitoring',
          permissions: ['admin.maintenance.backup', 'admin.maintenance.cleanup'],
          order: 2
        },
        {
          id: 'roles',
          name: 'Roles & Permissions',
          href: '/app/admin/roles',
          icon: UserCheck,
          description: 'Manage roles and permission assignments',
          permissions: ['admin.role.read'],
          order: 3
        },
        {
          id: 'marketplace-admin',
          name: 'Marketplace',
          href: '/app/admin/marketplace',
          icon: Store,
          description: 'Manage marketplace apps and listings',
          permissions: ['admin.marketplace.read'],
          order: 4
        },
        {
          id: 'settings',
          name: 'Settings',
          href: '/app/admin/settings',
          icon: Settings,
          description: 'Platform configuration and settings',
          permissions: ['admin.settings.read'],
          order: 5
        }
      ],
      permissions: ['admin.access'],
      collapsible: true,
      defaultExpanded: false,
      order: 20
    }
  ]
};

export default defaultNavigationConfig;