import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type {
  BackupInfo,
  SystemHealth,
  CleanupStats,
  MaintenanceSystemMetrics,
  MaintenanceStatus,
} from '@/shared/services/admin/maintenanceApi';
import type { UseConfirmationOptions } from '@/shared/components/ui/ConfirmationModal';
import {
  MaintenanceModeControl,
  SystemHealthMonitor,
  DatabaseBackupManager,
  DataCleanupManager,
} from './MaintenanceComponents';

// --- maintenanceApi mock (module boundary) ---------------------------------
const mockSetMaintenanceMode = jest.fn();
const mockScheduleMaintenanceMode = jest.fn();
const mockCreateBackup = jest.fn();
const mockDeleteBackup = jest.fn();
const mockDownloadBackup = jest.fn();
const mockRunCleanup = jest.fn();

// Pure formatting/colour helpers are reproduced (not stubbed away) so render
// assertions reflect real component output.
const realFormatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'] as const;
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

const realFormatUptime = (seconds: number): string => {
  const days = Math.floor(seconds / (24 * 3600));
  const hours = Math.floor((seconds % (24 * 3600)) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h ${minutes}m`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
};

const realGetStatusBgColor = (status: string): string => {
  switch (status) {
    case 'healthy':
      return 'bg-theme-success-background';
    case 'warning':
      return 'bg-theme-warning-background';
    case 'critical':
      return 'bg-theme-error-bg';
    default:
      return 'bg-theme-background-secondary';
  }
};

jest.mock('@/shared/services/admin/maintenanceApi', () => ({
  maintenanceApi: {
    setMaintenanceMode: (...args: unknown[]) => mockSetMaintenanceMode(...args),
    scheduleMaintenanceMode: (...args: unknown[]) => mockScheduleMaintenanceMode(...args),
    createBackup: (...args: unknown[]) => mockCreateBackup(...args),
    deleteBackup: (...args: unknown[]) => mockDeleteBackup(...args),
    downloadBackup: (...args: unknown[]) => mockDownloadBackup(...args),
    runCleanup: (...args: unknown[]) => mockRunCleanup(...args),
    formatBytes: (bytes: number) => realFormatBytes(bytes),
    formatUptime: (seconds: number) => realFormatUptime(seconds),
    getStatusBgColor: (status: string) => realGetStatusBgColor(status),
  },
}));

// --- notifications mock -----------------------------------------------------
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: mockShowNotification }),
}));

// --- confirmation mock ------------------------------------------------------
// confirm() captures opts and, when auto-confirm is on, immediately fires the
// gated action (mirrors a user clicking "Confirm").
let mockShouldAutoConfirm = true;
const mockConfirmFn = jest.fn();
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: UseConfirmationOptions) => {
      mockConfirmFn(opts);
      if (mockShouldAutoConfirm) {
        void opts.onConfirm();
      }
    },
    ConfirmationDialog: null,
  }),
}));

// --- fixtures ---------------------------------------------------------------
const baseStatus: MaintenanceStatus = {
  mode: false,
  message: 'Down for upgrades',
};

const healthyHealth: SystemHealth = {
  overall_status: 'healthy',
  database: { status: 'healthy', connection_time: 12, size: 1048576, last_backup: '2026-01-01T00:00:00Z' },
  redis: { status: 'healthy', memory_usage: 2048, connected_clients: 7 },
  storage: { status: 'healthy', total_space: 10485760, used_space: 5242880, available_space: 5242880 },
  services: [],
};

const healthyMetrics: MaintenanceSystemMetrics = {
  cpu_usage: 23,
  memory_usage: 41,
  disk_usage: 67,
  active_users: 9,
  database_connections: 5,
  queue_size: 2,
  response_time_avg: 120,
  error_rate: 0.1,
  uptime: 90000,
};

const completedBackup: BackupInfo = {
  id: 'backup-1',
  filename: 'db_2026_06_05.sql.gz',
  size: 2097152,
  created_at: '2026-06-05T10:00:00Z',
  type: 'manual',
  status: 'completed',
};

const cleanupStats: CleanupStats = {
  old_logs: 1200,
  expired_sessions: 45,
  temporary_files: 8,
  audit_logs_older_than_90_days: 300,
  orphaned_uploads: 17,
  cache_entries: 9999,
};

beforeEach(() => {
  jest.clearAllMocks();
  mockShouldAutoConfirm = true;
});

// ===========================================================================
describe('MaintenanceModeControl', () => {
  it('renders current accessible status with the maintenance message prefilled', () => {
    render(<MaintenanceModeControl status={baseStatus} onUpdate={jest.fn()} />);

    expect(screen.getByText('Maintenance Mode')).toBeInTheDocument();
    expect(screen.getByText('System is accessible to users')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Down for upgrades')).toBeInTheDocument();
    // Not in maintenance => no active alert
    expect(screen.queryByText('Maintenance Mode Active')).not.toBeInTheDocument();
  });

  it('shows the active maintenance alert when mode is enabled', () => {
    render(<MaintenanceModeControl status={{ mode: true }} onUpdate={jest.fn()} />);

    expect(screen.getByText('System is in maintenance mode')).toBeInTheDocument();
    expect(screen.getByText('Maintenance Mode Active')).toBeInTheDocument();
    expect(screen.getByRole('switch')).toHaveAttribute('aria-checked', 'true');
  });

  it('renders a scheduled-maintenance window from status', () => {
    render(
      <MaintenanceModeControl
        status={{ mode: false, scheduled_start: '2026-07-01T08:00:00Z', scheduled_end: '2026-07-01T10:00:00Z' }}
        onUpdate={jest.fn()}
      />
    );

    expect(screen.getByText('Scheduled Maintenance')).toBeInTheDocument();
    expect(screen.getByText(/Scheduled from/)).toBeInTheDocument();
  });

  it('enables maintenance mode and notifies success (passing the message)', async () => {
    mockSetMaintenanceMode.mockResolvedValue(undefined);
    const onUpdate = jest.fn();
    render(<MaintenanceModeControl status={baseStatus} onUpdate={onUpdate} />);

    fireEvent.click(screen.getByRole('switch'));

    await waitFor(() => {
      expect(mockSetMaintenanceMode).toHaveBeenCalledWith(true, 'Down for upgrades');
    });
    expect(mockShowNotification).toHaveBeenCalledWith('Maintenance mode activated', 'success');
    expect(onUpdate).toHaveBeenCalledTimes(1);
  });

  it('deactivates maintenance mode when currently enabled', async () => {
    mockSetMaintenanceMode.mockResolvedValue(undefined);
    render(<MaintenanceModeControl status={{ mode: true, message: 'hi' }} onUpdate={jest.fn()} />);

    fireEvent.click(screen.getByRole('switch'));

    await waitFor(() => {
      expect(mockSetMaintenanceMode).toHaveBeenCalledWith(false, 'hi');
    });
    expect(mockShowNotification).toHaveBeenCalledWith('Maintenance mode deactivated', 'success');
  });

  it('notifies error when toggling maintenance mode fails', async () => {
    mockSetMaintenanceMode.mockRejectedValue(new Error('mock_rejection'));
    const onUpdate = jest.fn();
    render(<MaintenanceModeControl status={baseStatus} onUpdate={onUpdate} />);

    fireEvent.click(screen.getByRole('switch'));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Failed to update maintenance mode', 'error');
    });
    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('reveals scheduling fields and schedules a maintenance window', async () => {
    mockScheduleMaintenanceMode.mockResolvedValue(undefined);
    const onUpdate = jest.fn();
    const { container } = render(<MaintenanceModeControl status={baseStatus} onUpdate={onUpdate} />);

    // Scheduling fields hidden until "Schedule" toggle is clicked.
    expect(container.querySelector('input[type="datetime-local"]')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Schedule' }));

    const [start, end] = container.querySelectorAll<HTMLInputElement>('input[type="datetime-local"]');
    fireEvent.change(start, { target: { value: '2026-07-01T08:00' } });
    fireEvent.change(end, { target: { value: '2026-07-01T10:00' } });

    fireEvent.click(screen.getByRole('button', { name: 'Schedule Maintenance Window' }));

    await waitFor(() => {
      expect(mockScheduleMaintenanceMode).toHaveBeenCalledWith(
        '2026-07-01T08:00',
        '2026-07-01T10:00',
        'Down for upgrades'
      );
    });
    expect(mockShowNotification).toHaveBeenCalledWith('Maintenance window scheduled successfully', 'success');
    expect(onUpdate).toHaveBeenCalledTimes(1);
  });

  it('keeps the schedule submit disabled until both start and end are set', () => {
    const { container } = render(<MaintenanceModeControl status={baseStatus} onUpdate={jest.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Schedule' }));

    const submit = screen.getByRole('button', { name: 'Schedule Maintenance Window' });
    expect(submit).toBeDisabled();

    const [start, end] = container.querySelectorAll<HTMLInputElement>('input[type="datetime-local"]');
    fireEvent.change(start, { target: { value: '2026-07-01T08:00' } });
    expect(submit).toBeDisabled(); // end still empty

    fireEvent.change(end, { target: { value: '2026-07-01T10:00' } });
    expect(submit).toBeEnabled();
  });

  it('notifies error when scheduling fails', async () => {
    mockScheduleMaintenanceMode.mockRejectedValue(new Error('mock_rejection'));
    const { container } = render(<MaintenanceModeControl status={baseStatus} onUpdate={jest.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Schedule' }));
    const [start, end] = container.querySelectorAll<HTMLInputElement>('input[type="datetime-local"]');
    fireEvent.change(start, { target: { value: '2026-07-01T08:00' } });
    fireEvent.change(end, { target: { value: '2026-07-01T10:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Schedule Maintenance Window' }));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Failed to schedule maintenance', 'error');
    });
  });
});

// ===========================================================================
describe('SystemHealthMonitor', () => {
  it('renders overall status, metric tiles and component sub-status', () => {
    render(<SystemHealthMonitor health={healthyHealth} metrics={healthyMetrics} onRefresh={jest.fn()} />);

    expect(screen.getByText('System Health')).toBeInTheDocument();
    expect(screen.getByText('healthy')).toBeInTheDocument();
    // Metric tiles
    expect(screen.getByText('23%')).toBeInTheDocument(); // CPU
    expect(screen.getByText('41%')).toBeInTheDocument(); // Memory
    expect(screen.getByText('67%')).toBeInTheDocument(); // Disk
    expect(screen.getByText('9')).toBeInTheDocument(); // Active users
    // Component cards
    expect(screen.getByText('Database')).toBeInTheDocument();
    expect(screen.getByText('Redis')).toBeInTheDocument();
    expect(screen.getByText('Storage')).toBeInTheDocument();
    // Formatted bytes via the util
    expect(screen.getByText('Size: 1 MB')).toBeInTheDocument();
    expect(screen.getByText('Response: 12ms')).toBeInTheDocument();
  });

  it('applies the warning background tone for a degraded system', () => {
    const { container } = render(
      <SystemHealthMonitor
        health={{ ...healthyHealth, overall_status: 'warning' }}
        metrics={healthyMetrics}
        onRefresh={jest.fn()}
      />
    );
    expect(container.querySelector('.bg-theme-warning-background')).toBeInTheDocument();
  });

  it('invokes onRefresh when the refresh button is clicked', () => {
    const onRefresh = jest.fn();
    render(<SystemHealthMonitor health={healthyHealth} metrics={healthyMetrics} onRefresh={onRefresh} />);

    fireEvent.click(screen.getByTitle('Refresh status'));
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('omits the Services section when there are no services', () => {
    render(<SystemHealthMonitor health={healthyHealth} metrics={healthyMetrics} onRefresh={jest.fn()} />);
    expect(screen.queryByText('Services')).not.toBeInTheDocument();
  });

  it('lists services with formatted uptime when present', () => {
    const withServices: SystemHealth = {
      ...healthyHealth,
      services: [{ name: 'sidekiq', status: 'warning', uptime: 90000, memory_usage: 524288 }],
    };
    render(<SystemHealthMonitor health={withServices} metrics={healthyMetrics} onRefresh={jest.fn()} />);

    expect(screen.getByText('Services')).toBeInTheDocument();
    expect(screen.getByText('sidekiq')).toBeInTheDocument();
    // 90000s => 1d 1h 0m, 524288 bytes => 512 KB
    expect(screen.getByText(/Uptime: 1d 1h 0m/)).toBeInTheDocument();
    expect(screen.getByText(/Memory: 512 KB/)).toBeInTheDocument();
  });
});

// ===========================================================================
describe('DatabaseBackupManager', () => {
  it('renders the empty state with no latest-backup panel and no history', () => {
    render(<DatabaseBackupManager backups={[]} onRefresh={jest.fn()} />);

    expect(screen.getByText('Database Backups')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create Backup Now' })).toBeInTheDocument();
    expect(screen.queryByText('Latest Backup')).not.toBeInTheDocument();
    expect(screen.queryByText('Backup History')).not.toBeInTheDocument();
  });

  it('renders latest backup summary and history rows when backups exist', () => {
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={jest.fn()} />);

    expect(screen.getByText('Latest Backup')).toBeInTheDocument();
    expect(screen.getByText('Backup History')).toBeInTheDocument();
    expect(screen.getByText('db_2026_06_05.sql.gz')).toBeInTheDocument();
    // 2097152 bytes => 2 MB, shown in latest panel and history row
    expect(screen.getAllByText(/2 MB/).length).toBeGreaterThan(0);
  });

  it('creates a backup and notifies success, showing the in-progress label while pending', async () => {
    let resolveCreate: () => void = () => {};
    mockCreateBackup.mockReturnValue(new Promise<void>((res) => { resolveCreate = res; }));
    const onRefresh = jest.fn();
    render(<DatabaseBackupManager backups={[]} onRefresh={onRefresh} />);

    fireEvent.click(screen.getByRole('button', { name: 'Create Backup Now' }));

    // Loading state surfaces while the promise is pending.
    expect(await screen.findByText('Creating Backup...')).toBeInTheDocument();

    resolveCreate();

    await waitFor(() => {
      expect(mockCreateBackup).toHaveBeenCalledTimes(1);
    });
    expect(mockShowNotification).toHaveBeenCalledWith('Backup created successfully', 'success');
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('notifies error when backup creation fails', async () => {
    mockCreateBackup.mockRejectedValue(new Error('mock_rejection'));
    render(<DatabaseBackupManager backups={[]} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Create Backup Now' }));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Failed to create backup', 'error');
    });
  });

  it('deletes a backup only after confirmation', async () => {
    mockDeleteBackup.mockResolvedValue(undefined);
    const onRefresh = jest.fn();
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={onRefresh} />);

    fireEvent.click(screen.getByTitle('Delete backup'));

    expect(mockConfirmFn).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Delete Backup', variant: 'danger', confirmLabel: 'Delete' })
    );
    await waitFor(() => {
      expect(mockDeleteBackup).toHaveBeenCalledWith('backup-1');
    });
    expect(mockShowNotification).toHaveBeenCalledWith('Backup deleted successfully', 'success');
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('does not delete a backup when confirmation is cancelled', () => {
    mockShouldAutoConfirm = false;
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByTitle('Delete backup'));

    expect(mockConfirmFn).toHaveBeenCalledTimes(1);
    expect(mockDeleteBackup).not.toHaveBeenCalled();
  });

  it('notifies error when backup deletion fails', async () => {
    mockDeleteBackup.mockRejectedValue(new Error('mock_rejection'));
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByTitle('Delete backup'));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Failed to delete backup', 'error');
    });
  });

  it('opens the download URL for a completed backup in a new tab', async () => {
    mockDownloadBackup.mockResolvedValue('https://example.test/backup.sql.gz');
    const openSpy = jest.spyOn(window, 'open').mockImplementation(() => null);
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByTitle('Download backup'));

    await waitFor(() => {
      expect(mockDownloadBackup).toHaveBeenCalledWith('backup-1');
    });
    expect(openSpy).toHaveBeenCalledWith('https://example.test/backup.sql.gz', '_blank');
    openSpy.mockRestore();
  });

  it('notifies error when downloading a backup fails', async () => {
    mockDownloadBackup.mockRejectedValue(new Error('mock_rejection'));
    const openSpy = jest.spyOn(window, 'open').mockImplementation(() => null);
    render(<DatabaseBackupManager backups={[completedBackup]} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByTitle('Download backup'));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Failed to download backup', 'error');
    });
    expect(openSpy).not.toHaveBeenCalled();
    openSpy.mockRestore();
  });

  it('hides the download control for a non-completed backup', () => {
    render(
      <DatabaseBackupManager
        backups={[{ ...completedBackup, status: 'in_progress' }]}
        onRefresh={jest.fn()}
      />
    );
    expect(screen.queryByTitle('Download backup')).not.toBeInTheDocument();
    expect(screen.getByTitle('Delete backup')).toBeInTheDocument();
  });
});

// ===========================================================================
describe('DataCleanupManager', () => {
  it('renders cleanup options with formatted item counts', () => {
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    expect(screen.getByText('Data Cleanup')).toBeInTheDocument();
    expect(screen.getByText('Old Log Files')).toBeInTheDocument();
    expect(screen.getByText('1,200 items')).toBeInTheDocument(); // old_logs
    expect(screen.getByText('300 items')).toBeInTheDocument(); // audit logs (mapped key)
    expect(screen.getByText('9,999 items')).toBeInTheDocument(); // cache entries
  });

  it('defaults a known set of options on and others off', () => {
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    expect(screen.getByLabelText(/Old Log Files/)).toBeChecked();
    expect(screen.getByLabelText(/Expired Sessions/)).toBeChecked();
    expect(screen.getByLabelText(/Old Audit Logs/)).not.toBeChecked();
    expect(screen.getByLabelText(/Cache Entries/)).not.toBeChecked();
  });

  it('runs cleanup after confirmation with the selected options and reports the result', async () => {
    mockRunCleanup.mockResolvedValue({ cleaned_items: 42, freed_space: 1048576 });
    const onRefresh = jest.fn();
    render(<DataCleanupManager stats={cleanupStats} onRefresh={onRefresh} />);

    fireEvent.click(screen.getByRole('button', { name: 'Run Selected Cleanup Operations' }));

    expect(mockConfirmFn).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Run Cleanup', variant: 'warning' })
    );
    await waitFor(() => {
      expect(mockRunCleanup).toHaveBeenCalledWith({
        old_logs: true,
        expired_sessions: true,
        temporary_files: true,
        audit_logs: false,
        orphaned_uploads: true,
        cache_entries: false,
      });
    });
    // 1048576 bytes => 1 MB via the util in the success message
    expect(mockShowNotification).toHaveBeenCalledWith(
      'Cleanup completed: 42 items removed, 1 MB freed',
      'success'
    );
    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('passes updated selections through when a checkbox is toggled', async () => {
    mockRunCleanup.mockResolvedValue({ cleaned_items: 1, freed_space: 0 });
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    // Turn audit logs on, turn old logs off.
    fireEvent.click(screen.getByLabelText(/Old Audit Logs/));
    fireEvent.click(screen.getByLabelText(/Old Log Files/));

    fireEvent.click(screen.getByRole('button', { name: 'Run Selected Cleanup Operations' }));

    await waitFor(() => {
      expect(mockRunCleanup).toHaveBeenCalledWith(
        expect.objectContaining({ audit_logs: true, old_logs: false })
      );
    });
  });

  it('disables the run button when no options are selected', () => {
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    // Uncheck every default-on option.
    fireEvent.click(screen.getByLabelText(/Old Log Files/));
    fireEvent.click(screen.getByLabelText(/Expired Sessions/));
    fireEvent.click(screen.getByLabelText(/Temporary Files/));
    fireEvent.click(screen.getByLabelText(/Orphaned Uploads/));

    expect(screen.getByRole('button', { name: 'Run Selected Cleanup Operations' })).toBeDisabled();
  });

  it('does not run cleanup when confirmation is cancelled', () => {
    mockShouldAutoConfirm = false;
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Run Selected Cleanup Operations' }));

    expect(mockConfirmFn).toHaveBeenCalledTimes(1);
    expect(mockRunCleanup).not.toHaveBeenCalled();
  });

  it('notifies error when cleanup fails', async () => {
    mockRunCleanup.mockRejectedValue(new Error('mock_rejection'));
    render(<DataCleanupManager stats={cleanupStats} onRefresh={jest.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Run Selected Cleanup Operations' }));

    await waitFor(() => {
      expect(mockShowNotification).toHaveBeenCalledWith('Cleanup failed', 'error');
    });
  });

  it('handles missing stat fields by rendering zero counts', () => {
    const partial = { old_logs: 5 } as CleanupStats;
    render(<DataCleanupManager stats={partial} onRefresh={jest.fn()} />);

    expect(screen.getByText('5 items')).toBeInTheDocument();
    // Every other row falls back to 0.
    expect(screen.getAllByText('0 items').length).toBeGreaterThanOrEqual(4);
  });
});
