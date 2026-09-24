import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type {
  BackupInfo,
  CleanupStats,
} from '@/shared/services/admin/maintenanceApi';
import type { UseConfirmationOptions } from '@/shared/components/ui/ConfirmationModal';
import {
  DatabaseBackupManager,
  DataCleanupManager,
} from './MaintenanceComponents';

// --- maintenanceApi mock (module boundary) ---------------------------------
const mockCreateBackup = jest.fn();
const mockDeleteBackup = jest.fn();
const mockDownloadBackup = jest.fn();
const mockRunCleanup = jest.fn();

// Pure formatting helper is reproduced (not stubbed away) so render
// assertions reflect real component output.
const realFormatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'] as const;
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

jest.mock('@/shared/services/admin/maintenanceApi', () => ({
  maintenanceApi: {
    createBackup: (...args: unknown[]) => mockCreateBackup(...args),
    deleteBackup: (...args: unknown[]) => mockDeleteBackup(...args),
    downloadBackup: (...args: unknown[]) => mockDownloadBackup(...args),
    runCleanup: (...args: unknown[]) => mockRunCleanup(...args),
    formatBytes: (bytes: number) => realFormatBytes(bytes),
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
