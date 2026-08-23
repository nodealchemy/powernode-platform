// Navigation Configuration
import {
  Home, Users, User, Settings,
  FileText, UserCheck,
  HelpCircle, LogOut, Bot, Brain, Bell,
  HardDrive, Workflow, Server, GitBranch,
  Plug, BookOpen, Activity, ShieldCheck,
  Container, Boxes,
  Play, Rocket, DollarSign, Code2, Gauge, Building2, Megaphone,
  Shield, Route, ClipboardCheck
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
          id: 'ai-autonomy',
          name: 'Autonomy',
          href: '/app/ai/agents/autonomy',
          icon: Shield,
          description: 'Agent trust, lineage, budgets, and the kill switch',
          permissions: ['ai.agents.read'],
          order: 2.5
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
          id: 'ai-campaigns',
          name: 'Campaigns',
          href: '/app/ai/campaigns',
          icon: Megaphone,
          description: 'Autonomous, repeatable improvement campaigns',
          permissions: ['ai.campaigns.read'],
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
          id: 'ai-model-router',
          name: 'Model Router',
          href: '/app/ai/infrastructure/model-router',
          icon: Route,
          description: 'Model routing rules and bandit performance',
          permissions: ['ai.routing.read'],
          order: 9.5
        },
        {
          id: 'ai-observability',
          name: 'Observability',
          href: '/app/ai/observability',
          icon: Activity,
          description: 'Health, systems, conversations, and evaluation',
          permissions: ['ai.analytics.read'],
          order: 10
        },
        {
          id: 'ai-operations',
          name: 'Operations',
          href: '/app/ai/operations',
          icon: Gauge,
          description: 'Real-time AiOps, alerts, and execution traces',
          permissions: ['ai.aiops.read', 'ai_monitoring.read'],
          order: 11
        },
        {
          id: 'ai-cost',
          name: 'Cost',
          href: '/app/ai/cost',
          icon: DollarSign,
          description: 'Credits, FinOps, ROI, and outcome billing',
          permissions: ['ai.finops.view', 'ai.roi.read', 'ai.analytics.read'],
          order: 12
        },
        {
          id: 'ai-governance',
          name: 'Governance',
          href: '/app/ai/governance',
          icon: ShieldCheck,
          description: 'AI governance policies and compliance',
          permissions: ['ai.governance.read'],
          order: 13
        },
        {
          id: 'ai-approval-chains',
          name: 'Approval Chains',
          href: '/app/ai/approval-chains',
          icon: ClipboardCheck,
          description: 'Define reusable multi-step approval workflows',
          permissions: ['ai.approval_chains.manage'],
          order: 13.5
        },
      ],
      permissions: ['ai.agents.read', 'ai.conversations.read', 'ai.context.read', 'ai.providers.read', 'ai.analytics.read', 'ai.teams.read', 'ai.missions.read', 'ai.finops.view', 'ai.roi.read', 'ai.aiops.read', 'ai_monitoring.read', 'ai.governance.read', 'ai.routing.read', 'ai.approval_chains.manage'],
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
      // Items mirror the Profile page tabs (pages/app/account/ProfilePage.tsx),
      // so the sidebar and the in-page tabs stay in lockstep. Each links to the
      // matching /app/profile/* tab route.
      items: [
        {
          id: 'profile',
          name: 'My Profile',
          href: '/app/profile',
          icon: User,
          description: 'Your personal information',
          permissions: [],
          order: 1
        },
        {
          id: 'account',
          name: 'Account',
          href: '/app/profile/account',
          icon: Building2,
          description: 'Account details and status',
          permissions: [],
          order: 2
        },
        // 'Subscription' (order 3) is registered by the business extension via
        // featureRegistry.registerNavItems('business', [{ section: 'account', ... }]),
        // since billing/subscription is a commercial concern owned by that extension.
        {
          id: 'users',
          name: 'Users',
          href: '/app/profile/users',
          icon: Users,
          description: 'Manage your team members',
          permissions: ['team.read'],
          order: 5
        },
        {
          id: 'preferences',
          name: 'Preferences',
          href: '/app/profile/preferences',
          icon: Settings,
          description: 'Customize your experience',
          permissions: [],
          order: 6
        },
        {
          id: 'notifications',
          name: 'Notifications',
          href: '/app/profile/notifications',
          icon: Bell,
          description: 'Notification preferences',
          permissions: [],
          order: 7
        },
        {
          id: 'security',
          name: 'Security',
          href: '/app/profile/security',
          icon: ShieldCheck,
          description: 'Password, SSH keys, and security status',
          permissions: [],
          order: 8
        }
        // 'Billing' (order 4) is registered by the business extension via
        // featureRegistry.registerNavItems('business', [{ section: 'account', ... }]),
        // slotting in after Subscription.
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
          name: 'Overview',
          href: '/app/devops',
          icon: Activity,
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
          description: 'Pipelines, runners, and module build management',
          permissions: ['devops.pipelines.read', 'git.runners.read', 'system.module_builds.read'],
          order: 3
        },
        {
          id: 'connections',
          name: 'Connections',
          href: '/app/devops/connections',
          icon: Plug,
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
          permissions: ['devops.swarm.read'],
          order: 6
        },
        {
          id: 'docker',
          name: 'Docker',
          href: '/app/devops/docker',
          icon: HardDrive,
          description: 'Docker hosts, containers, images, and monitoring',
          permissions: ['devops.docker.read'],
          order: 7
        },
        {
          id: 'kubernetes',
          name: 'Kubernetes',
          href: '/app/devops/kubernetes',
          icon: Boxes,
          description: 'K3s and kubeadm clusters, nodes, and workloads',
          permissions: ['devops.kubernetes.read'],
          order: 8
        },
        {
          id: 'developer-portal',
          name: 'Developer Portal',
          href: '/app/developer',
          icon: Code2,
          description: 'API documentation, code samples, and API keys',
          permissions: ['api.manage_keys'],
          order: 9
        }
      ],
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'git.runners.read', 'system.module_builds.read', 'webhook.read', 'integrations.read', 'api.manage_keys', 'admin.storage.read', 'devops.containers.read', 'devops.swarm.read', 'devops.docker.read', 'devops.kubernetes.read'],
      collapsible: true,
      defaultExpanded: true,
      order: 11
    },
    // NOTE: the former orphan "Cost" and "Developer" sections were consolidated:
    // FinOps/ROI/Credits/Outcome-Billing now live in the AI section's Cost hub
    // (/app/ai/cost); Execution Traces moved under the AI "Operations" item; and
    // the Developer Portal moved into the DevOps section above.
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
    // 'Billing Center' is registered by the business extension via
    // featureRegistry.registerNavItems('business', [{ section: 'userMenu', ... }]).
    {
      id: 'help-support',
      name: 'Help & Support',
      href: 'https://github.com/nodealchemy/powernode-platform/discussions',
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
    // 'Create Plan', 'View Analytics', and 'Configure Payments' are registered
    // by the business extension via featureRegistry.registerNavItems('business',
    // [{ section: 'quickActions', ... }]).
    {
      id: 'invite-team',
      name: 'Invite Team Member',
      href: '/app/profile/users',
      icon: UserCheck,
      description: 'Add someone to your team'
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
          id: 'admin-accounts',
          name: 'Accounts',
          href: '/app/admin/accounts',
          icon: Building2,
          description: 'Provision tenant accounts',
          permissions: ['admin.account.create'],
          // order 3 is taken by the business extension's 'Impersonation' item.
          order: 4
        },
        // 'Impersonation' (order 3) is registered by the business extension via
        // featureRegistry.registerNavItems('business', [{ section: 'admin', ... }]);
        // the impersonation page/route/permission (admin.user.impersonate) live there.
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