import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MaintenanceModeTab } from './MaintenanceModeTab';
import { maintenanceApi, MaintenanceStatus } from '@/shared/services/admin/maintenanceApi';

jest.mock('@/shared/services/admin/maintenanceApi', () => ({
  maintenanceApi: {
    setMaintenanceMode: jest.fn()
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
  let confirmSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    confirmSpy = jest.spyOn(window, 'confirm');
  });

  afterEach(() => {
    confirmSpy.mockRestore();
  });

  it('asks for confirmation before enabling maintenance mode, and proceeds when confirmed', async () => {
    confirmSpy.mockReturnValue(true);
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockResolvedValue(undefined);
    const onUpdate = jest.fn();

    render(<MaintenanceModeTab status={baseStatus} onUpdate={onUpdate} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(confirmSpy).toHaveBeenCalled();
    await waitFor(() => expect(maintenanceApi.setMaintenanceMode).toHaveBeenCalledWith(true, '', undefined, []));
    expect(onUpdate).toHaveBeenCalled();
  });

  it('does not enable when the confirmation is declined', async () => {
    confirmSpy.mockReturnValue(false);

    render(<MaintenanceModeTab status={baseStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(confirmSpy).toHaveBeenCalled();
    expect(maintenanceApi.setMaintenanceMode).not.toHaveBeenCalled();
  });

  it('does not ask for confirmation when disabling maintenance mode', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockResolvedValue(undefined);
    const enabledStatus: MaintenanceStatus = { ...baseStatus, mode: true, message: 'Upgrading' };

    render(<MaintenanceModeTab status={enabledStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('switch'));

    expect(confirmSpy).not.toHaveBeenCalled();
    await waitFor(() => expect(maintenanceApi.setMaintenanceMode).toHaveBeenCalledWith(false, 'Upgrading', undefined, []));
  });

  it('shows the server-provided error message when a save fails', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockRejectedValue(
      new Error('invalid bypass IP/CIDR: not-an-ip')
    );
    const enabledStatus: MaintenanceStatus = { ...baseStatus, mode: true };

    render(<MaintenanceModeTab status={enabledStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(mockShowNotification).toHaveBeenCalledWith('invalid bypass IP/CIDR: not-an-ip', 'error')
    );
  });

  it('allows saving message/ETA/bypass edits while maintenance is ON without toggling it off', async () => {
    (maintenanceApi.setMaintenanceMode as jest.Mock).mockResolvedValue(undefined);
    const enabledStatus: MaintenanceStatus = { ...baseStatus, mode: true, message: 'Upgrading' };

    render(<MaintenanceModeTab status={enabledStatus} onUpdate={jest.fn()} />);
    fireEvent.change(screen.getByLabelText('Maintenance Message'), { target: { value: 'Almost done' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(maintenanceApi.setMaintenanceMode).toHaveBeenCalledWith(true, 'Almost done', undefined, [])
    );
    expect(confirmSpy).not.toHaveBeenCalled();
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
