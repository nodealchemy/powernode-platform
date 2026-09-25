import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { CiCdPage } from './CiCdPage';

// =============================================================================
// Mocks
//
// CiCdPage composes four static tabs plus, per the fc-34 review fix, any
// number of extension-contributed tabs discovered from the
// `devops.ci-cd.tab.*` component-slot prefix. The static tabs are stubbed so
// this file tests CiCdPage's own tab-switching + slot-discovery logic, not
// their internals (each has its own test file).
// =============================================================================

jest.mock('@/pages/app/devops/CiCdOverviewTab', () => ({
  CiCdOverviewTab: () => <div data-testid="ci-cd-overview-tab">Overview</div>,
}));

jest.mock('@/pages/app/devops/PipelinesPage', () => ({
  PipelinesPage: () => <div data-testid="pipelines-page">Pipelines</div>,
}));

jest.mock('@/features/devops/pipelines', () => ({
  RunnersPage: () => <div data-testid="runners-page">Runners</div>,
}));

jest.mock('@/pages/app/ai/DevOpsTemplatesPage', () => ({
  TemplatesContent: () => <div data-testid="templates-content">Templates</div>,
}));

jest.mock('@/shared/hooks/BreadcrumbContext', () => ({
  __esModule: true,
  BreadcrumbProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  useBreadcrumb: () => ({
    breadcrumbs: [],
    setBreadcrumbs: jest.fn(),
    getCurrentBreadcrumbs: () => [],
    setCurrentPage: jest.fn(),
  }),
}));

// The real TabContainer reads its `permissions`-filtered visible tabs off
// Redux — irrelevant to what this file tests (CiCdPage's own slot-discovery
// and tab-merging logic, not TabContainer's permission filtering, which has
// its own test file). Stubbed to a plain tab strip + `role="tab"` buttons.
// TabPanel is NOT mocked — its real implementation is pure prop-based
// filtering (`tabId !== activeTab ? null : children`), which is exactly the
// "only one panel visible" behaviour these tests rely on.
// Captures every `tabs` array CiCdPage hands to TabContainer (fc-34 round 3
// slot-metadata k1): TabContainer's OWN permission filtering is proven
// generically in TabContainer.test.tsx ("hides a tab whose permissions the
// user lacks" / "always shows a tab with no permissions declared") — what
// THIS file needs to prove is that CiCdPage correctly wires a slot's
// registered metadata (label, permissions) into the Tab object it passes
// down, so that generic filtering has the right input to act on.
const tabsPropCalls: Array<Array<{ id: string; label: string; path?: string; permissions?: string[] }>> = [];

jest.mock('@/shared/components/layout/TabContainer', () => {
  const actual = jest.requireActual('@/shared/components/layout/TabContainer');
  const { useNavigate } = jest.requireActual('react-router-dom');
  return {
    ...actual,
    // Real TabContainer navigates to `${basePath}${tab.path}` on click, THEN
    // calls onTabChange — CiCdPage's own effect re-derives `activeTab` from
    // the URL on every location change, so a click that only called
    // onTabChange (skipping the navigate) would have that effect immediately
    // stomp the click back to whatever the (unchanged) URL says.
    TabContainer: ({
      children,
      tabs,
      activeTab,
      onTabChange,
      basePath,
    }: {
      children?: React.ReactNode;
      tabs?: Array<{ id: string; label: string; path?: string; permissions?: string[] }>;
      activeTab?: string;
      onTabChange?: (tabId: string) => void;
      basePath?: string;
    }) => {
      const navigate = useNavigate();
      tabsPropCalls.push(tabs ?? []);
      return (
        <div>
          <div>
            {tabs?.map((tab) => (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={tab.id === activeTab}
                onClick={() => {
                  navigate(`${basePath ?? ''}${tab.path ?? ''}`);
                  onTabChange?.(tab.id);
                }}
              >
                {tab.label}
              </button>
            ))}
          </div>
          {children}
        </div>
      );
    },
  };
});

// =============================================================================
// Helpers
// =============================================================================

function renderPage(path = '/app/devops/ci-cd') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <CiCdPage />
    </MemoryRouter>,
  );
}

// =============================================================================
// Tests
// =============================================================================

