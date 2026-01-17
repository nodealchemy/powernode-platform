import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { NavigationSection } from './NavigationSection';
import { NavigationSection as NavSection } from '@/shared/types/navigation';
import { Home, Settings, Users } from 'lucide-react';

// Mock NavigationContext
const mockHasPermission = jest.fn();
const mockUpdateState = jest.fn();
let mockExpandedSections: string[] = ['test-section'];

jest.mock('@/shared/hooks/NavigationContext', () => ({
  useNavigation: () => ({
    hasPermission: mockHasPermission,
    state: {
      activePath: '/',
      expandedSections: mockExpandedSections,
      isCollapsed: false,
      isMobileOpen: false
    },
    updateState: mockUpdateState,
    config: { items: [], sections: [] },
    theme: 'default',
  }),
}));

// Mock NavigationItem
jest.mock('./NavigationItem', () => ({
  NavigationItem: ({ item }: { item: any }) => (
    <div data-testid={`nav-item-${item.id}`}>{item.name}</div>
  ),
}));

describe('NavigationSection', () => {
  const defaultSection: NavSection = {
    id: 'test-section',
    name: 'Test Section',
    order: 1,
    items: [
      { id: 'item1', name: 'Item 1', href: '/item1', icon: Home, permissions: [] },
      { id: 'item2', name: 'Item 2', href: '/item2', icon: Settings, permissions: [] },
      { id: 'item3', name: 'Item 3', href: '/item3', icon: Users, permissions: ['admin'] },
    ],
  };

  const renderNavigationSection = (
    section: NavSection = defaultSection,
    props: Partial<React.ComponentProps<typeof NavigationSection>> = {}
  ) => {
    return render(
      <MemoryRouter>
        <NavigationSection section={section} {...props} />
      </MemoryRouter>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermission.mockReturnValue(true);
    mockExpandedSections = ['test-section'];
  });

  describe('rendering', () => {
    it('renders section name', () => {
      renderNavigationSection();

      expect(screen.getByText('Test Section')).toBeInTheDocument();
    });

    it('renders all visible items', () => {
      renderNavigationSection();

      expect(screen.getByTestId('nav-item-item1')).toBeInTheDocument();
      expect(screen.getByTestId('nav-item-item2')).toBeInTheDocument();
      expect(screen.getByTestId('nav-item-item3')).toBeInTheDocument();
    });

    it('does not render section name when collapsed', () => {
      renderNavigationSection(defaultSection, { isCollapsed: true });

      expect(screen.queryByText('Test Section')).not.toBeInTheDocument();
    });
  });

  describe('permission checking', () => {
    it('does not render when section permission denied', () => {
      mockHasPermission.mockReturnValue(false);

      const { container } = renderNavigationSection();

      expect(container.firstChild).toBeNull();
    });

    it('filters items by permission', () => {
      // Allow section but deny third item
      mockHasPermission
        .mockReturnValueOnce(true)  // Section permission
        .mockReturnValueOnce(true)  // Item 1 permission
        .mockReturnValueOnce(true)  // Item 2 permission
        .mockReturnValueOnce(false); // Item 3 permission

      renderNavigationSection();

      expect(screen.getByTestId('nav-item-item1')).toBeInTheDocument();
      expect(screen.getByTestId('nav-item-item2')).toBeInTheDocument();
      expect(screen.queryByTestId('nav-item-item3')).not.toBeInTheDocument();
    });

    it('does not render if no items are visible', () => {
      mockHasPermission
        .mockReturnValueOnce(true)   // Section permission
        .mockReturnValueOnce(false)  // Item 1 permission
        .mockReturnValueOnce(false)  // Item 2 permission
        .mockReturnValueOnce(false); // Item 3 permission

      const { container } = renderNavigationSection();

      expect(container.firstChild).toBeNull();
    });
  });

  describe('collapsible behavior', () => {
    it('shows chevron icon for collapsible sections', () => {
      const { container } = renderNavigationSection();

      const chevron = container.querySelector('svg');
      expect(chevron).toBeInTheDocument();
    });

    it('hides chevron when collapsible is false', () => {
      const nonCollapsibleSection: NavSection = {
        ...defaultSection,
        collapsible: false,
      };

      const { container } = renderNavigationSection(nonCollapsibleSection);

      // Should not have the ChevronDown icon (only NavigationItem icons via mock)
      const svgs = container.querySelectorAll('svg');
      expect(svgs.length).toBe(0);
    });

    it('calls updateState when toggling section', () => {
      renderNavigationSection();

      const header = screen.getByText('Test Section').closest('div');
      fireEvent.click(header!);

      expect(mockUpdateState).toHaveBeenCalledWith({
        expandedSections: [], // test-section was expanded, now collapsed
      });
    });

    it('expands section when clicking collapsed section', () => {
      mockExpandedSections = [];
      renderNavigationSection();

      const header = screen.getByText('Test Section').closest('div');
      fireEvent.click(header!);

      expect(mockUpdateState).toHaveBeenCalledWith({
        expandedSections: ['test-section'],
      });
    });

    it('does not toggle non-collapsible sections', () => {
      const nonCollapsibleSection: NavSection = {
        ...defaultSection,
        collapsible: false,
      };

      renderNavigationSection(nonCollapsibleSection);

      const header = screen.getByText('Test Section').closest('div');
      fireEvent.click(header!);

      expect(mockUpdateState).not.toHaveBeenCalled();
    });
  });

  describe('expanded state', () => {
    it('shows items when section is expanded', () => {
      mockExpandedSections = ['test-section'];
      renderNavigationSection();

      expect(screen.getByTestId('nav-item-item1')).toBeInTheDocument();
    });

    it('hides items when section is collapsed', () => {
      mockExpandedSections = [];
      renderNavigationSection();

      expect(screen.queryByTestId('nav-item-item1')).not.toBeInTheDocument();
    });

    it('always shows items when sidebar is collapsed', () => {
      mockExpandedSections = [];
      renderNavigationSection(defaultSection, { isCollapsed: true });

      expect(screen.getByTestId('nav-item-item1')).toBeInTheDocument();
    });

    it('always shows items for non-collapsible sections', () => {
      mockExpandedSections = [];
      const nonCollapsibleSection: NavSection = {
        ...defaultSection,
        collapsible: false,
      };

      renderNavigationSection(nonCollapsibleSection);

      expect(screen.getByTestId('nav-item-item1')).toBeInTheDocument();
    });

    it('rotates chevron when expanded', () => {
      mockExpandedSections = ['test-section'];
      const { container } = renderNavigationSection();

      const chevron = container.querySelector('svg');
      expect(chevron).toHaveClass('rotate-180');
    });

    it('does not rotate chevron when collapsed', () => {
      mockExpandedSections = [];
      const { container } = renderNavigationSection();

      const chevron = container.querySelector('svg');
      expect(chevron).not.toHaveClass('rotate-180');
    });
  });

  describe('separator', () => {
    it('renders separator for non-main sections', () => {
      const { container } = renderNavigationSection();

      const separator = container.querySelector('.border-t');
      expect(separator).toBeInTheDocument();
    });

    it('does not render separator for main section', () => {
      const mainSection: NavSection = {
        ...defaultSection,
        id: 'main',
      };

      const { container } = renderNavigationSection(mainSection);

      const separator = container.querySelector('.border-t.border-theme.my-2');
      expect(separator).not.toBeInTheDocument();
    });

    it('does not render separator when collapsed', () => {
      const { container } = renderNavigationSection(defaultSection, { isCollapsed: true });

      const separator = container.querySelector('.border-t.my-2');
      expect(separator).not.toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('section header has proper styling', () => {
      renderNavigationSection();

      const sectionName = screen.getByText('Test Section');
      expect(sectionName).toHaveClass('text-xs', 'font-semibold', 'uppercase', 'tracking-wider');
    });

    it('collapsible header has hover styling', () => {
      renderNavigationSection();

      const header = screen.getByText('Test Section').closest('div');
      expect(header).toHaveClass('cursor-pointer', 'hover:bg-theme-surface-hover', 'rounded-md');
    });

    it('non-collapsible header has no cursor styling', () => {
      const nonCollapsibleSection: NavSection = {
        ...defaultSection,
        collapsible: false,
      };

      renderNavigationSection(nonCollapsibleSection);

      const header = screen.getByText('Test Section').closest('div');
      expect(header).not.toHaveClass('cursor-pointer');
    });
  });
});
