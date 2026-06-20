import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { SetupPendingBanner } from './SetupPendingBanner';

jest.mock('./services/setupApi', () => ({
  __esModule: true,
  setupApi: { getStatus: jest.fn() },
}));

import { setupApi } from './services/setupApi';

const mockGetStatus = setupApi.getStatus as jest.Mock;

const renderBanner = () =>
  render(
    <MemoryRouter>
      <SetupPendingBanner />
    </MemoryRouter>
  );

describe('SetupPendingBanner', () => {
  beforeEach(() => mockGetStatus.mockReset());

  it('shows when bootstrap is complete and an extension is pending', async () => {
    mockGetStatus.mockResolvedValue({ bootstrap_complete: true, pending: [], extensions_pending: ['system'] });
    renderBanner();

    await waitFor(() => expect(screen.getByTestId('setup-pending-banner')).toBeInTheDocument());
    expect(screen.getByText(/system/)).toBeInTheDocument();
  });

  it('stays hidden when no extensions are pending', async () => {
    mockGetStatus.mockResolvedValue({ bootstrap_complete: true, pending: [], extensions_pending: [] });
    renderBanner();

    await waitFor(() => expect(mockGetStatus).toHaveBeenCalled());
    expect(screen.queryByTestId('setup-pending-banner')).toBeNull();
  });

  it('stays hidden while bootstrap is incomplete', async () => {
    mockGetStatus.mockResolvedValue({ bootstrap_complete: false, pending: [], extensions_pending: ['system'] });
    renderBanner();

    await waitFor(() => expect(mockGetStatus).toHaveBeenCalled());
    expect(screen.queryByTestId('setup-pending-banner')).toBeNull();
  });

  it('can be dismissed', async () => {
    mockGetStatus.mockResolvedValue({ bootstrap_complete: true, pending: [], extensions_pending: ['system'] });
    renderBanner();

    await waitFor(() => expect(screen.getByTestId('setup-pending-banner')).toBeInTheDocument());
    fireEvent.click(screen.getByTestId('setup-pending-dismiss'));
    expect(screen.queryByTestId('setup-pending-banner')).toBeNull();
  });
});
