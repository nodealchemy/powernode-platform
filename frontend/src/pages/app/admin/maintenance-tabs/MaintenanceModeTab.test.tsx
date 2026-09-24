import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MaintenanceModeTab } from './MaintenanceModeTab';
import { maintenanceApi, MaintenanceStatus } from '@/shared/services/admin/maintenanceApi';

jest.mock('@/shared/services/admin/maintenanceApi', () => ({
  maintenanceApi: {
    setMaintenanceMode: jest.fn(),
    updateMaintenanceSettings: jest.fn()
  }
}));

const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: mockShowNotification })
}));

const baseStatus: MaintenanceStatus = {
  mode: false,
  message: '',
  estimated_completion: '',
  bypass_ips: [],
  bypass_ips_supported: true
};

describe('MaintenanceModeTab', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // The confirmation dialog is the shared ConfirmationModal (not
  // window.confirm) — asserted on by its rendered title/buttons rather than
  // a spy.
  it('asks for confirmation via the shared ConfirmationModal before enabling, and proceeds when confirmed', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockResolvedValue(undefined);
    const onUpdate = jest.fn();

    render(<MaintenanceModeTab status={baseStatus} onUpdate={onUpdate} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(await screen.findByText('Enable Maintenance Mode')).toBeInTheDocument();
    expect(maintenanceApi.setMaintenanceMode).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Enable' }));

    await waitFor(() => expect(maintenanceApi.setMaintenanceMode).toHaveBeenCalledWith(true, '', undefined, []));
    expect(onUpdate).toHaveBeenCalled();
  });

  it('does not enable when the confirmation is cancelled', async () => {
    render(<MaintenanceModeTab status={baseStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(await screen.findByText('Enable Maintenance Mode')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByText('Enable Maintenance Mode')).not.toBeInTheDocument());
    expect(maintenanceApi.setMaintenanceMode).not.toHaveBeenCalled();
  });

  it('does not ask for confirmation when disabling maintenance mode', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockResolvedValue(undefined);
    const enabledStatus: MaintenanceStatus = { ...baseStatus, mode: true, message: 'Upgrading' };

    render(<MaintenanceModeTab status={enabledStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(screen.queryByText('Enable Maintenance Mode')).not.toBeInTheDocument();
    await waitFor(() => expect(maintenanceApi.setMaintenanceMode).toHaveBeenCalledWith(false, 'Upgrading', undefined, []));
  });

  // Save routes to PATCH (update_fields!) — never the POST toggle — so it
  // can never wipe fields (Save-while-OFF) or reset enabled_at (Save-while-ON).
  it('Save calls updateMaintenanceSettings, never setMaintenanceMode', async () => {
    (maintenanceApi.updateMaintenanceSettings as jest.Mock).mockResolvedValue(undefined);
    const onUpdate = jest.fn();

    render(<MaintenanceModeTab status={baseStatus} onUpdate={onUpdate} />);
    fireEvent.change(screen.getByLabelText('Maintenance Message'), { target: { value: 'Staged message' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(maintenanceApi.updateMaintenanceSettings).toHaveBeenCalledWith('Staged message', undefined, [])
    );
    expect(maintenanceApi.setMaintenanceMode).not.toHaveBeenCalled();
    expect(onUpdate).toHaveBeenCalled();
  });

  it('allows saving message/ETA/bypass edits while maintenance is ON without toggling it off', async () => {
    (maintenanceApi.updateMaintenanceSettings as jest.Mock).mockResolvedValue(undefined);
    const enabledStatus: MaintenanceStatus = { ...baseStatus, mode: true, message: 'Upgrading' };

    render(<MaintenanceModeTab status={enabledStatus} onUpdate={jest.fn()} />);
    fireEvent.change(screen.getByLabelText('Maintenance Message'), { target: { value: 'Almost done' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(maintenanceApi.updateMaintenanceSettings).toHaveBeenCalledWith('Almost done', undefined, [])
    );
    expect(screen.queryByText('Enable Maintenance Mode')).not.toBeInTheDocument();
  });

  it('shows the server-provided error message when a save fails', async () => {
    (maintenanceApi.updateMaintenanceSettings as jest.Mock).mockRejectedValue(
      new Error('invalid bypass IP/CIDR: not-an-ip')
    );

    render(<MaintenanceModeTab status={baseStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(mockShowNotification).toHaveBeenCalledWith('invalid bypass IP/CIDR: not-an-ip', 'error')
    );
  });

  it('shows the server-provided error message when enabling fails', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockRejectedValue(
      new Error('TRUSTED_PROXY_CIDRS must be configured')
    );

    render(<MaintenanceModeTab status={baseStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('switch'));
    fireEvent.click(await screen.findByRole('button', { name: 'Enable' }));

    await waitFor(() =>
      expect(mockShowNotification).toHaveBeenCalledWith('TRUSTED_PROXY_CIDRS must be configured', 'error')
    );
  });

  it('disables and explains the bypass IP field when the server reports it unsupported', () => {
    const unsupportedStatus: MaintenanceStatus = { ...baseStatus, bypass_ips_supported: false };

    render(<MaintenanceModeTab status={unsupportedStatus} onUpdate={jest.fn()} />);

    expect(screen.getByLabelText('Bypass IPs')).toBeDisabled();
    expect(screen.getByText(/TRUSTED_PROXY_CIDRS/)).toBeInTheDocument();
  });

  it('leaves the bypass IP field enabled when supported', () => {
    render(<MaintenanceModeTab status={baseStatus} onUpdate={jest.fn()} />);

    expect(screen.getByLabelText('Bypass IPs')).not.toBeDisabled();
  });
});
