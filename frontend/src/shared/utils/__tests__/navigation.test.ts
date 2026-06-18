import { defaultNavigationConfig } from '@/shared/utils/navigation';

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
