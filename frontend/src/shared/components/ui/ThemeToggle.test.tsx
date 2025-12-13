import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { ThemeToggle } from './ThemeToggle';

// Mock the ThemeContext hook
const mockToggleTheme = jest.fn();
let mockTheme = 'light';
let mockLoading = false;

jest.mock('@/shared/hooks/ThemeContext', () => ({
  useTheme: () => ({
    theme: mockTheme,
    toggleTheme: mockToggleTheme,
    loading: mockLoading
  })
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Moon: () => <svg data-testid="moon-icon" />,
  Sun: () => <svg data-testid="sun-icon" />
}));

describe('ThemeToggle', () => {
  const createStore = (isAuthenticated: boolean) => configureStore({
    reducer: {
      auth: () => ({ isAuthenticated })
    }
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockTheme = 'light';
    mockLoading = false;
  });

  describe('authentication', () => {
    it('returns null when not authenticated', () => {
      const { container } = render(
        <Provider store={createStore(false)}>
          <ThemeToggle />
        </Provider>
      );

      expect(container.firstChild).toBeNull();
    });

    it('renders when authenticated', () => {
      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByRole('button')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      mockLoading = true;

      const { container } = render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });
  });

  describe('theme display', () => {
    it('shows Moon icon in light theme', () => {
      mockTheme = 'light';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByTestId('moon-icon')).toBeInTheDocument();
    });

    it('shows Sun icon in dark theme', () => {
      mockTheme = 'dark';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByTestId('sun-icon')).toBeInTheDocument();
    });
  });

  describe('label', () => {
    it('does not show label by default', () => {
      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.queryByText('Dark')).not.toBeInTheDocument();
    });

    it('shows "Dark" label in light theme when showLabel is true', () => {
      mockTheme = 'light';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle showLabel />
        </Provider>
      );

      expect(screen.getByText('Dark')).toBeInTheDocument();
    });

    it('shows "Light" label in dark theme when showLabel is true', () => {
      mockTheme = 'dark';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle showLabel />
        </Provider>
      );

      expect(screen.getByText('Light')).toBeInTheDocument();
    });
  });

  describe('interaction', () => {
    it('calls toggleTheme when clicked', () => {
      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      fireEvent.click(screen.getByRole('button'));

      expect(mockToggleTheme).toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    it('has aria-label for light theme', () => {
      mockTheme = 'light';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByRole('button')).toHaveAttribute(
        'aria-label',
        'Switch to dark theme'
      );
    });

    it('has aria-label for dark theme', () => {
      mockTheme = 'dark';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByRole('button')).toHaveAttribute(
        'aria-label',
        'Switch to light theme'
      );
    });

    it('has title attribute', () => {
      mockTheme = 'light';

      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByRole('button')).toHaveAttribute(
        'title',
        'Switch to dark theme'
      );
    });
  });

  describe('styling', () => {
    it('applies custom className', () => {
      render(
        <Provider store={createStore(true)}>
          <ThemeToggle className="custom-class" />
        </Provider>
      );

      expect(screen.getByRole('button')).toHaveClass('custom-class');
    });

    it('has rounded-full class', () => {
      render(
        <Provider store={createStore(true)}>
          <ThemeToggle />
        </Provider>
      );

      expect(screen.getByRole('button')).toHaveClass('rounded-full');
    });
  });
});
