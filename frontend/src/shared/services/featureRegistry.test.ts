import { featureRegistry } from './featureRegistry';

// getComponentSlotIds — the listing a host uses to render a FAMILY of views
// under one prefix (the status drawer's `platform.status.drawer.<kind>.<view>`).

const View = () => null;

describe('featureRegistry.getComponentSlotIds', () => {
  beforeEach(() => featureRegistry.clear());

  it('keeps two views registered in separate calls, sorted by id rather than by registration order', () => {
    featureRegistry.registerComponentSlots({ 'host.kind.signals': View });
    featureRegistry.registerComponentSlots({ 'host.kind.boot_replay': View });

    expect(featureRegistry.getComponentSlotIds('host.kind.')).toEqual([
      'host.kind.boot_replay',
      'host.kind.signals',
    ]);
  });

  it('lists only ids under the prefix — not a sibling that merely starts with the same letters', () => {
    featureRegistry.registerComponentSlots({
      'host.kind.signals': View,
      'host.kind_pool.signals': View,
      'host.other.signals': View,
      'elsewhere.host.kind.signals': View,
    });

    expect(featureRegistry.getComponentSlotIds('host.kind.')).toEqual(['host.kind.signals']);
  });

  it('returns an empty list when nothing is registered under the prefix', () => {
    featureRegistry.registerComponentSlots({ 'host.other.signals': View });
    expect(featureRegistry.getComponentSlotIds('host.kind.')).toEqual([]);
  });
});

describe('featureRegistry public route roles', () => {
  afterEach(() => featureRegistry.clear());

  it('resolves no path for a role nothing registered', () => {
    expect(featureRegistry.getPublicRoutePath('pricing')).toBeUndefined();
  });

  it('resolves the path of the public route registered for a role', () => {
    featureRegistry.registerPublicRoutes('ext', [
      { path: '/register', component: () => null },
      { path: '/ext-pricing', component: () => null, role: 'pricing' },
    ]);
    expect(featureRegistry.getPublicRoutePath('pricing')).toBe('/ext-pricing');
  });
});
