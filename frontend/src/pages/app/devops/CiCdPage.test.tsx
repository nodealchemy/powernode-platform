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
      tabs?: Array<{ id: string; label: string; path?: string }>;
      activeTab?: string;
      onTabChange?: (tabId: string) => void;
      basePath?: string;
    }) => {
      const navigate = useNavigate();
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
});
