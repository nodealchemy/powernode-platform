import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import uiSlice, { setMaintenanceMode, clearMaintenanceMode } from '@/shared/services/slices/uiSlice';
import authReducer from '@/shared/services/slices/authSlice';
import { MaintenanceScreen } from './MaintenanceScreen';
import { authApi } from '@/features/account/auth/services/authAPI';

jest.mock('@/features/account/auth/services/authAPI');
const mockedAuthAPI = authApi as jest.Mocked<typeof authApi>;

describe('MaintenanceScreen', () => {
  const makeStore = () => configureStore({ reducer: { ui: uiSlice, auth: authReducer } });

  beforeEach(() => {
    jest.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('renders nothing when maintenance mode is not active', () => {
    const store = makeStore();
    const { container } = render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    expect(container).toBeEmptyDOMElement();
  });

  it('renders the message and formats the estimated completion when active', () => {
    const store = makeStore();
    store.dispatch(setMaintenanceMode({ message: 'Down for upgrades', estimatedCompletion: '2026-01-01T00:00:00Z' }));

    render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    expect(screen.getByText('System Under Maintenance')).toBeInTheDocument();
    expect(screen.getByText('Down for upgrades')).toBeInTheDocument();
    // ISO input is reformatted for display, not shown verbatim.
    expect(screen.getByText(/Jan 1, 2026/)).toBeInTheDocument();
  });

  it('shows a free-text estimated completion verbatim, unmangled by date parsing', () => {
    const store = makeStore();
    store.dispatch(setMaintenanceMode({ message: 'Down for upgrades', estimatedCompletion: 'about 30 minutes' }));

    render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    expect(screen.getByText(/about 30 minutes/)).toBeInTheDocument();
  });

  it('clears the flag when Retry is clicked', () => {
    // window.location.reload() is also called (see the component), but this
    // jsdom's Location object doesn't allow redefining/spying on `reload` —
    // the state-clearing side of Retry is the meaningful, testable part.
    const store = makeStore();
    store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

    render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));

    expect(store.getState().ui.maintenance?.active).toBe(false);
  });

  it('signs the user out and clears the flag when Sign out is clicked', async () => {
    mockedAuthAPI.logout.mockResolvedValueOnce({} as never);
    const store = makeStore();
    store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

    render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));

    expect(store.getState().ui.maintenance?.active).toBe(false);
    await waitFor(() => expect(mockedAuthAPI.logout).toHaveBeenCalled());
  });

  describe('accessibility', () => {
    it('renders as an alertdialog with aria-modal and aria-live', () => {
      const store = makeStore();
      store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

      render(
        <Provider store={store}>
          <MaintenanceScreen />
        </Provider>
      );

      const dialog = screen.getByRole('alertdialog');
      expect(dialog).toHaveAttribute('aria-modal', 'true');
      expect(dialog).toHaveAttribute('aria-live', 'assertive');
    });

    it('hides the decorative emoji from assistive tech', () => {
      const store = makeStore();
      store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

      render(
        <Provider store={store}>
          <MaintenanceScreen />
        </Provider>
      );

      expect(screen.getByText('🔧')).toHaveAttribute('aria-hidden', 'true');
    });

    it('moves focus into the dialog on mount', () => {
      const store = makeStore();
      store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

      render(
        <Provider store={store}>
          <MaintenanceScreen />
        </Provider>
      );

      expect(screen.getByRole('alertdialog')).toHaveFocus();
    });

    it('makes the app root inert and aria-hidden while shown, and restores it when maintenance clears', () => {
      const appRoot = document.createElement('div');
      appRoot.id = 'root';
      document.body.appendChild(appRoot);

      const store = makeStore();
      store.dispatch(setMaintenanceMode({ message: 'Down for upgrades' }));

      const { rerender } = render(
        <Provider store={store}>
          <MaintenanceScreen />
        </Provider>
      );

      expect(appRoot).toHaveAttribute('aria-hidden', 'true');
      expect(appRoot).toHaveAttribute('inert');

      store.dispatch(clearMaintenanceMode());
      rerender(
        <Provider store={store}>
          <MaintenanceScreen />
        </Provider>
      );

      expect(appRoot).not.toHaveAttribute('aria-hidden');
      expect(appRoot).not.toHaveAttribute('inert');
    });
  });
});
