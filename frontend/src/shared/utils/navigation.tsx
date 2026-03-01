// Navigation Configuration
import {
  Home, BarChart3, Users, User, Settings, CreditCard,
  FileText, Package, UserCheck,
  HelpCircle, LogOut, Bot, Brain,
  HardDrive, Workflow, Server, GitBranch,
  Puzzle, BookOpen, UserCog, Activity, ShieldCheck,
  Container,
  Play, Rocket
} from 'lucide-react';
import { NavigationConfig } from '@/shared/types/navigation';

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
  ],

  sections: [
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
          id: 'ai-teams',
          name: 'Teams',
          href: '/app/ai/teams',
          icon: Users,
          description: 'Advanced multi-agent team orchestration',
          permissions: ['ai.teams.read'],
          order: 3
        },
        {
          id: 'ai-missions',
          name: 'Missions',
          href: '/app/ai/missions',
          icon: Rocket,
          description: 'AI-assisted development missions',
          permissions: ['ai.missions.read'],
          order: 4
        },
        {
          id: 'ai-workflows',
          name: 'Workflows',
          href: '/app/ai/workflows',
          icon: Workflow,
          description: 'Advanced visual workflow builder for developers',
          permissions: ['ai.workflows.read'],
          order: 12
        },
        {
          id: 'ai-execution',
          name: 'Execution',
          href: '/app/ai/execution',
          icon: Play,
          description: 'Monitor and manage active AI agent execution',
          permissions: ['ai.agents.read'],
          order: 6
        },
        {
          id: 'ai-knowledge',
          name: 'Knowledge',
          href: '/app/ai/knowledge',
          icon: BookOpen,
          description: 'Manage agent knowledge, prompts, skills, and memory tiers',
          permissions: ['ai.context.read'],
          order: 7
        },
        {
          id: 'ai-infrastructure',
          name: 'Infrastructure',
          href: '/app/ai/infrastructure',
          icon: Server,
          description: 'Configure AI providers, MCP servers, and model routing',
          permissions: ['ai.providers.read'],
          order: 9
        },
        {
          id: 'ai-observability',
          name: 'Observability',
          href: '/app/ai/observability',
          icon: Activity,
          description: 'Real-time monitoring, evaluation, and cost tracking',
          permissions: ['ai.analytics.read'],
          order: 10
        },
        {
          id: 'ai-governance',
          name: 'Governance',
          href: '/app/ai/governance',
          icon: ShieldCheck,
          description: 'AI governance policies and compliance',
          permissions: ['ai.workflows.read'],
          order: 11
        },
      ],
      permissions: ['ai.agents.read', 'ai.workflows.read', 'ai.conversations.read', 'ai.context.read', 'ai.providers.read', 'ai.analytics.read', 'ai.teams.read', 'ai.missions.read'],
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
          id: 'knowledge-base',
          name: 'Knowledge Base',
          href: '/app/content/kb',
          icon: HelpCircle,
          description: 'Browse articles, guides, and documentation',
          permissions: ['kb.read'],
          order: 1
        },
        {
          id: 'pages',
          name: 'Pages',
          href: '/app/content/pages',
          icon: FileText,
          description: 'Manage content pages and documentation',
          permissions: ['page.read'],
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
    // Marketing section — registered dynamically via marketing extension (featureRegistry)
    // Account section - personal and team management
    {
      id: 'account',
      name: 'Account',
      items: [
        {
          id: 'users',
          name: 'Users',
          href: '/app/users',
          icon: Users,
          description: 'Manage your team members',
          permissions: ['team.read'],
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
          id: 'billing',
          name: 'Billing',
          href: '/app/account/billing',
          icon: CreditCard,
          description: 'Invoices and payment processing',
          permissions: ['admin.billing.read'],
          extensionSlug: 'enterprise',
          order: 3
        }
      ],
      collapsible: true,
      defaultExpanded: true,
      order: 3
    },
    // DevOps section - developer and operations tools
    {
      id: 'devops',
      name: 'DevOps',
      items: [
        {
          id: 'devops-overview',
          name: 'DevOps',
          href: '/app/devops',
          icon: Server,
          description: 'DevOps dashboard and quick access',
          permissions: [],
          order: 1
        },
        {
          id: 'source-control',
          name: 'Source Control',
          href: '/app/devops/source-control',
          icon: GitBranch,
          description: 'Git providers and repository management',
          permissions: ['git.providers.read', 'git.repositories.read'],
          order: 2
        },
        {
          id: 'ci-cd',
          name: 'CI/CD',
          href: '/app/devops/ci-cd',
          icon: Workflow,
          description: 'Pipelines and runner management',
          permissions: ['devops.pipelines.read', 'cicd.runners.read'],
          order: 3
        },
        {
          id: 'connections',
          name: 'Connections',
          href: '/app/devops/connections',
          icon: Puzzle,
          description: 'Integrations, webhooks, API keys, and file storage',
          permissions: ['integrations.read', 'webhook.read', 'api.manage_keys', 'admin.storage.read'],
          order: 4
        },
        {
          id: 'devops-sandboxes',
          name: 'Sandboxes',
          href: '/app/devops/sandboxes',
          icon: Container,
          description: 'Sandboxed container execution and resource quotas',
          permissions: ['devops.containers.read'],
          order: 5
        },
        {
          id: 'swarm',
          name: 'Swarm',
          href: '/app/devops/swarm',
          icon: Server,
          description: 'Docker Swarm clusters, services, stacks, and operations',
          permissions: ['swarm.clusters.read'],
          order: 6
        },
        {
          id: 'docker',
          name: 'Docker',
          href: '/app/devops/docker',
          icon: HardDrive,
          description: 'Docker hosts, containers, images, and monitoring',
          permissions: ['docker.hosts.read'],
          order: 7
        }
      ],
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'cicd.runners.read', 'webhook.read', 'integrations.read', 'api.manage_keys', 'admin.storage.read', 'devops.containers.read', 'swarm.clusters.read', 'docker.hosts.read'],
      collapsible: true,
      defaultExpanded: true,
      order: 11
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
      description: 'Subscription and payment details',
      extensionSlug: 'enterprise'
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
      description: 'Set up a new subscription plan',
      extensionSlug: 'enterprise'
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
      description: 'Check your latest metrics',
      extensionSlug: 'enterprise'
    },
    {
      id: 'configure-payments',
      name: 'Configure Payments',
      href: '/app/admin/settings/payment-gateways',
      icon: CreditCard,
      description: 'Set up payment processing',
      permissions: ['admin.billing.manage_gateways'],
      extensionSlug: 'enterprise'
    },
    {
      id: 'create-ai-agent',
      name: 'Create AI Agent',
      href: '/app/ai/agents',
      icon: Bot,
      description: 'Create a new AI agent for automation',
      permissions: ['ai.agents.create']
    }
  ]
};

