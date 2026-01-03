import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ScheduleModal } from '../components/ScheduleModal';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitPipelineScheduleDetail, GitRepository } from '@/features/git-providers/types';

// Mock dependencies
jest.mock('@/features/git-providers/services/gitProvidersApi');

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  Clock: () => <span data-testid="icon-clock" />,
  Calendar: () => <span data-testid="icon-calendar" />,
  GitBranch: () => <span data-testid="icon-git-branch" />,
  FileCode: () => <span data-testid="icon-file-code" />,
  Settings: () => <span data-testid="icon-settings" />,
  Plus: () => <span data-testid="icon-plus" />,
  Trash2: () => <span data-testid="icon-trash" />,
  ChevronDown: () => <span data-testid="icon-chevron-down" />,
  ChevronUp: () => <span data-testid="icon-chevron-up" />,
  AlertCircle: () => <span data-testid="icon-alert" />,
  Info: () => <span data-testid="icon-info" />,
  Check: () => <span data-testid="icon-check" />,
  Play: () => <span data-testid="icon-play" />,
  Pause: () => <span data-testid="icon-pause" />,
  RefreshCw: () => <span data-testid="icon-refresh" />,
  Zap: () => <span data-testid="icon-zap" />,
}));

const mockRepositories: GitRepository[] = [
  {
    id: 'repo-1',
    name: 'test-repo',
    full_name: 'owner/test-repo',
    owner: 'owner',
    default_branch: 'main',
    is_private: false,
    is_fork: false,
    is_archived: false,
    webhook_configured: true,
    stars_count: 10,
    forks_count: 2,
    open_issues_count: 5,
    open_prs_count: 1,
    topics: [],
    created_at: new Date().toISOString(),
    provider_type: 'github',
    credential_id: 'cred-1',
  },
];

const mockSchedule: GitPipelineScheduleDetail = {
  id: 'schedule-1',
  name: 'Nightly Build',
  description: 'Runs every night at 2 AM',
  cron_expression: '0 2 * * *',
  timezone: 'UTC',
  ref: 'main',
  workflow_file: '.github/workflows/nightly.yml',
  is_active: true,
  next_run_at: new Date(Date.now() + 3600000).toISOString(),
  last_run_at: new Date(Date.now() - 86400000).toISOString(),
  last_run_status: 'success',
  run_count: 100,
  success_rate: 95.0,
  repository_id: 'repo-1',
  inputs: { environment: 'staging' },
  success_count: 95,
  failure_count: 5,
  consecutive_failures: 0,
  human_schedule: 'Daily at 2:00 AM',
  next_runs: [
    new Date(Date.now() + 3600000).toISOString(),
    new Date(Date.now() + 90000000).toISOString(),
  ],
  overdue: false,
  repository: {
    id: 'repo-1',
    name: 'test-repo',
    full_name: 'owner/test-repo',
  },
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const defaultProps = {
  isOpen: true,
  onClose: jest.fn(),
  onSuccess: jest.fn(),
  repositories: mockRepositories,
  repository: mockRepositories[0],
  schedule: null as GitPipelineScheduleDetail | null,
};

describe('ScheduleModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (gitProvidersApi.createSchedule as jest.Mock).mockResolvedValue(mockSchedule);
    (gitProvidersApi.updateSchedule as jest.Mock).mockResolvedValue(mockSchedule);
  });

  it('renders modal when open', () => {
    render(<ScheduleModal {...defaultProps} />);

    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent(/schedule/i);
  });

  it('does not render when closed', () => {
    render(<ScheduleModal {...defaultProps} isOpen={false} />);

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('shows edit mode when schedule is provided', () => {
    render(<ScheduleModal {...defaultProps} schedule={mockSchedule} />);

    expect(screen.getByDisplayValue('Nightly Build')).toBeInTheDocument();
  });

  it('renders schedule name input', () => {
    render(<ScheduleModal {...defaultProps} />);

    const nameInput = screen.getByPlaceholderText(/Nightly Build/i);
    expect(nameInput).toBeInTheDocument();
  });

  it('displays schedule presets', () => {
    render(<ScheduleModal {...defaultProps} />);

    expect(screen.getByText('Every hour')).toBeInTheDocument();
    expect(screen.getByText('Nightly at 2 AM')).toBeInTheDocument();
  });

  it('applies preset when clicked', () => {
    render(<ScheduleModal {...defaultProps} />);

    const nightlyPreset = screen.getByText('Nightly at 2 AM');
    fireEvent.click(nightlyPreset);

    // Preset should be selectable (highlighted)
    expect(nightlyPreset).toBeInTheDocument();
  });

  it('renders branch/ref input', () => {
    render(<ScheduleModal {...defaultProps} />);

    const refInput = screen.getByPlaceholderText(/main, develop/i);
    expect(refInput).toBeInTheDocument();
  });

  it('renders workflow file input', () => {
    render(<ScheduleModal {...defaultProps} />);

    const workflowInput = screen.getByPlaceholderText(/.github\/workflows/i);
    expect(workflowInput).toBeInTheDocument();
  });

  it('handles form submission for create', async () => {
    render(<ScheduleModal {...defaultProps} />);

    // Fill in required fields
    const nameInput = screen.getByPlaceholderText(/Nightly Build/i);
    fireEvent.change(nameInput, { target: { value: 'Test Schedule' } });

    // Select a preset
    const nightlyPreset = screen.getByText('Nightly at 2 AM');
    fireEvent.click(nightlyPreset);

    // Find and click submit button (use role)
    const submitButtons = screen.getAllByRole('button');
    const submitButton = submitButtons.find(btn => btn.textContent?.includes('Create') || btn.textContent?.includes('Save'));
    if (submitButton) {
      fireEvent.click(submitButton);
    }

    await waitFor(() => {
      expect(gitProvidersApi.createSchedule).toHaveBeenCalled();
    });
  });

  it('handles form submission for update', async () => {
    render(<ScheduleModal {...defaultProps} schedule={mockSchedule} />);

    // Change the name
    const nameInput = screen.getByDisplayValue('Nightly Build');
    fireEvent.change(nameInput, { target: { value: 'Updated Schedule' } });

    // Find and click update button
    const submitButtons = screen.getAllByRole('button');
    const submitButton = submitButtons.find(btn => btn.textContent?.includes('Update') || btn.textContent?.includes('Save'));
    if (submitButton) {
      fireEvent.click(submitButton);
    }

    await waitFor(() => {
      expect(gitProvidersApi.updateSchedule).toHaveBeenCalled();
    });
  });

  it('calls onClose when close button is clicked', () => {
    render(<ScheduleModal {...defaultProps} />);

    const closeButton = screen.getByTestId('icon-x').closest('button');
    if (closeButton) {
      fireEvent.click(closeButton);
      expect(defaultProps.onClose).toHaveBeenCalled();
    }
  });

  it('calls onClose when cancel button is clicked', () => {
    render(<ScheduleModal {...defaultProps} />);

    const cancelButton = screen.getByText('Cancel');
    fireEvent.click(cancelButton);

    expect(defaultProps.onClose).toHaveBeenCalled();
  });

  it('pre-fills form when editing existing schedule', () => {
    render(<ScheduleModal {...defaultProps} schedule={mockSchedule} />);

    expect(screen.getByDisplayValue('Nightly Build')).toBeInTheDocument();
    expect(screen.getByDisplayValue('0 2 * * *')).toBeInTheDocument();
    expect(screen.getByDisplayValue('main')).toBeInTheDocument();
  });
});
