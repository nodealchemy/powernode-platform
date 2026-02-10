// Navigation Configuration
import {
  Home, BarChart3, Users, User, Settings, CreditCard,
  FileText, Package, UserCheck, Store,
  HelpCircle, LogOut, Bot, Brain, MessageSquare,
  HardDrive, Workflow, Server, GitBranch, FolderGit2,
  Puzzle, BookOpen, UserCog, Key, Shield, FileCode,
  CheckCircle2, Scale, Building2, Activity, ShieldCheck,
  FlaskConical, Boxes, MessagesSquare,
  Container, Coins, Database,
  Network, Layers, Lock, Rocket, HeartPulse,
  Play
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
    // Business section - enterprise SaaS monetization features
    {
      id: 'business',
      name: 'Business',
      enterpriseOnly: true,
      items: [
        {
          id: 'customers',
          name: 'Customers',
          href: '/app/business/customers',
          icon: Users,
          description: 'Customer management and insights',
          permissions: [],
          order: 1
        },
        {
          id: 'plans',
          name: 'Plans',
          href: '/app/business/plans',
          icon: Package,
          description: 'Manage pricing and subscription tiers',
          permissions: [],
          order: 2
        },
        {
          id: 'analytics',
          name: 'Analytics',
          href: '/app/business/analytics',
          icon: BarChart3,
          description: 'Revenue and growth metrics',
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
          id: 'ai-teams',
          name: 'Teams',
          href: '/app/ai/teams',
          icon: Users,
          description: 'Advanced multi-agent team orchestration',
          permissions: ['ai.teams.read'],
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
          id: 'ai-conversations',
          name: 'Conversations',
          href: '/app/ai/conversations',
          icon: MessageSquare,
          description: 'AI-powered conversations',
          permissions: ['ai.conversations.read'],
          order: 5
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
          description: 'Manage agent knowledge, prompts, skills, and document bases',
          permissions: ['ai.context.read'],
          order: 7
        },
        {
          id: 'ai-chat-channels',
          name: 'Chat Channels',
          href: '/app/ai/chat-channels',
          icon: MessagesSquare,
          description: 'Multi-platform chat gateway',
          permissions: ['ai.agents.read'],
          order: 8
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
          id: 'ai-monitoring',
          name: 'Monitoring',
          href: '/app/ai/monitoring',
          icon: Activity,
          description: 'Real-time AI system monitoring and metrics',
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
        {
          id: 'ai-billing',
          name: 'Billing',
          href: '/app/ai/billing',
          icon: Coins,
          description: 'Manage AI credits and outcome-based billing',
          permissions: ['ai.credits.read'],
          order: 12
        },
        {
          id: 'ai-sandbox',
          name: 'Sandbox',
          href: '/app/ai/sandbox',
          icon: FlaskConical,
          description: 'Test and experiment with AI capabilities',
          permissions: ['ai.agents.read'],
          order: 13
        }
      ],
      permissions: ['ai.agents.read', 'ai.workflows.read', 'ai.conversations.read', 'ai.context.read', 'ai.providers.read', 'ai.analytics.read', 'ai.credits.read', 'ai.teams.read'],
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
    // Account section - personal and team management (less frequent access)
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
          enterpriseOnly: true,
          order: 3
        }
      ],
      collapsible: true,
      defaultExpanded: false,
      order: 18
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
      enterpriseOnly: true
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
      enterpriseOnly: true
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
      enterpriseOnly: true
    },
    {
      id: 'configure-payments',
      name: 'Configure Payments',
      href: '/app/admin/settings/payment-gateways',
      icon: CreditCard,
      description: 'Set up payment processing',
      permissions: ['admin.billing.manage_gateways'],
      enterpriseOnly: true
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
          order: 1
        },
        {
          id: 'git-providers',
          name: 'Git Providers',
          href: '/app/devops/git',
          icon: GitBranch,
          description: 'GitHub, GitLab, Gitea, and other git providers',
          permissions: ['git.providers.read'],
          order: 2
        },
        {
          id: 'repositories',
          name: 'Repositories',
          href: '/app/devops/repositories',
          icon: FolderGit2,
          description: 'Synced Git repositories from all providers',
          permissions: ['git.repositories.read'],
          order: 3
        },
        {
          id: 'pipelines',
          name: 'Pipelines',
          href: '/app/devops/pipelines',
          icon: Workflow,
          description: 'DevOps pipelines for automated deployments',
          permissions: ['devops.pipelines.read'],
          order: 4
        },
        {
          id: 'runners',
          name: 'Runners',
          href: '/app/devops/runners',
          icon: Server,
          description: 'Self-hosted workflow execution agents',
          permissions: ['cicd.runners.read', 'git.runners.read'],
          order: 5
        },
        {
          id: 'webhooks',
          name: 'Webhooks',
          href: '/app/devops/webhooks',
          icon: '🔗',
          description: 'Manage webhook endpoints and events',
          permissions: ['webhook.read'],
          order: 6
        },
        {
          id: 'integrations',
          name: 'Integrations',
          href: '/app/devops/integrations',
          icon: Puzzle,
          description: 'Third-party service integrations and webhooks',
          permissions: ['integrations.read'],
          order: 7
        },
        {
          id: 'api-keys',
          name: 'API Keys',
          href: '/app/devops/api-keys',
          icon: Key,
          description: 'API keys and authentication tokens',
          permissions: ['api.manage_keys'],
          order: 8
        },
        {
          id: 'devops-containers',
          name: 'Containers',
          href: '/app/devops/containers',
          icon: Container,
          description: 'Sandboxed container execution and resource quotas',
          permissions: ['devops.containers.read'],
          order: 9
        },
        {
          id: 'swarm-clusters',
          name: 'Swarm Clusters',
          href: '/app/devops/swarm',
          icon: Server,
          description: 'Docker Swarm cluster management and orchestration',
          permissions: ['swarm.clusters.read'],
          order: 10
        },
        {
          id: 'swarm-services',
          name: 'Swarm Services',
          href: '/app/devops/swarm/services',
          icon: Layers,
          description: 'Manage Docker Swarm services and replicas',
          permissions: ['swarm.services.read'],
          order: 11
        },
        {
          id: 'swarm-stacks',
          name: 'Stacks',
          href: '/app/devops/swarm/stacks',
          icon: Boxes,
          description: 'Docker Compose stack deployments',
          permissions: ['swarm.stacks.read'],
          order: 12
        },
        {
          id: 'swarm-networks',
          name: 'Networks',
          href: '/app/devops/swarm/networks',
          icon: Network,
          description: 'Docker Swarm overlay networks',
          permissions: ['swarm.networks.read'],
          order: 13
        },
        {
          id: 'swarm-secrets',
          name: 'Secrets & Configs',
          href: '/app/devops/swarm/secrets',
          icon: Lock,
          description: 'Docker Swarm secrets and config objects',
          permissions: ['swarm.secrets.read'],
          order: 14
        },
        {
          id: 'swarm-deployments',
          name: 'Deployments',
          href: '/app/devops/swarm/deployments',
          icon: Rocket,
          description: 'Swarm deployment history and timeline',
          permissions: ['swarm.deployments.read'],
          order: 15
        },
        {
          id: 'swarm-health',
          name: 'Health Monitor',
          href: '/app/devops/swarm/health',
          icon: HeartPulse,
          description: 'Multi-cluster health monitoring and alerts',
          permissions: ['swarm.events.read'],
          order: 16
        },
        {
          id: 'docker-hosts',
          name: 'Docker Hosts',
          href: '/app/devops/docker',
          icon: HardDrive,
          description: 'Standalone Docker host management',
          permissions: ['docker.hosts.read'],
          order: 17
        },
        {
          id: 'docker-containers',
          name: 'Containers',
          href: '/app/devops/docker/containers',
          icon: Container,
          description: 'Docker container lifecycle management',
          permissions: ['docker.containers.read'],
          order: 18
        },
        {
          id: 'docker-images',
          name: 'Images',
          href: '/app/devops/docker/images',
          icon: Layers,
          description: 'Docker image management and registry pulls',
          permissions: ['docker.images.read'],
          order: 19
        },
        {
          id: 'docker-networks',
          name: 'Docker Networks',
          href: '/app/devops/docker/networks',
          icon: Network,
          description: 'Docker host network management',
          permissions: ['docker.networks.read'],
          order: 20
        },
        {
          id: 'docker-volumes',
          name: 'Docker Volumes',
          href: '/app/devops/docker/volumes',
          icon: Database,
          description: 'Docker host volume management',
          permissions: ['docker.volumes.read'],
          order: 21
        },
        {
          id: 'docker-activities',
          name: 'Docker Activities',
          href: '/app/devops/docker/activities',
          icon: Activity,
          description: 'Docker container lifecycle activity log',
          permissions: ['docker.activities.read'],
          order: 22
        },
        {
          id: 'docker-health',
          name: 'Docker Health',
          href: '/app/devops/docker/health',
          icon: HeartPulse,
          description: 'Docker host health monitoring and alerts',
          permissions: ['docker.events.read'],
          order: 23
        }
      ],
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'cicd.runners.read', 'webhook.read', 'integrations.read', 'api.manage_keys', 'devops.containers.read', 'swarm.clusters.read', 'swarm.services.read', 'swarm.stacks.read', 'swarm.networks.read', 'swarm.secrets.read', 'swarm.deployments.read', 'swarm.events.read', 'docker.hosts.read', 'docker.containers.read', 'docker.images.read', 'docker.networks.read', 'docker.volumes.read', 'docker.activities.read', 'docker.events.read'],
      collapsible: true,
      defaultExpanded: false,
      order: 20
    },
    // Supply Chain section - software supply chain security
    {
      id: 'supply-chain',
      name: 'Supply Chain',
      items: [
        {
          id: 'sc-overview',
          name: 'Overview',
          href: '/app/supply-chain',
          icon: Shield,
          description: 'Supply chain security dashboard',
          permissions: ['supply_chain.read'],
          order: 1
        },
        {
          id: 'sc-sboms',
          name: 'SBOMs',
          href: '/app/supply-chain/sboms',
          icon: FileCode,
          description: 'Software Bill of Materials',
          permissions: ['supply_chain.read'],
          order: 2
        },
        {
          id: 'sc-attestations',
          name: 'Attestations',
          href: '/app/supply-chain/attestations',
          icon: CheckCircle2,
          description: 'Build provenance and attestations',
          permissions: ['supply_chain.read'],
          order: 3
        },
        {
          id: 'sc-containers',
          name: 'Container Images',
          href: '/app/supply-chain/containers',
          icon: Package,
          description: 'Container image security',
          permissions: ['supply_chain.read'],
          order: 4
        },
        {
          id: 'sc-licenses',
          name: 'License Compliance',
          href: '/app/supply-chain/licenses',
          icon: Scale,
          description: 'License policies and violations',
          permissions: ['supply_chain.read'],
          order: 5
        },
        {
          id: 'sc-vendors',
          name: 'Vendor Risk',
          href: '/app/supply-chain/vendors',
          icon: Building2,
          description: 'Third-party vendor management',
          permissions: ['supply_chain.read'],
          order: 6
        }
      ],
      permissions: ['supply_chain.read'],
      collapsible: true,
      defaultExpanded: false,
      order: 22
    },
    // System section - infrastructure management
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
      order: 25
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
          id: 'impersonation-admin',
          name: 'Impersonation',
          href: '/app/admin/impersonation',
          icon: UserCog,
          description: 'User impersonation for support and debugging',
          permissions: ['admin.impersonation.read'],
          order: 3
        },
        {
          id: 'admin-marketplace',
          name: 'Marketplace',
          href: '/app/admin/marketplace',
          icon: Store,
          description: 'Manage marketplace listings and plugins',
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
        },
        {
          id: 'maintenance',
          name: 'Maintenance',
          href: '/app/admin/maintenance',
          icon: '🔧',
          description: 'System maintenance and health monitoring',
          permissions: ['admin.maintenance.backup', 'admin.maintenance.cleanup'],
          order: 6
        }
      ],
      permissions: ['admin.access'],
      collapsible: true,
      defaultExpanded: false,
      order: 30
    }
  ]
};

export default defaultNavigationConfig;