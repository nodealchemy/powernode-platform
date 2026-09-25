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

// registerSlotMeta / getSlotMeta / getSlotPermissions — the optional metadata
// (label, permissions) a slot registration can carry alongside its component,
// kept in a parallel map so getComponentSlot's return shape never changes.

describe('featureRegistry slot metadata', () => {
  beforeEach(() => featureRegistry.clear());

  it('has no metadata for a slot nothing registered metadata for', () => {
    featureRegistry.registerComponentSlots({ 'host.kind.signals': View });
    expect(featureRegistry.getSlotMeta('host.kind.signals')).toBeUndefined();
  });

  it('resolves the metadata registered for a slot id', () => {
    featureRegistry.registerSlotMeta({
      'host.kind.signals': { label: 'Signals', permissions: ['host.signals.read'] },
    });
    expect(featureRegistry.getSlotMeta('host.kind.signals')).toEqual({
      label: 'Signals',
      permissions: ['host.signals.read'],
    });
  });

  describe('getSlotPermissions', () => {
    it('unions permissions across every registered slot under the prefix, deduplicated', () => {
      featureRegistry.registerComponentSlots({ 'host.kind.a': View, 'host.kind.b': View });
      featureRegistry.registerSlotMeta({
        'host.kind.a': { permissions: ['host.a.read', 'host.shared.read'] },
        'host.kind.b': { permissions: ['host.b.read', 'host.shared.read'] },
      });

      expect(featureRegistry.getSlotPermissions('host.kind.')).toEqual(
        expect.arrayContaining(['host.a.read', 'host.b.read', 'host.shared.read']),
      );
      expect(featureRegistry.getSlotPermissions('host.kind.')).toHaveLength(3);
    });

    it('is empty when a registered slot under the prefix declares no metadata', () => {
      featureRegistry.registerComponentSlots({ 'host.kind.a': View });
      expect(featureRegistry.getSlotPermissions('host.kind.')).toEqual([]);
    });

    it('is empty when nothing is registered under the prefix at all', () => {
      expect(featureRegistry.getSlotPermissions('host.kind.')).toEqual([]);
    });

    it('ignores metadata registered for a slot under a different prefix', () => {
      featureRegistry.registerComponentSlots({ 'host.other.a': View });
      featureRegistry.registerSlotMeta({ 'host.other.a': { permissions: ['host.other.read'] } });
      expect(featureRegistry.getSlotPermissions('host.kind.')).toEqual([]);
    });
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

// An extension presents the intervention-policy DOMAINS it owns (label, blurb,
// icon), and core's policy panel builds its sections in that order. The server
// owns which category is in which domain; this is presentation only.
describe('featureRegistry policy domains', () => {
  afterEach(() => featureRegistry.clear());

  const domain = (key: string) => ({ key, label: key.toUpperCase(), description: `${key} blurb` });

  it('returns nothing when no extension registered a domain', () => {
    expect(featureRegistry.getPolicyDomains()).toEqual([]);
    expect(featureRegistry.getPolicyDomains('ext')).toEqual([]);
  });

  it('keeps registration order within and across namespaces', () => {
    featureRegistry.registerPolicyDomains('ext', [domain('b'), domain('a')]);
    featureRegistry.registerPolicyDomains('other_ext', [domain('c')]);

    expect(featureRegistry.getPolicyDomains().map((d) => d.key)).toEqual(['b', 'a', 'c']);
    expect(featureRegistry.getPolicyDomains('ext').map((d) => d.key)).toEqual(['b', 'a']);
    expect(featureRegistry.getPolicyDomains('other_ext').map((d) => d.key)).toEqual(['c']);
  });

  it('replaces, not appends, a namespace that registers again', () => {
    featureRegistry.registerPolicyDomains('ext', [domain('old')]);
    featureRegistry.registerPolicyDomains('ext', [domain('new')]);

    expect(featureRegistry.getPolicyDomains('ext').map((d) => d.key)).toEqual(['new']);
  });

  it('is emptied by clear()', () => {
    featureRegistry.registerPolicyDomains('ext', [domain('a')]);
    featureRegistry.clear();

    expect(featureRegistry.getPolicyDomains()).toEqual([]);
  });
});
