// Navigation Configuration
import {
  Home, Users, User, Settings,
  FileText, UserCheck,
  HelpCircle, LogOut, Bot, Brain, Bell,
  HardDrive, Workflow, Server, GitBranch,
  Plug, BookOpen, Activity, ShieldCheck,
  Container, Key,
  Play, Rocket, DollarSign, Code2, Building2, Megaphone,
  Route, MessageSquare, MessageSquareText, MessagesSquare, Share2, Lock, Puzzle, Database
} from 'lucide-react';
import type { NavigationConfig, NavigationItem } from '@/shared/types/navigation';
import { CONTROL_PERMISSIONS } from '@/shared/constants/controlPermissions';
import { KNOWLEDGE_PERMISSIONS } from '@/shared/constants/knowledgePermissions';
import { MCP_PERMISSIONS } from '@/shared/constants/mcpPermissions';

// AI → Agents: the agents themselves and what they know (fc-43).
const aiAgentsItems: NavigationItem[] = [
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
    id: 'ai-skills',
    name: 'Skills',
    href: '/app/ai/skills',
    icon: Puzzle,
    description: 'Skill bundles agents use, and the skill graph',
    permissions: ['ai.skills.read'],
    order: 4
  },
  {
    id: 'ai-prompts',
    name: 'Prompts',
    href: '/app/ai/prompts',
    icon: MessageSquareText,
    description: 'Prompt templates for agents and workflows',
    permissions: ['ai.prompt_templates.read'],
    order: 5
  },
  {
    // Contexts, Tiered Memory, RAG, Graph and Learning; each tab is
    // gated on its own permission, so any one of them opens the item.
    id: 'ai-knowledge',
    name: 'Knowledge',
    href: '/app/ai/knowledge',
    icon: BookOpen,
    description: 'Contexts, tiered memory, document bases, the knowledge graph and learning',
    permissions: KNOWLEDGE_PERMISSIONS,
    order: 6
  },
];

// AI → Work: what agents do, and the controls over it (fc-43).
const aiWorkItems: NavigationItem[] = [
  {
    id: 'ai-missions',
    name: 'Missions',
    href: '/app/ai/missions',
    icon: Rocket,
    description: 'AI-assisted development missions',
    permissions: ['ai.missions.read'],
    order: 1
  },
  {
    id: 'ai-campaigns',
    name: 'Campaigns',
    href: '/app/ai/campaigns',
    icon: Megaphone,
    description: 'Autonomous, repeatable improvement campaigns',
    permissions: ['ai.campaigns.read'],
    order: 2
  },
  {
    id: 'ai-execution',
    name: 'Execution',
    href: '/app/ai/execution',
    icon: Play,
    description: 'Monitor and manage active AI agent execution',
    permissions: ['ai.agents.read'],
    order: 3
  },
  {
    // The conversation list (export, unarchive, detail) had a route and
    // a gate but no sidebar item. Gated like ConversationsController#index.
    id: 'ai-conversations',
    name: 'Conversations',
    href: '/app/ai/conversations',
    icon: MessagesSquare,
    description: 'Agent conversations: browse, continue, export and archive',
    permissions: ['ai.conversations.read'],
    order: 4
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
    order: 5
  },
  {
    // AI → Control: approvals, policies, budgets, safety, trust &
    // lineage, goals and compliance audit. Gated on the same list as the
    // /ai/control/* route.
    id: 'ai-control',
    name: 'Control',
    href: '/app/ai/control',
    icon: ShieldCheck,
    description: 'Approvals, policies, budgets, safety, trust and compliance audit',
    permissions: CONTROL_PERMISSIONS,
    order: 6
  },
];

