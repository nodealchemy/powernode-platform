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
