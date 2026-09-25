import { defaultNavigationConfig } from '@/shared/utils/navigation';
import { hasAccess } from '@/shared/utils/permissionUtils';
import { CONTROL_PERMISSIONS } from '@/shared/constants/controlPermissions';
import type { User } from '@/shared/services/slices/authSlice';

const sections = defaultNavigationConfig.sections ?? [];
const section = (id: string) => sections.find((s) => s.id === id);
const itemIds = (id: string) => (section(id)?.items ?? []).map((i) => i.id);

describe('defaultNavigationConfig — AI category consolidation', () => {
  it('removes the orphan "cost" and "developer" sidebar sections', () => {
    expect(section('cost')).toBeUndefined();
    expect(section('developer')).toBeUndefined();
  });

  it('exposes Observability and Cost as AI Platform items (fc-42: Operations merged into Observability)', () => {
    expect(itemIds('ai-platform')).toEqual(expect.arrayContaining(['ai-observability', 'ai-cost']));
    expect(sections.flatMap((s) => s.items.map((i) => i.id))).not.toContain('ai-operations');
  });

  it('points the Cost and Observability items at their domain routes', () => {
    const ai = section('ai-platform')?.items ?? [];
    expect(ai.find((i) => i.id === 'ai-cost')?.href).toBe('/app/ai/cost');
    expect(ai.find((i) => i.id === 'ai-observability')?.href).toBe('/app/ai/observability');
  });

  it('re-homes the Developer Portal into the DevOps section', () => {
    expect(itemIds('devops')).toContain('developer-portal');
    const portal = section('devops')?.items.find((i) => i.id === 'developer-portal');
    expect(portal?.href).toBe('/app/developer');
    expect(portal?.permissions).toContain('api.manage_keys');
  });

  it('gates Cost on cost-domain permissions only (no role checks)', () => {
    const cost = section('ai-platform')?.items.find((i) => i.id === 'ai-cost');
    expect(cost?.permissions).toEqual(
      expect.arrayContaining(['ai.finops.view', 'ai.roi.read', 'ai.analytics.read']),
    );
  });

  it('no longer surfaces Credits as a standalone sidebar item (it lives under Cost)', () => {
    const allItemIds = sections.flatMap((s) => s.items.map((i) => i.id));
    expect(allItemIds).not.toContain('cost-credits');
    expect(allItemIds).not.toContain('developer-traces');
  });
});

// fc-20: the delegations management UI is now linked into navigation rather
// than orphaned. Placed in the Account section, right after Users (both are
// "who has access to this account" concerns), gated on the same permissions
// Api::V1::DelegationsController#authorize_delegation_management! itself
// checks -- permissions only, never roles.
describe('defaultNavigationConfig — Delegations (fc-20)', () => {
  it('is in the account section, right after Users', () => {
    const account = itemIds('account');
    const usersIndex = account.indexOf('users');
    const delegationsIndex = account.indexOf('delegations');

    expect(usersIndex).toBeGreaterThanOrEqual(0);
    expect(delegationsIndex).toBe(usersIndex + 1);
  });

  it('points at the URL-addressable Delegations tab on the Profile page', () => {
    const delegations = section('account')?.items.find((i) => i.id === 'delegations');
    expect(delegations?.href).toBe('/app/profile/delegations');
  });

  it('gates on the same permissions the server enforces, permissions only', () => {
    const delegations = section('account')?.items.find((i) => i.id === 'delegations');
    expect(delegations?.permissions).toEqual(
      expect.arrayContaining(['accounts.manage', 'admin.access']),
    );
    expect(delegations).not.toHaveProperty('roles');
  });
});