// AI → Platform: what agents run on (fc-43; MCP was the "Infrastructure" hub).
const aiPlatformItems: NavigationItem[] = [
  {
    id: 'ai-providers',
    name: 'Providers',
    href: '/app/ai/providers',
    icon: Plug,
    description: 'AI providers and their credentials',
    permissions: ['ai.providers.read'],
    order: 1
  },
  {
    id: 'ai-model-router',
    name: 'Model Router',
    href: '/app/ai/model-router',
    icon: Route,
    description: 'Model routing rules and bandit performance',
    permissions: ['ai.routing.read'],
    order: 2
  },
  {
    // Servers, Apps, Studio and Sessions — the MCP tabs of the former
    // "Infrastructure" hub, whose name did not say it held MCP.
    id: 'ai-mcp',
    name: 'MCP',
    href: '/app/ai/mcp',
    icon: Server,
    description: 'Model Context Protocol servers, apps, studio and sessions',
    permissions: MCP_PERMISSIONS,
    order: 3
  },
  {
    id: 'ai-data-sources',
    name: 'Data Sources',
    href: '/app/ai/data-sources',
    icon: Database,
    description: 'External data sources agents can query',
    permissions: ['ai.data_sources.read'],
    order: 4
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
    order: 5
  },
  {
    id: 'ai-cost',
    name: 'Cost',
    href: '/app/ai/cost',
    icon: DollarSign,
    description: 'Credits, FinOps, ROI, and outcome billing',
    permissions: ['ai.finops.view', 'ai.roi.read', 'ai.analytics.read'],
    order: 6
  },
];

/** A section opens to a holder of any of its items' permissions, and only those. */
const openedByItems = (items: NavigationItem[]): string[] =>
  Array.from(new Set(items.flatMap((item) => item.permissions ?? [])));

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
    // AI — three groups of at most 7 items each, named for what they hold
    // (fc-43; the single AI section had grown to 16 items). The Agents group
    // keeps the 'ai' id extensions register into.
    {
      id: 'ai',
      name: 'AI Agents',
      items: aiAgentsItems,
      permissions: openedByItems(aiAgentsItems),
      collapsible: true,
      defaultExpanded: true,
      order: 10
    },
    {
      id: 'ai-work',
      name: 'AI Work',
      items: aiWorkItems,
      permissions: openedByItems(aiWorkItems),
      collapsible: true,
      defaultExpanded: true,
      order: 11
    },
    {
      id: 'ai-platform',
      name: 'AI Platform',
      items: aiPlatformItems,
      permissions: openedByItems(aiPlatformItems),
      collapsible: true,
      defaultExpanded: true,
      order: 12
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
          id: 'integrations',
          name: 'Integrations & Webhooks',
          href: '/app/devops/integrations',
          icon: Plug,
          description: 'Integrations and webhook endpoints',
          permissions: ['integrations.read', 'webhook.read'],
          order: 4
        },
        {
          id: 'api-keys',
          name: 'API Keys',
          href: '/app/devops/api-keys',
          icon: Key,
          description: 'Create, regenerate and revoke API keys',
          permissions: ['api.manage_keys'],
          order: 5
        },
        {
          // One hub for the container runtimes; its leaves (Docker, Swarm,
          // Kubernetes) live on the hub's own rail, each gated on its own
          // family, so this item shows when ANY leaf would. Sandboxes are not
          // a leaf: they live once, under AI › Execution (fc-32).
          id: 'containers',
          name: 'Containers',
          href: '/app/devops/containers',
          icon: Container,
          description: 'Docker, Swarm, and Kubernetes',
          permissions: ['devops.docker.read', 'devops.swarm.read', 'devops.kubernetes.read'],
          order: 6
        },
        {
          id: 'developer-portal',
          name: 'Developer Portal',
          href: '/app/developer',
          icon: Code2,
          description: 'API documentation and code samples',
          permissions: ['api.manage_keys'],
          order: 7
        }
      ],
      // fc-34 review fix: dropped system.module_builds.read (extension-owned;
      // see the 'ci-cd' item's own comment above for the visibility decision).
      permissions: ['git.providers.read', 'git.repositories.read', 'devops.pipelines.read', 'git.runners.read', 'integrations.read', 'webhook.read', 'api.manage_keys', 'devops.docker.read', 'devops.swarm.read', 'devops.kubernetes.read'],
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