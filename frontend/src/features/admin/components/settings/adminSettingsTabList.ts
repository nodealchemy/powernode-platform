// The one Admin Settings tab list. AdminSettingsTabs renders it as the tab bar;
// AdminSettingsPage derives its breadcrumb and routes from it, so the three
// cannot drift apart.

import { useEffect, useState } from 'react';
import {
  Mail, Server,
  LayoutDashboard, ShieldAlert,
  Network, Lock, Wrench, Puzzle, KeyRound, Bot,
  icons as lucideIcons
} from 'lucide-react';
import { featureRegistry, FeatureSettingsTab } from '@/shared/services/featureRegistry';

export const ADMIN_SETTINGS_BASE = '/app/admin/settings';

export interface AdminSettingsTab {
  id: string;
  label: string;
  href: string;
  icon: React.ComponentType<React.SVGProps<SVGSVGElement>>;
  description: string;
  requiredPermissions?: readonly string[];
}

export const CORE_ADMIN_SETTINGS_TABS = [
  {
    id: 'overview',
    label: 'Overview',
    href: ADMIN_SETTINGS_BASE,
    icon: LayoutDashboard,
    description: 'System overview and quick admin actions'
    // No specific permissions required - covered by parent admin.settings.read
  },
  {
    id: 'extensions',
    label: 'Extensions',
    href: `${ADMIN_SETTINGS_BASE}/extensions`,
    icon: Puzzle,
    description: 'Manage platform extensions and modules',
    requiredPermissions: ['admin.settings.read']
  },
  {
    id: 'email',
    label: 'Email Settings',
    href: `${ADMIN_SETTINGS_BASE}/email`,
    icon: Mail,
    description: 'Configure email providers and delivery settings',
    requiredPermissions: ['admin.settings.email']
  },
  {
    id: 'proxy',
    label: 'Reverse Proxy',
    href: `${ADMIN_SETTINGS_BASE}/proxy`,
    icon: Network,
    description: 'Configure reverse proxy URL handling and trusted hosts',
    requiredPermissions: ['admin.settings.read']
  },
  {
    id: 'security',
    label: 'Security',
    href: `${ADMIN_SETTINGS_BASE}/security`,
    icon: Lock,
    description: 'Security policies and access controls',
    requiredPermissions: ['admin.settings.security']
  },
  {
    id: 'rate-limiting',
    label: 'Rate Limiting',
    href: `${ADMIN_SETTINGS_BASE}/rate-limiting`,
    icon: ShieldAlert,
    description: 'Configure API rate limits and monitor usage patterns',
    requiredPermissions: ['admin.settings.security']
  },
  {
    id: 'infrastructure',
    label: 'Infrastructure',
    href: `${ADMIN_SETTINGS_BASE}/infrastructure`,
    icon: Server,
    description: 'Redis connection and infrastructure configuration',
    requiredPermissions: ['admin.settings.read']
  },
  {
    id: 'vault',
    label: 'Vault & Secrets',
    href: `${ADMIN_SETTINGS_BASE}/vault`,
    icon: KeyRound,
    description: 'HashiCorp Vault connection and key management',
    requiredPermissions: ['admin.settings.security']
  },
  {
    id: 'development',
    label: 'Development',
    href: `${ADMIN_SETTINGS_BASE}/development`,
    icon: Wrench,
    description: 'Manage extensions and development tools',
    requiredPermissions: ['admin.settings.read']
  },
  {
    // D3. Listed under the same read permission as its siblings so the tab is
    // visible to anyone who can view settings; the CONTROL inside it gates
    // separately on settings.manage, which is the permission its write
    // endpoint names.
    id: 'autonomy',
    label: 'Autonomy',
    href: `${ADMIN_SETTINGS_BASE}/autonomy`,
    icon: Bot,
    description: 'Platform-wide switches for autonomous agent cadences',
    requiredPermissions: ['admin.settings.read']
  }
] as const satisfies readonly AdminSettingsTab[];

export type CoreAdminSettingsTabId = (typeof CORE_ADMIN_SETTINGS_TABS)[number]['id'];

// An extension-registered tab (featureRegistry.registerSettingsTabs), in the
// core tab shape. String icon names resolve against the Lucide set, falling
// back to Puzzle. Core names no extension: a registered tab is present only
// when its owning extension is loaded.
export const toAdminSettingsTab = (tab: FeatureSettingsTab): AdminSettingsTab => ({
  id: tab.id,
  label: tab.label,
  href: tab.path,
  icon: (tab.icon && lucideIcons[tab.icon as keyof typeof lucideIcons]) || Puzzle,
  description: tab.description || '',
  requiredPermissions: tab.permission ? [tab.permission] : undefined,
});

// The registry's settings tabs, re-read whenever an extension registers one.
export const useRegisteredSettingsTabs = (): FeatureSettingsTab[] => {
  const [, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(() => {
    return featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion()));
  }, []);
  return featureRegistry.getSettingsTabs();
};

// Core tabs followed by extension-registered ones.
export const useAdminSettingsTabs = (): AdminSettingsTab[] => [
  ...CORE_ADMIN_SETTINGS_TABS,
  ...useRegisteredSettingsTabs().map(toAdminSettingsTab),
];

// The tab a path belongs to: an exact match, else the tab whose href is a
// prefix of it (the overview's base path matches only exactly).
export const findActiveSettingsTab = (tabs: AdminSettingsTab[], pathname: string): AdminSettingsTab | undefined =>
  tabs.find((tab) => tab.href === pathname) ||
  tabs.find((tab) => tab.href !== ADMIN_SETTINGS_BASE && pathname.startsWith(`${tab.href}/`));