describe('defaultNavigationConfig — DevOps nav permission alignment', () => {
  const devopsItem = (id: string) =>
    (section('devops')?.items ?? []).find((i) => i.id === id);

  it('gates the Containers hub on every leaf\'s dedicated devops.* family', () => {
    expect(devopsItem('containers')?.permissions).toEqual([
      'devops.docker.read',
      'devops.swarm.read',
      'devops.kubernetes.read',
    ]);
  });

  it('references no catalog-absent swarm.clusters.read/docker.hosts.read/kubernetes.clusters.read', () => {
    const allPerms = sections.flatMap((s) =>
      (s.permissions ?? []).concat((s.items ?? []).flatMap((i) => i.permissions ?? [])),
    );
    expect(allPerms).not.toContain('swarm.clusters.read');
    expect(allPerms).not.toContain('docker.hosts.read');
    expect(allPerms).not.toContain('kubernetes.clusters.read');
  });

  // fc-25 review item 7: the section-level `permissions` aggregate is an
  // OR gate (NavigationSection only hides the section header if the user
  // has NONE of these) — every entry in it must be pulled by at least one
  // child item, or it is dead weight left over from a deleted child (here,
  // Connections' File Storage tab, deleted in fc-25, which used to need
  // admin.storage.read; that permission belongs solely to Admin ▸ Storage
  // now, a different section entirely).
  it('the DevOps section aggregate carries exactly the union of its own items\' permissions', () => {
    const devops = section('devops');
    const childPerms = new Set((devops?.items ?? []).flatMap((i) => i.permissions ?? []));
    expect(new Set(devops?.permissions ?? [])).toEqual(childPerms);
    expect(devops?.permissions).not.toContain('admin.storage.read');
  });
});

// fc-44: the DevOps regroup — seven items, Containers as one hub, API Keys
// as its own item, Connections renamed Integrations & Webhooks at a new URL.
describe('defaultNavigationConfig — DevOps regroup (fc-44)', () => {
  const devops = () => section('devops')?.items ?? [];

  it('has exactly the seven DevOps items, in order', () => {
    expect(devops().map((i) => i.name)).toEqual([
      'Overview',
      'Source Control',
      'CI/CD',
      'Integrations & Webhooks',
      'API Keys',
      'Containers',
      'Developer Portal',
    ]);
  });

  it('points each item at its route', () => {
    expect(devops().map((i) => i.href)).toEqual([
      '/app/devops',
      '/app/devops/source-control',
      '/app/devops/ci-cd',
      '/app/devops/integrations',
      '/app/devops/api-keys',
      '/app/devops/containers',
      '/app/developer',
    ]);
  });

  it('gates Integrations & Webhooks and API Keys on their own permissions', () => {
    const byId = (id: string) => devops().find((i) => i.id === id);
    expect(byId('integrations')?.permissions).toEqual(['integrations.read', 'webhook.read']);
    expect(byId('api-keys')?.permissions).toEqual(['api.manage_keys']);
  });
});

// fc-41: one Control item (in AI Work since fc-43) replaces Autonomy, Governance,
// Budgets and Approval Chains. It carries the same permissions as the Control
// route (CONTROL_PERMISSIONS) — permissions only, never roles.
describe('defaultNavigationConfig — Control (fc-41)', () => {
  const control = () => section('ai-work')?.items.find((i) => i.id === 'ai-control');
  const userWith = (permissions: string[]) => ({ permissions } as unknown as User);

  it('links Control from the AI Work section, and nothing links the pages it replaced', () => {
    expect(control()).toMatchObject({ name: 'Control', href: '/app/ai/control' });
    const allItems = sections.flatMap((s) => s.items);
    ['ai-autonomy', 'ai-governance', 'ai-budgets', 'ai-approval-chains'].forEach((id) =>
      expect(allItems.map((i) => i.id)).not.toContain(id));
    expect(allItems.filter((i) => /\/app\/ai\/(governance|approval-chains|agents\/autonomy|control\/budgets)/.test(i.href ?? '')))
      .toEqual([]);
  });

  // A section is shown only to holders of one of ITS permissions; a user
  // whose only Control permission (e.g. ai.goals.manage) is missing there
  // would never see the section, and so never the Control item inside it.
  it.each(CONTROL_PERMISSIONS)('shows the AI Work section, and Control in it, to a holder of only %s', (permission) => {
    const user = userWith([permission]);
    expect(hasAccess(user, section('ai-work')?.permissions)).toBe(true);
    expect(hasAccess(user, control()?.permissions)).toBe(true);
  });

  it('is gated on exactly the Control route permissions', () => {
    expect([...(control()?.permissions ?? [])].sort()).toEqual([...CONTROL_PERMISSIONS].sort());
    expect(hasAccess(userWith(['ai.governance.read']), control()?.permissions)).toBe(true);
    expect(hasAccess(userWith(['ai.teams.read']), control()?.permissions)).toBe(false);
  });
});

