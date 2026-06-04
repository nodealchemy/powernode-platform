import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { NavigationItem } from '../NavigationItem';
import type { NavigationItem as NavItem } from '@/shared/types/navigation';

const mockNavigate = jest.fn();
let mockHasPermissionResult = true;

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

jest.mock('@/shared/hooks/NavigationContext', () => ({
  useNavigation: () => ({
    hasPermission: () => mockHasPermissionResult,
    config: { items: [], sections: [] },
  }),
}));

// Probe component to surface the current router location in the DOM so we can
// assert that native <Link> navigation actually changed the path.
const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderItem = (item: NavItem) => {
  return render(
    <MemoryRouter initialEntries={['/app']}>
      <NavigationItem item={item} />
    </MemoryRouter>
  );
};

describe('NavigationItem', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermissionResult = true;
  });

  it('renders navigation item with name', () => {
    renderItem({ id: 'test', name: 'Test Item', href: '/app/test', icon: 'T' });
    expect(screen.getByText('Test Item')).toBeInTheDocument();
  });

  it('navigates when clicked (normal item)', () => {
    // The component navigates via a native <Link>, so assert the router path
    // actually changed rather than expecting a programmatic navigate() call.
    render(
      <MemoryRouter initialEntries={['/app']}>
        <NavigationItem item={{ id: 'test', name: 'Normal Link', href: '/app/test', icon: 'T' }} />
        <LocationProbe />
      </MemoryRouter>
    );

    expect(screen.getByTestId('location-probe')).toHaveTextContent('/app');
    fireEvent.click(screen.getByText('Normal Link'));
    expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/test');
  });

  it('dispatches CustomEvent instead of navigating when action is "open-chat"', () => {
    const eventSpy = jest.fn();
    window.addEventListener('powernode:open-chat-maximized', eventSpy);

    renderItem({ id: 'chat', name: 'Chat', href: '#', icon: 'C', action: 'open-chat' });
    fireEvent.click(screen.getByText('Chat'));

    expect(eventSpy).toHaveBeenCalled();
    expect(mockNavigate).not.toHaveBeenCalled();

    window.removeEventListener('powernode:open-chat-maximized', eventSpy);
  });

  it('returns null when user lacks permission', () => {
    mockHasPermissionResult = false;

    const { container } = renderItem({
      id: 'restricted',
      name: 'Restricted',
      href: '/app/restricted',
      icon: 'R',
      permissions: ['admin.access'],
    });

    expect(container.firstChild).toBeNull();
  });
});
