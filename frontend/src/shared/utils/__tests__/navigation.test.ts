import { defaultNavigationConfig } from '@/shared/utils/navigation';
import { hasAccess } from '@/shared/utils/permissionUtils';
import type { User } from '@/shared/services/slices/authSlice';

const sections = defaultNavigationConfig.sections ?? [];
const section = (id: string) => sections.find((s) => s.id === id);
const itemIds = (id: string) => (section(id)?.items ?? []).map((i) => i.id);

describe('defaultNavigationConfig — AI category consolidation', () => {
  it('removes the orphan "cost" and "developer" sidebar sections', () => {
    expect(section('cost')).toBeUndefined();
    expect(section('developer')).toBeUndefined();
  });

  it('exposes Observability, Operations, and Cost as AI section items', () => {
    expect(itemIds('ai')).toEqual(
      expect.arrayContaining(['ai-observability', 'ai-operations', 'ai-cost', 'ai-governance']),
    );
  });

  it('points the Cost and Operations items at their domain routes', () => {
    const ai = section('ai')?.items ?? [];
    expect(ai.find((i) => i.id === 'ai-cost')?.href).toBe('/app/ai/cost');
    expect(ai.find((i) => i.id === 'ai-operations')?.href).toBe('/app/ai/operations');
  });

  it('re-homes the Developer Portal into the DevOps section', () => {
    expect(itemIds('devops')).toContain('developer-portal');
    const portal = section('devops')?.items.find((i) => i.id === 'developer-portal');
    expect(portal?.href).toBe('/app/developer');
    expect(portal?.permissions).toContain('api.manage_keys');
  });

  it('gates Cost on cost-domain permissions only (no role checks)', () => {
    const cost = section('ai')?.items.find((i) => i.id === 'ai-cost');
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

  it('gates Swarm/Docker/Kubernetes on the dedicated devops.* families', () => {
    expect(devopsItem('swarm')?.permissions).toContain('devops.swarm.read');
    expect(devopsItem('docker')?.permissions).toContain('devops.docker.read');
    expect(devopsItem('kubernetes')?.permissions).toContain('devops.kubernetes.read');
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

// fc-31: one Budgets page, linked from the AI section under the same label as
// its title and breadcrumb, gated on the permission its route guard and the
// list endpoint check — permissions only, never roles.
describe('defaultNavigationConfig — Budgets (fc-31)', () => {
  const budgets = () => section('ai')?.items.find((i) => i.id === 'ai-budgets');
  const userWith = (permissions: string[]) => ({ permissions } as unknown as User);

  it('links the Budgets page from the AI section', () => {
    expect(budgets()).toMatchObject({ name: 'Budgets', href: '/app/ai/control/budgets' });
    const allBudgetHrefs = sections.flatMap((s) => s.items).filter((i) => /budget/i.test(i.href ?? ''));
    expect(allBudgetHrefs.map((i) => i.id)).toEqual(['ai-budgets']);
  });

  it('is gated on ai.agents.read alone, which shows it to readers and hides it otherwise', () => {
    expect(budgets()?.permissions).toEqual(['ai.agents.read']);
    expect(hasAccess(userWith(['ai.agents.read']), budgets()?.permissions)).toBe(true);
    expect(hasAccess(userWith(['ai.autonomy.manage']), budgets()?.permissions)).toBe(false);
  });
});