// fc-43: the one 16-item AI section became three groups, each of at most 7
// items, whose names predict their contents.
describe('defaultNavigationConfig — AI Agents / Work / Platform (fc-43)', () => {
  const byId = (sectionId: string, id: string) => section(sectionId)?.items.find((i) => i.id === id);
  const userWith = (permissions: string[]) => ({ permissions } as unknown as User);

  it('groups the AI items into AI Agents, AI Work and AI Platform, in that order', () => {
    expect(section('ai')?.name).toBe('AI Agents');
    expect(section('ai-work')?.name).toBe('AI Work');
    expect(section('ai-platform')?.name).toBe('AI Platform');
    expect(itemIds('ai')).toEqual(['ai-overview', 'ai-agents', 'ai-teams', 'ai-skills', 'ai-prompts', 'ai-knowledge']);
    expect(itemIds('ai-work')).toEqual([
      'ai-missions', 'ai-campaigns', 'ai-execution', 'ai-conversations', 'ai-chat-channels', 'ai-control',
    ]);
    expect(itemIds('ai-platform')).toEqual([
      'ai-providers', 'ai-model-router', 'ai-mcp', 'ai-data-sources', 'ai-observability', 'ai-cost',
    ]);
    const order = (id: string) => section(id)?.order ?? 0;
    expect(order('ai')).toBeLessThan(order('ai-work'));
    expect(order('ai-work')).toBeLessThan(order('ai-platform'));
  });

  // Equality ratchet: a section growing past 7 fails, and so does a listed
  // one that got back under (remove it here). Account is fc-45's regroup.
  const KNOWN_OVERSIZED = ['account'];

  it('keeps every section at 7 items or fewer', () => {
    const oversized = sections.filter((s) => s.items.length > 7).map((s) => s.id);
    expect(oversized).toEqual(KNOWN_OVERSIZED);
  });

  it('names the MCP item MCP and links nothing to the deleted Infrastructure or Learning Insights pages', () => {
    expect(byId('ai-platform', 'ai-mcp')).toMatchObject({ name: 'MCP', href: '/app/ai/mcp' });
    const hrefs = sections.flatMap((s) => s.items.map((i) => i.href ?? ''));
    expect(hrefs.filter((h) => /^\/app\/ai\/(infrastructure|learning)(\/|$)/.test(h))).toEqual([]);
  });

  it('links Conversations from AI Work, gated like ConversationsController#index', () => {
    expect(byId('ai-work', 'ai-conversations')).toMatchObject({
      href: '/app/ai/conversations',
      permissions: ['ai.conversations.read'],
    });
  });

  it.each(['ai', 'ai-work', 'ai-platform'])('opens %s to a holder of any one of its items\' permissions, and only them', (id) => {
    const s = section(id);
    for (const item of s?.items ?? []) {
      for (const permission of item.permissions ?? []) {
        expect(hasAccess(userWith([permission]), s?.permissions)).toBe(true);
      }
    }
    const itemPermissions = new Set((s?.items ?? []).flatMap((i) => i.permissions ?? []));
    expect([...(s?.permissions ?? [])].filter((p) => !itemPermissions.has(p))).toEqual([]);
  });
});

// fc-45: the user menu carries ONE entry per destination — 'My Profile' and
// 'Account Settings' used to both open /app/profile.
describe('defaultNavigationConfig — user menu (fc-45)', () => {
  const menu = defaultNavigationConfig.userMenuItems;

  it('has unique hrefs', () => {
    const hrefs = menu.map((i) => i.href);
    expect(hrefs).toEqual(Array.from(new Set(hrefs)));
  });

  it('has exactly one profile entry, labelled My Profile', () => {
    const profile = menu.filter((i) => i.href === '/app/profile');
    expect(profile).toHaveLength(1);
    expect(profile[0]).toMatchObject({ id: 'profile', name: 'My Profile' });
    expect(menu.map((i) => i.id)).not.toContain('account-settings');
  });
});
