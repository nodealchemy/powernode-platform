// Navigation Configuration
import {
  Home, BarChart3, Users, User, Settings, CreditCard,
  FileText, Package, UserCheck, Store,
  HelpCircle, LogOut, Bot, Brain, MessageSquare,
  HardDrive, Workflow, Server, GitBranch, FolderGit2,
  Puzzle, BookOpen, UserCog, Key
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
      id: 'marketplace',
      name: 'Marketplace',
      href: '/app/marketplace',
      icon: Store,
      description: 'Browse apps, manage subscriptions, and create your own',
      permissions: [],
      order: 2
    }
  ],
  
  sections: [
    // Account section - personal and team management
    {
      id: 'account',
      name: 'Account',
      items: [
        {
          id: 'profile',
          name: 'My Profile',
          href: '/app/profile',
          icon: User,
          description: 'Personal information and preferences',
          permissions: [],
          order: 1
        },
        {
          id: 'users',
          name: 'Users',
          href: '/app/users',
          icon: Users,
          description: 'Manage your team members',
          permissions: ['team.read'],
          order: 2
        },
        {
          id: 'billing',
          name: 'Billing',
          href: '/app/account/billing',
          icon: CreditCard,
          description: 'Invoices and payment processing',
          permissions: ['admin.billing.read'],
          order: 3
        }
      ],
      collapsible: true,
      defaultExpanded: true,
      order: 3
    },
    // Business section - core business operations
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
          order: 3
        },
        {
          id: 'reports',
          name: 'Reports',
          href: '/app/business/reports',
          icon: FileText,
          description: 'Financial and usage reports',
          permissions: ['analytics.read'],
          order: 4
        }
      ],
      collapsible: true,
      defaultExpanded: true,
      order: 5
    },
    // AI section - primary differentiating feature
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
          id: 'ai-agents',
          name: 'Agents',
          href: '/app/ai/agents',
          icon: Bot,
          description: 'Create and manage AI agents',
          permissions: ['ai.agents.read'],
          order: 2
        },
        {
          id: 'ai-conversations',
          name: 'Conversations',
          href: '/app/ai/conversations',
          icon: MessageSquare,
          description: 'AI-powered conversations',
          permissions: ['ai.conversations.read'],
          order: 3
        },
        {
          id: 'ai-workflows',
          name: 'Workflows',
          href: '/app/ai/workflows',
          icon: Workflow,
          description: 'Visual AI orchestration and flow builder',
          permissions: ['ai.workflows.read'],
          order: 4
        },
        {
          id: 'ai-prompts',
          name: 'Prompts',
          href: '/app/ai/prompts',
          icon: MessageSquare,
          description: 'Reusable prompt templates for AI workflows',
          permissions: ['ai.prompt_templates.read'],
          order: 5
        },
        {
          id: 'ai-contexts',
          name: 'Contexts',
          href: '/app/ai/contexts',
          icon: BookOpen,
          description: 'Persistent contexts and memory for AI agents',
          permissions: ['ai.context.read'],
          order: 6
        },
        {
          id: 'ai-analytics',
          name: 'AI Analytics',
          href: '/app/ai/analytics',
          icon: BarChart3,
          description: 'AI performance, usage insights, and monitoring',
          permissions: ['ai.analytics.read'],
          order: 7
        },
        {
          id: 'ai-providers',
          name: 'Providers',
          href: '/app/ai/providers',
          icon: Brain,
          description: 'OpenAI, Anthropic, and other AI providers',
          permissions: ['ai.providers.read'],
          order: 8
        },
        {
          id: 'ai-agent-teams',
          name: 'Agent Teams',
          href: '/app/ai/agent-teams',
          icon: Users,
          description: 'CrewAI-style multi-agent team orchestration',
          permissions: ['ai.agents.read'],
          order: 9
        },
        {
          id: 'ai-mcp',
          name: 'MCP Servers',
          href: '/app/ai/mcp',
          icon: Server,
          description: 'Model Context Protocol servers and tools',
          permissions: ['mcp.servers.read'],
          order: 10
        }
      ],
      permissions: ['ai.agents.read', 'ai.workflows.read', 'ai.conversations.read', 'ai.context.read', 'ai.providers.read', 'ai.prompt_templates.read', 'mcp.servers.read'],
      collapsible: true,
      defaultExpanded: true,
      order: 10
    },
    // Content section - supporting content management
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
      order: 15
    },
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
      href: '/app/account/billing',
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
    // DevOps section - developer and operations tools
    {
      id: 'devops',
      name: 'DevOps',
      items: [
        {
          id: 'devops-overview',
          name: 'Overview',
          href: '/app/devops',
          icon: Server,
          description: 'DevOps dashboard and quick access',
          permissions: [],
          order: 0
        },
        {
          id: 'git-providers',
          name: 'Git Providers',
          href: '/app/devops/git',
          icon: GitBranch,
          description: 'GitHub, GitLab, Gitea, and other git providers',
          permissions: ['git.providers.read'],
          order: 1
        },
        {
          id: 'repositories',
          name: 'Repositories',
          href: '/app/devops/repositories',
          icon: FolderGit2,
          description: 'Synced Git repositories from all providers',
          permissions: ['git.repositories.read'],
          order: 2
        },
        {
          id: 'pipelines',
          name: 'Pipelines',
          href: '/app/devops/pipelines',
          icon: Workflow,
          description: 'CI/CD pipelines for automated deployments',
          permissions: ['devops.pipelines.read'],
          order: 3
        },
        {
          id: 'runners',
          name: 'Runners',
          href: '/app/devops/runners',
          icon: Server,
          description: 'Self-hosted workflow execution agents',
          permissions: ['cicd.runners.read', 'git.runners.read'],
          order: 4
        },
        {
          id: 'webhooks',
          name: 'Webhooks',
          href: '/app/devops/webhooks',
          icon: '🔗',
          description: 'Manage webhook endpoints and events',
          permissions: ['webhook.read'],
          order: 5
        },
        {
          id: 'integrations',
          name: 'Integrations',
          href: '/app/devops/integrations',
          icon: Puzzle,
          description: 'Third-party service integrations and webhooks',
          permissions: ['integrations.read'],
          order: 6
        },
        {
          id: 'api-keys',
          name: 'API Keys',
          href: '/app/devops/api-keys',
          icon: Key,
          description: 'API keys and authentication tokens',
          permissions: ['api.manage_keys'],
          order: 7
        }
      ],
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'cicd.runners.read', 'webhook.read', 'integrations.read', 'api.manage_keys'],
      collapsible: true,
      defaultExpanded: false,
      order: 20  // After Content (15)
    },
    // System section - infrastructure only
    {
      id: 'system',
      name: 'System',
      items: [
        {
          id: 'services',
          name: 'Services',
          href: '/app/system/services',
          icon: '🌐',
          description: 'Configure service routing, load balancing, and proxy settings',
          permissions: ['admin.settings.update'],
          order: 1
        },
        {
          id: 'workers',
          name: 'Workers',
          href: '/app/system/workers',
          icon: '🤖',
          description: 'Manage background workers and job processing',
          permissions: ['system.workers.read'],
          order: 2
        },
        {
          id: 'storage',
          name: 'File Storage',
          href: '/app/system/storage',
          icon: HardDrive,
          description: 'Configure storage providers for file management',
          permissions: ['admin.storage.manage', 'admin.storage.read'],
          order: 3
        },
        {
          id: 'audit-logs',
          name: 'Audit Logs',
          href: '/app/system/audit-logs',
          icon: '📋',
          description: 'System audit and activity logs',
          permissions: ['admin.audit.read'],
          order: 4
        }
      ],
      permissions: ['admin.settings.update', 'system.workers.read', 'admin.storage.manage', 'admin.storage.read', 'admin.audit.read'],
      collapsible: true,
      defaultExpanded: false,
      order: 25  // After DevOps (20)
    },
    // Administration section - super admin features (always last)
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
          id: 'roles',
          name: 'Roles & Permissions',
          href: '/app/admin/roles',
          icon: UserCheck,
          description: 'Manage roles and permission assignments',
          permissions: ['admin.role.read'],
          order: 2
        },
        {
          id: 'admin-marketplace',
          name: 'Marketplace',
          href: '/app/admin/marketplace',
          icon: Store,
          description: 'Manage marketplace listings and plugins',
          permissions: ['admin.marketplace.read'],
          order: 3
        },
        {
          id: 'impersonation-admin',
          name: 'Impersonation',
          href: '/app/admin/impersonation',
          icon: UserCog,
          description: 'User impersonation for support and debugging',
          permissions: ['admin.impersonation.read'],
          order: 4
        },
        {
          id: 'maintenance',
          name: 'Maintenance',
          href: '/app/admin/maintenance',
          icon: '🔧',
          description: 'System maintenance and health monitoring',
          permissions: ['admin.maintenance.backup', 'admin.maintenance.cleanup'],
          order: 5
        },
        {
          id: 'settings',
          name: 'Settings',
          href: '/app/admin/settings',
          icon: Settings,
          description: 'Platform configuration and settings',
          permissions: ['admin.settings.read'],
          order: 6
        }
      ],
      permissions: ['admin.access'],
      collapsible: true,
      defaultExpanded: false,
      order: 30  // Always last
    }
  ]
};

export default defaultNavigationConfig;