import { act, render } from '@testing-library/react';
import { MemoryRouter, useNavigate } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { NavigationProvider, useNavigation } from './NavigationContext';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { defaultNavigationConfig } from '@/shared/utils/navigation';

// buildNavigationConfig runs on every location change. An extension item that
// targets a CORE section must land in a copy of that section, never in the
// shared defaultNavigationConfig, or it accumulates one duplicate per build.
describe('NavigationProvider extension items targeting a core section', () => {
  const coreSection = defaultNavigationConfig.sections![0];

  let latest: ReturnType<typeof useNavigation> | null = null;
  let go: ((path: string) => void) | null = null;
  const Probe = () => {
    latest = useNavigation();
    go = useNavigate();
    return null;
  };

  const snapshot = () =>
    (defaultNavigationConfig.sections || []).map((s) => [s.id, s.items.map((i) => i.id)]);

  afterEach(() => featureRegistry.clear());

  it('adds exactly one entry across rebuilds and leaves the defaults untouched', () => {
    const before = snapshot();
    featureRegistry.registerNavItems('test-ext', [
      { label: 'Ext Probe Item', path: '/app/ext-probe', section: coreSection.id },
    ]);
    const store = configureStore({
      reducer: { auth: (state = { user: null }) => state },
    });

    render(
      <Provider store={store}>
        <MemoryRouter initialEntries={['/app']}>
          <NavigationProvider>
            <Probe />
          </NavigationProvider>
        </MemoryRouter>
      </Provider>,
    );

    for (const path of ['/app/a', '/app/b', '/app/c', '/app/d']) {
      act(() => go!(path));
    }

    const section = latest!.config.sections!.find((s) => s.id === coreSection.id)!;
    expect(section.items.filter((i) => i.id === 'ext-probe-item')).toHaveLength(1);
    expect(snapshot()).toEqual(before);
  });
});