describe('CiCdPage', () => {
  // No slot registered anywhere in this describe block yet — must run before
  // any test below registers one, since featureRegistry is a real singleton
  // with no unregister call and state persists across tests in this file.
  it('renders only the four static tabs when no devops.ci-cd.tab.* slot is registered', () => {
    renderPage();

    expect(screen.getByRole('tab', { name: 'Overview' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Pipelines' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Runners' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Templates' })).toBeInTheDocument();
    expect(screen.queryAllByRole('tab')).toHaveLength(4);
  });

  describe('with a devops.ci-cd.tab.* slot registered', () => {
    const SlotComponent: React.FC<{ onActionsReady?: (actions: unknown[]) => void }> = ({
      onActionsReady,
    }) => {
      React.useEffect(() => {
        onActionsReady?.([{ id: 'refresh', label: 'Refresh', onClick: jest.fn() }]);
        return () => onActionsReady?.([]);
      }, [onActionsReady]);
      return <div data-testid="module-builds-slot">Module Builds Slot</div>;
    };

    beforeAll(() => {
      // Registered once for this describe block — core never names the
      // extension; this simulates what extensions/system's register.ts does.
      featureRegistry.registerComponentSlots({
        'devops.ci-cd.tab.module-builds': SlotComponent as React.ComponentType<unknown>,
      });
    });

    it('adds a tab for the slot, labelled from its id', () => {
      renderPage();

      expect(screen.getByRole('tab', { name: 'Module builds' })).toBeInTheDocument();
      expect(screen.queryAllByRole('tab')).toHaveLength(5);
    });

    it('renders the slot component when its tab is active via URL', () => {
      renderPage('/app/devops/ci-cd/module-builds');

      expect(screen.getByTestId('module-builds-slot')).toBeInTheDocument();
      expect(screen.queryByTestId('ci-cd-overview-tab')).not.toBeInTheDocument();
    });

    it('marks the slot tab active from the URL and switches to it on click', () => {
      renderPage();

      expect(screen.getByTestId('ci-cd-overview-tab')).toBeInTheDocument();

      fireEvent.click(screen.getByRole('tab', { name: 'Module builds' }));

      expect(screen.getByTestId('module-builds-slot')).toBeInTheDocument();
      expect(screen.queryByTestId('ci-cd-overview-tab')).not.toBeInTheDocument();
    });

    it('bridges the slot component’s onActionsReady into the page actions', async () => {
      renderPage('/app/devops/ci-cd/module-builds');

      await waitFor(() =>
        expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument(),
      );
    });

    it('includes the slot tab label in the breadcrumb when active', () => {
      renderPage('/app/devops/ci-cd/module-builds');

      // Appears twice: the active tab button and the breadcrumb's last item.
      expect(screen.getAllByText('Module builds').length).toBeGreaterThanOrEqual(2);
    });
  });

  // fc-34 round 3: registerSlotMeta lets a slot declare its own label and
  // gating permissions, instead of CiCdPage deriving a label from the raw id
  // and leaving the tab ungated. Runs after the block above, which already
  // registered the `devops.ci-cd.tab.module-builds` component — this only
  // adds metadata for it (featureRegistry has no unregister, so the
  // component from the earlier block is still there).
  describe('with slot metadata registered for that slot', () => {
    beforeAll(() => {
      featureRegistry.registerSlotMeta({
        'devops.ci-cd.tab.module-builds': {
          label: 'Module Builds',
          permissions: ['ext.example.read'],
        },
      });
    });

    it('labels the tab from the metadata, in Title Case, instead of deriving one from the id', () => {
      tabsPropCalls.length = 0;
      renderPage();

      expect(screen.getByRole('tab', { name: 'Module Builds' })).toBeInTheDocument();
      expect(screen.queryByRole('tab', { name: 'Module builds' })).not.toBeInTheDocument();
    });

    // TabContainer.test.tsx already proves generically that a tab whose
    // `permissions` the user lacks is hidden, and that a tab with none
    // declared is always shown. What CiCdPage itself must get right is
    // wiring the slot's registered permissions into the Tab object at all —
    // proven here by inspecting what CiCdPage actually hands to TabContainer,
    // composing with that proof into "hidden without the permission" overall.
    it('wires the slot metadata\'s permissions into the tab CiCdPage hands to TabContainer', () => {
      tabsPropCalls.length = 0;
      renderPage();

      const lastTabs = tabsPropCalls[tabsPropCalls.length - 1];
      const moduleBuildsTab = lastTabs.find((t) => t.id === 'module-builds');
      expect(moduleBuildsTab?.permissions).toEqual(['ext.example.read']);
    });

    it('a static tab with no slot metadata still carries no permissions restriction', () => {
      tabsPropCalls.length = 0;
      renderPage();

      const lastTabs = tabsPropCalls[tabsPropCalls.length - 1];
      const overviewTab = lastTabs.find((t) => t.id === 'overview');
      expect(overviewTab?.permissions).toBeUndefined();
    });
  });

  // fc-34 round 3, item 3: proves the `[registryVersion]` dependency, not just
  // that a slot present at mount renders — a slot registered by an extension
  // that finishes loading asynchronously, after CiCdPage has already
  // rendered, must still appear without a remount.
  describe('late slot registration (after first render)', () => {
    const LateSlotComponent: React.FC = () => <div data-testid="late-slot">Late Slot</div>;

    it('adds a tab for a slot registered after the page has already rendered', async () => {
      renderPage();
      expect(screen.queryByRole('tab', { name: 'Late slot' })).not.toBeInTheDocument();

      featureRegistry.registerComponentSlots({
        'devops.ci-cd.tab.late-slot': LateSlotComponent as React.ComponentType<unknown>,
      });

      await waitFor(() => expect(screen.getByRole('tab', { name: 'Late slot' })).toBeInTheDocument());
    });
  });
});
