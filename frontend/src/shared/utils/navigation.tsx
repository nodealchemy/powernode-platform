// Navigation Configuration
import {
  Home, Users, User, Settings,
  FileText, UserCheck,
  HelpCircle, LogOut, Bot, Brain, Bell,
  HardDrive, Workflow, Server, GitBranch,
  Plug, BookOpen, Activity, ShieldCheck,
  Container, Boxes,
  Play, Rocket, DollarSign, Code2, Building2, Megaphone,
  Route, MessageSquare, Share2, Lock, Lightbulb
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
      // Top-level rather than inside a section: the component status plane spans
      // core AND fleet, so filing it under AI or DevOps would say it belongs to
      // one of them. Granted to admin, owner, manager and member — a status page
      // only admins can open does not replace five pages a member could reach.
      id: 'platform-status',
      name: 'Status',
      href: '/app/status',
      icon: Activity,
      description: 'Every component, its verdict, and what is being done about it',
      permissions: ['platform.status.read'],
      order: 2
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
          // fc-26: routed but previously unlinked — reachable only by
          // typing the URL, and the guard's own basePath declaration was
          // the sole thing satisfying its own discoverability check.
          // Named "Learning Insights" rather than "Learning" — Knowledge's
          // own tab is already "Compound Learning", easy to confuse
          // otherwise. Gated on the same permission the route (DashboardPage
          // .tsx) and the backend (LearningController) both enforce.
          id: 'ai-learning-insights',
          name: 'Learning Insights',
          href: '/app/ai/learning',
          icon: Lightbulb,
          description: 'Improvement recommendations and trajectory insights from agent execution history',
          permissions: ['ai.analytics.read'],
          order: 7.5
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
          // fc-42: merged with the former Operations hub (AiOps/alerts/traces) —
          // one page, one Systems backend, one Circuit Breakers view. See
          // MONITORING_TABS (features/ai/monitoring/utils/monitoringFormatters.ts)
          // for the per-tab permissions this nav entry's own list summarizes.
          id: 'ai-observability',
          name: 'Observability',
          href: '/app/ai/observability',
          icon: Activity,
          description: 'Health, systems, circuit breakers, alerts, conversations, traces, and evaluation',
          permissions: ['ai.monitoring.read', 'ai.aiops.read', 'ai.conversations.read', 'ai_monitoring.read', 'ai.analytics.read'],
          order: 10
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
          // AI → Control: approvals, policies, budgets, safety, trust &
          // lineage, goals and compliance audit. Gated on the same list as the
          // /ai/control/* route (CONTROL_PERMISSIONS, pinned by the nav test).
          id: 'ai-control',
          name: 'Control',
          href: '/app/ai/control',
          icon: ShieldCheck,
          description: 'Approvals, policies, budgets, safety, trust and compliance audit',
          permissions: [
            'ai.agents.read', 'ai.proposals.view', 'ai.escalations.view', 'ai.approval_chains.manage',
            'ai.intervention_policies.manage', 'ai.governance.read', 'ai.kill_switch.manage',
            'ai.security.manage', 'ai.feedback.view', 'ai.goals.manage',
          ],
          order: 13
        },
        {
          // The only operator screen for chat-platform integrations the
          // server still serves (Api::V1::Chat::ChannelsController) — no
          // other page links to it, so without this it was reachable only by
          // typing the URL.
          id: 'ai-chat-channels',
          name: 'Chat Channels',
          href: '/app/ai/chat-channels',
          icon: MessageSquare,
          description: 'Manage external chat platform integrations',
          permissions: ['chat.channels.read'],
          order: 13.6
        },
      ],
      permissions: ['ai.agents.read', 'ai.conversations.read', 'ai.context.read', 'ai.providers.read', 'ai.analytics.read', 'ai.teams.read', 'ai.missions.read', 'ai.finops.view', 'ai.roi.read', 'ai.aiops.read', 'ai.monitoring.read', 'ai_monitoring.read', 'ai.governance.read', 'ai.routing.read', 'ai.approval_chains.manage', 'chat.channels.read'],
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
        // 'Billing' (order 4) is registered by the business extension via
        // featureRegistry.registerNavItems('business', [{ section: 'account', ... }]),
        // since billing is a commercial concern owned by that extension.
        {
          id: 'users',
          name: 'Users',
          href: '/app/profile/users',
          icon: Users,
          description: 'Manage your team members',
          permissions: ['team.read'],
          order: 5
        },
        // Delegations: grant another user account access scoped to a role or
        // specific permissions. Placed right after Users -- both are "who has
        // access to this account" concerns, and this is the resource-management
        // permission Api::V1::DelegationsController#authorize_delegation_management!
        // itself checks (permissions only, never roles).
        {
          id: 'delegations',
          name: 'Delegations',
          href: '/app/profile/delegations',
          icon: Share2,
          description: 'Grant other users delegated access to this account',
          permissions: ['accounts.manage', 'admin.access'],
          order: 6
        },
        {
          id: 'preferences',
          name: 'Preferences',
          href: '/app/profile/preferences',
          icon: Settings,
          description: 'Customize your experience',
          permissions: [],
          order: 7
        },
        {
          id: 'notifications',
          name: 'Notifications',
          href: '/app/profile/notifications',
          icon: Bell,
          description: 'Notification preferences',
          permissions: [],
          order: 8
        },
        {
          id: 'security',
          name: 'Security',
          href: '/app/profile/security',
          icon: ShieldCheck,
          description: 'Password, SSH keys, and security status',
          permissions: [],
          order: 9
        },
        {
          // fc-26: routed but previously unlinked — reachable only by typing
          // the URL. Not a ProfilePage tab like its Account siblings (its own
          // dashboard at /app/privacy), but "Account" is where an operator
          // looking for consent/export/deletion controls would expect it.
          id: 'privacy',
          name: 'Privacy Center',
          href: '/app/privacy',
          icon: Lock,
          description: 'Consent preferences, data export, and data deletion requests',
          permissions: [],
          order: 10
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
          // fc-34: this used to list system.module_builds.read (an
          // extension-owned permission core must not name) so a Module
          // Builds tab lived here too. That tab now mounts through CiCdPage's
          // generic devops.ci-cd.tab.* component-slot seam, and `slotPrefix`
          // below closes the discoverability gap that left open: a user
          // holding ONLY the extension's slot permission (registered via
          // featureRegistry.registerSlotMeta, never written here) still sees
          // this nav entry, because NavigationContext's buildNavigationConfig
          // unions every registered slot's declared permissions into this
          // item's own gate (featureRegistry.getSlotPermissions). Core still
          // never names the permission — the union is by prefix, not by
          // literal string.
          description: 'Pipelines and runner management',
          permissions: ['devops.pipelines.read', 'git.runners.read'],
          slotPrefix: 'devops.ci-cd.tab.',
          order: 3
        },
        {
          id: 'connections',
          name: 'Connections',
          href: '/app/devops/connections',
          icon: Plug,
          description: 'Integrations, webhooks, and API keys',
          permissions: ['integrations.read', 'webhook.read', 'api.manage_keys'],
          order: 4
        },
        {
          id: 'devops-sandboxes',
          name: 'Sandboxes',
          href: '/app/ai/execution/containers',
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
      // fc-34 review fix: dropped system.module_builds.read (extension-owned;
      // see the 'ci-cd' item's own comment above for the visibility decision).
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'git.runners.read', 'webhook.read', 'integrations.read', 'api.manage_keys', 'devops.containers.read', 'devops.swarm.read', 'devops.docker.read', 'devops.kubernetes.read'],
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
          permissions: ['admin.maintenance.backup', 'admin.maintenance.cleanup', 'admin.maintenance.mode'],
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