// A nav item's `slotPrefix` (e.g. the DevOps section's 'ci-cd' item, whose
// page hosts extension tabs through the devops.ci-cd.tab.* component-slot
// seam) unions in every registered slot's declared permissions under that
// prefix — so an extension permission core never writes still shows the item
// to a user who holds only it. fc-34 round 3.
describe('NavigationProvider slot-permission union (item.slotPrefix)', () => {
  const devopsSection = defaultNavigationConfig.sections!.find((s) => s.id === 'devops')!;
  const ciCdItemBefore = devopsSection.items.find((i) => i.id === 'ci-cd')!;

  let latest: ReturnType<typeof useNavigation> | null = null;
  const Probe = () => {
    latest = useNavigation();
    return null;
  };

  const renderProvider = () =>
    render(
      <Provider store={configureStore({ reducer: { auth: (state = { user: null }) => state } })}>
        <MemoryRouter initialEntries={['/app']}>
          <NavigationProvider>
            <Probe />
          </NavigationProvider>
        </MemoryRouter>
      </Provider>,
    );

  const ciCdItem = () =>
    latest!.config.sections!.find((s) => s.id === 'devops')!.items.find((i) => i.id === 'ci-cd')!;

  afterEach(() => featureRegistry.clear());

  it('sanity: the ci-cd nav item declares a slotPrefix, so this test targets the real feature', () => {
    expect(ciCdItemBefore.slotPrefix).toBe('devops.ci-cd.tab.');
  });

  it('adds nothing when no slot under the prefix declares a permission', () => {
    renderProvider();
    expect(ciCdItem().permissions).toEqual(ciCdItemBefore.permissions);
  });

  it('unions a registered slot\'s declared permission into the item\'s own gate', () => {
    featureRegistry.registerComponentSlots({ 'devops.ci-cd.tab.module-builds': () => null });
    featureRegistry.registerSlotMeta({
      'devops.ci-cd.tab.module-builds': { permissions: ['ext.example.read'] },
    });

    renderProvider();

    expect(ciCdItem().permissions).toEqual(
      expect.arrayContaining([...(ciCdItemBefore.permissions ?? []), 'ext.example.read']),
    );
  });

  it('also unions the permission into the item\'s own section, not just the item', () => {
    featureRegistry.registerComponentSlots({ 'devops.ci-cd.tab.module-builds': () => null });
    featureRegistry.registerSlotMeta({
      'devops.ci-cd.tab.module-builds': { permissions: ['ext.example.read'] },
    });

    renderProvider();

    const section = latest!.config.sections!.find((s) => s.id === 'devops')!;
    expect(section.permissions).toEqual(expect.arrayContaining(['ext.example.read']));
  });

  it('picks up a slot registered AFTER the provider has already rendered', () => {
    renderProvider();
    expect(ciCdItem().permissions).toEqual(ciCdItemBefore.permissions);

    act(() => {
      featureRegistry.registerComponentSlots({ 'devops.ci-cd.tab.module-builds': () => null });
      featureRegistry.registerSlotMeta({
        'devops.ci-cd.tab.module-builds': { permissions: ['ext.example.read'] },
      });
    });

    expect(ciCdItem().permissions).toEqual(
      expect.arrayContaining([...(ciCdItemBefore.permissions ?? []), 'ext.example.read']),
    );
  });

  it('never writes the extension permission literal into the static config itself', () => {
    featureRegistry.registerComponentSlots({ 'devops.ci-cd.tab.module-builds': () => null });
    featureRegistry.registerSlotMeta({
      'devops.ci-cd.tab.module-builds': { permissions: ['ext.example.read'] },
    });
    renderProvider();

    expect(ciCdItemBefore.permissions).not.toContain('ext.example.read');
  });

  // A slotPrefix's job is to WIDEN an already-restricted item/section (the OR
  // gate now also accepts the slot's permission). An item or section with NO
  // permissions of its own is open to everyone (hasPermissions treats an
  // empty/undefined array as unrestricted) — unioning a slot permission into
  // that would flip it from open to "must hold this one permission", which is
  // backwards. These two temporarily borrow an item/section that already
  // ships with no permissions and add a slotPrefix only for the test.
  it('leaves an item with no permissions of its own open, even when its slot declares one', () => {
    const openItem = devopsSection.items.find((i) => i.id === 'devops-overview')!;
    expect(openItem.permissions).toEqual([]);
    const originalSlotPrefix = openItem.slotPrefix;
    openItem.slotPrefix = 'test.open-item.tab.';
    try {
      featureRegistry.registerComponentSlots({ 'test.open-item.tab.probe': () => null });
      featureRegistry.registerSlotMeta({
        'test.open-item.tab.probe': { permissions: ['ext.example.read'] },
      });

      renderProvider();

      const item = latest!.config.sections!
        .find((s) => s.id === 'devops')!
        .items.find((i) => i.id === 'devops-overview')!;
      expect(item.permissions).toEqual([]);
    } finally {
      openItem.slotPrefix = originalSlotPrefix;
    }
  });

  it('leaves a section with no permissions of its own open, even when a member item\'s slot declares one', () => {
    const accountSection = defaultNavigationConfig.sections!.find((s) => s.id === 'account')!;
    expect(accountSection.permissions).toBeUndefined();
    const openItem = accountSection.items.find((i) => i.id === 'preferences')!;
    const originalSlotPrefix = openItem.slotPrefix;
    openItem.slotPrefix = 'test.open-section.tab.';
    try {
      featureRegistry.registerComponentSlots({ 'test.open-section.tab.probe': () => null });
      featureRegistry.registerSlotMeta({
        'test.open-section.tab.probe': { permissions: ['ext.example.read'] },
      });

      renderProvider();

      const section = latest!.config.sections!.find((s) => s.id === 'account')!;
      expect(section.permissions).toBeUndefined();
    } finally {
      openItem.slotPrefix = originalSlotPrefix;
    }
  });
});