// Admin-specific navigation overrides
export const adminNavigationOverrides = {
  sections: [
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
          id: 'impersonation-admin',
          name: 'Impersonation',
          href: '/app/admin/impersonation',
          icon: UserCog,
          description: 'User impersonation for support and debugging',
          permissions: ['admin.impersonation.read'],
          order: 3
        },
        {
          id: 'settings',
          name: 'Settings',
          href: '/app/admin/settings',
          icon: Settings,
          description: 'Platform configuration and settings',
          permissions: ['admin.settings.read'],
          order: 5
        },
        {
          id: 'maintenance',
          name: 'Maintenance',
          href: '/app/admin/maintenance',
          icon: '🔧',
          description: 'System maintenance and health monitoring',
          permissions: ['admin.maintenance.backup', 'admin.maintenance.cleanup'],
          order: 6
        },
        {
          id: 'workers',
          name: 'Workers',
          href: '/app/admin/workers',
          icon: '🤖',
          description: 'Manage background workers and job processing',
          permissions: ['admin.settings.read'],
          order: 7
        },
        {
          id: 'storage',
          name: 'File Storage',
          href: '/app/admin/storage',
          icon: HardDrive,
          description: 'Configure storage providers for file management',
          permissions: ['admin.storage.manage', 'admin.storage.read'],
          order: 8
        },
        {
          id: 'audit-logs',
          name: 'Audit Logs',
          href: '/app/admin/audit-logs',
          icon: '📋',
          description: 'System audit and activity logs',
          permissions: ['admin.audit.read'],
          order: 9
        }
      ],
      permissions: ['admin.access', 'admin.storage.manage', 'admin.storage.read', 'admin.audit.read'],
      collapsible: true,
      defaultExpanded: false,
      order: 30
    }
  ]
};

export default defaultNavigationConfig;