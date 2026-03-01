import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
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
  }),
}));

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
    renderItem({ id: 'test', name: 'Normal Link', href: '/app/test', icon: 'T' });
    fireEvent.click(screen.getByText('Normal Link'));
    expect(mockNavigate).toHaveBeenCalledWith('/app/test');
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
