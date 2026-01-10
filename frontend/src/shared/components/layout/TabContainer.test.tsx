import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { TabContainer, TabPanel } from './TabContainer';

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate
}));

describe('TabContainer', () => {
  const mockTabs = [
    { id: 'tab1', label: 'First Tab', path: '/' },
    { id: 'tab2', label: 'Second Tab', path: '/second' },
    { id: 'tab3', label: 'Third Tab', path: '/third', disabled: true }
  ];

  const renderWithRouter = (
    component: React.ReactElement,
    initialPath: string = '/app'
  ) => {
    return render(
      <MemoryRouter initialEntries={[initialPath]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        {component}
      </MemoryRouter>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders all tab labels', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      expect(screen.getByText('First Tab')).toBeInTheDocument();
      expect(screen.getByText('Second Tab')).toBeInTheDocument();
      expect(screen.getByText('Third Tab')).toBeInTheDocument();
    });

    it('renders tabs as buttons', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      const buttons = screen.getAllByRole('tab');
      expect(buttons.length).toBe(3);
    });

    it('sets first tab as active by default', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      const firstTab = screen.getByText('First Tab').closest('button');
      expect(firstTab).toHaveAttribute('aria-selected', 'true');
    });

    it('respects activeTab prop', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} activeTab="tab2" />);

      const secondTab = screen.getByText('Second Tab').closest('button');
      expect(secondTab).toHaveAttribute('aria-selected', 'true');
    });
  });

  describe('tab icons', () => {
    it('renders string icons', () => {
      const tabsWithIcons = [
        { id: 'tab1', label: 'Tab', icon: '🏠' }
      ];
      renderWithRouter(<TabContainer tabs={tabsWithIcons} />);

      expect(screen.getByText('🏠')).toBeInTheDocument();
    });

    it('renders React node icons', () => {
      const tabsWithIcons = [
        { id: 'tab1', label: 'Tab', icon: <span data-testid="custom-icon">Icon</span> }
      ];
      renderWithRouter(<TabContainer tabs={tabsWithIcons} />);

      expect(screen.getByTestId('custom-icon')).toBeInTheDocument();
    });
  });

  describe('badges', () => {
    it('renders badge when provided', () => {
      const tabsWithBadge = [
        { id: 'tab1', label: 'Tab', badge: { count: 5 } }
      ];
      renderWithRouter(<TabContainer tabs={tabsWithBadge} />);

      expect(screen.getByText('5')).toBeInTheDocument();
    });

    it('does not render badge when count is 0', () => {
      const tabsWithBadge = [
        { id: 'tab1', label: 'Tab', badge: { count: 0 } }
      ];
      renderWithRouter(<TabContainer tabs={tabsWithBadge} />);

      expect(screen.queryByText('0')).not.toBeInTheDocument();
    });
  });

  describe('disabled tabs', () => {
    it('marks disabled tab as disabled', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      const disabledTab = screen.getByText('Third Tab').closest('button');
      expect(disabledTab).toBeDisabled();
    });

    it('does not change active tab when disabled tab clicked', () => {
      const onTabChange = jest.fn();
      renderWithRouter(<TabContainer tabs={mockTabs} onTabChange={onTabChange} />);

      fireEvent.click(screen.getByText('Third Tab'));

      expect(onTabChange).not.toHaveBeenCalled();
    });
  });

  describe('tab click', () => {
    it('calls onTabChange when tab clicked', () => {
      const onTabChange = jest.fn();
      renderWithRouter(<TabContainer tabs={mockTabs} onTabChange={onTabChange} />);

      fireEvent.click(screen.getByText('Second Tab'));

      expect(onTabChange).toHaveBeenCalledWith('tab2');
    });

    it('does not call onTabChange when clicking already active tab', () => {
      const onTabChange = jest.fn();
      renderWithRouter(<TabContainer tabs={mockTabs} activeTab="tab1" onTabChange={onTabChange} />);

      fireEvent.click(screen.getByText('First Tab'));

      expect(onTabChange).not.toHaveBeenCalled();
    });

    it('navigates when basePath is provided', () => {
      renderWithRouter(
        <TabContainer tabs={mockTabs} basePath="/app/settings" />,
        '/app/settings'
      );

      fireEvent.click(screen.getByText('Second Tab'));

      expect(mockNavigate).toHaveBeenCalledWith('/app/settings/second');
    });
  });

  describe('variants', () => {
    it('applies underline variant classes', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} variant="underline" />);

      const container = screen.getByText('First Tab').closest('button')?.parentElement;
      expect(container).toHaveClass('border-b');
    });

    it('applies pills variant classes', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} variant="pills" />);

      const container = screen.getByText('First Tab').closest('button')?.parentElement;
      expect(container).toHaveClass('rounded-lg');
    });
  });

  describe('sizes', () => {
    it('applies small size classes', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} size="sm" />);

      const tab = screen.getByText('First Tab').closest('button');
      expect(tab).toHaveClass('py-1.5');
    });

    it('applies large size classes', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} size="lg" />);

      const tab = screen.getByText('First Tab').closest('button');
      expect(tab).toHaveClass('py-2.5');
    });
  });

  describe('content rendering', () => {
    it('renders children when provided', () => {
      renderWithRouter(
        <TabContainer tabs={mockTabs}>
          <div>Tab Content</div>
        </TabContainer>
      );

      expect(screen.getByText('Tab Content')).toBeInTheDocument();
    });

    it('renders content from renderContent function', () => {
      renderWithRouter(
        <TabContainer
          tabs={mockTabs}
          renderContent={(activeTab) => <div>Content for {activeTab}</div>}
        />
      );

      expect(screen.getByText('Content for tab1')).toBeInTheDocument();
    });
  });

  describe('fullWidth', () => {
    it('applies fullWidth class when true', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} fullWidth />);

      const container = screen.getByText('First Tab').closest('button')?.parentElement;
      expect(container).toHaveClass('w-full');
    });
  });

  describe('accessibility', () => {
    it('has role="tab" on buttons', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      const tabs = screen.getAllByRole('tab');
      expect(tabs.length).toBe(3);
    });

    it('has aria-selected on tabs', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} activeTab="tab2" />);

      const firstTab = screen.getByText('First Tab').closest('button');
      const secondTab = screen.getByText('Second Tab').closest('button');

      expect(firstTab).toHaveAttribute('aria-selected', 'false');
      expect(secondTab).toHaveAttribute('aria-selected', 'true');
    });

    it('has aria-controls pointing to tabpanel', () => {
      renderWithRouter(<TabContainer tabs={mockTabs} />);

      const firstTab = screen.getByText('First Tab').closest('button');
      expect(firstTab).toHaveAttribute('aria-controls', 'tabpanel-tab1');
    });

    it('has role="tabpanel" on content', () => {
      renderWithRouter(
        <TabContainer tabs={mockTabs}>
          <div>Content</div>
        </TabContainer>
      );

      expect(screen.getByRole('tabpanel')).toBeInTheDocument();
    });
  });
});

describe('TabPanel', () => {
  it('renders children when tabId matches activeTab', () => {
    render(
      <TabPanel tabId="tab1" activeTab="tab1">
        <div>Panel Content</div>
      </TabPanel>
    );

    expect(screen.getByText('Panel Content')).toBeInTheDocument();
  });

  it('does not render when tabId does not match activeTab', () => {
    render(
      <TabPanel tabId="tab1" activeTab="tab2">
        <div>Panel Content</div>
      </TabPanel>
    );

    expect(screen.queryByText('Panel Content')).not.toBeInTheDocument();
  });

  it('has tabpanel role', () => {
    render(
      <TabPanel tabId="tab1" activeTab="tab1">
        <div>Panel Content</div>
      </TabPanel>
    );

    expect(screen.getByRole('tabpanel')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    render(
      <TabPanel tabId="tab1" activeTab="tab1" className="custom-class">
        <div>Panel Content</div>
      </TabPanel>
    );

    expect(screen.getByRole('tabpanel')).toHaveClass('custom-class');
  });
});
