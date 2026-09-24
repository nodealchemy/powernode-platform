import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import uiSlice, { setMaintenanceMode } from '@/shared/services/slices/uiSlice';
import { MaintenanceScreen } from './MaintenanceScreen';

describe('MaintenanceScreen', () => {
  const makeStore = () => configureStore({ reducer: { ui: uiSlice } });

  it('renders nothing when maintenance mode is not active', () => {
    const store = makeStore();
    const { container } = render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    expect(container).toBeEmptyDOMElement();
  });

  it('renders the message and estimated completion when active', () => {
    const store = makeStore();
    store.dispatch(setMaintenanceMode({ message: 'Down for upgrades', estimatedCompletion: '2026-01-01T00:00:00Z' }));

    render(
      <Provider store={store}>
        <MaintenanceScreen />
      </Provider>
    );

    expect(screen.getByText('System Under Maintenance')).toBeInTheDocument();
    expect(screen.getByText('Down for upgrades')).toBeInTheDocument();
    expect(screen.getByText(/2026-01-01T00:00:00Z/)).toBeInTheDocument();
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
});
