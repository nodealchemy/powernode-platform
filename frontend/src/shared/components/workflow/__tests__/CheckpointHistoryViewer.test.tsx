import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderWithProviders } from '@/shared/utils/test-utils';
import { CheckpointHistoryViewer, Checkpoint } from '../CheckpointHistoryViewer';

// Mock the API
jest.mock('@/shared/services/api', () => ({
  api: {
    get: jest.fn().mockResolvedValue({ data: { data: { checkpoints: [] } } }),
    post: jest.fn().mockResolvedValue({ data: { success: true } })
  }
}));

// Mock window.confirm
const mockConfirm = jest.fn();
window.confirm = mockConfirm;

const mockCheckpoints: Checkpoint[] = [
  {
    id: 'cp-1',
    checkpoint_type: 'node_completed' as const,
    node_id: 'node-5',
    sequence_number: 3,
    created_at: '2025-01-04T10:00:00Z',
    age_seconds: 120,
    metadata: {
      progress_percentage: 60.0,
      cost_so_far: 0.75,
      duration_so_far: 3000,
      total_nodes: 10,
      completed_nodes: 5,
      workflow_version: '1.0.0'
    },
    state_keys: ['var1', 'var2'],
    state_snapshot: {
      variables: { var1: 'value1' },
      completed_nodes: ['node-1', 'node-2', 'node-3', 'node-4', 'node-5']
    }
  },
  {
    id: 'cp-2',
    checkpoint_type: 'manual' as const,
    node_id: 'node-3',
    sequence_number: 2,
    created_at: '2025-01-04T09:30:00Z',
    age_seconds: 1920,
    metadata: {
      progress_percentage: 40.0,
      cost_so_far: 0.5,
      duration_so_far: 2000,
      total_nodes: 10,
      completed_nodes: 3,
      workflow_version: '1.0.0',
      reason: 'before_critical_operation'
    },
    state_keys: ['var1'],
    state_snapshot: {
      variables: { var1: 'initial' },
      completed_nodes: ['node-1', 'node-2', 'node-3']
    }
  },
  {
    id: 'cp-3',
    checkpoint_type: 'error_handler' as const,
    node_id: 'node-2',
    sequence_number: 1,
    created_at: '2025-01-04T09:00:00Z',
    age_seconds: 3720,
    metadata: {
      progress_percentage: 20.0,
      cost_so_far: 0.25,
      duration_so_far: 1000,
      total_nodes: 10,
      completed_nodes: 2,
      workflow_version: '1.0.0'
    },
    state_snapshot: {
      variables: {},
      completed_nodes: ['node-1', 'node-2']
    }
  }
];

describe('CheckpointHistoryViewer', () => {
  const mockOnRestore = jest.fn();
  const mockOnCreateCheckpoint = jest.fn();

  beforeEach(() => {
    mockOnRestore.mockClear();
    mockOnCreateCheckpoint.mockClear();
    mockConfirm.mockClear();
  });

  describe('rendering', () => {
    it('renders checkpoint history header', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('Checkpoint History')).toBeInTheDocument();
    });

    it('displays checkpoint count', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('3 checkpoints available')).toBeInTheDocument();
    });

    it('shows checkpoint type badges', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      // Use regex since text may be split across DOM nodes
      expect(screen.getByText(/Node Completed/)).toBeInTheDocument();
      expect(screen.getByText(/Manual/)).toBeInTheDocument();
      expect(screen.getByText(/Error Handler/)).toBeInTheDocument();
    });

    it('displays checkpoint metadata (progress, cost, duration)', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('60.0%')).toBeInTheDocument();
      expect(screen.getByText('40.0%')).toBeInTheDocument();
      expect(screen.getByText('20.0%')).toBeInTheDocument();
      expect(screen.getByText('$0.7500')).toBeInTheDocument(); // Cost formatting - formatCost outputs $X.XXXX
      expect(screen.getByText('3.0s')).toBeInTheDocument(); // Duration formatting
    });

    it('formats age correctly', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('2m ago')).toBeInTheDocument(); // 120 seconds
      expect(screen.getByText('32m ago')).toBeInTheDocument(); // 1920 seconds
      expect(screen.getByText('1h ago')).toBeInTheDocument(); // 3720 seconds
    });

    it('shows empty state when no checkpoints exist', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={[]}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText(/no checkpoints available/i)).toBeInTheDocument();
      expect(screen.getByText(/checkpoints are created automatically/i)).toBeInTheDocument();
    });

    it('displays sequence numbers', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText(/#3 - Node Completed/)).toBeInTheDocument();
      expect(screen.getByText(/#2 - Manual/)).toBeInTheDocument();
      expect(screen.getByText(/#1 - Error Handler/)).toBeInTheDocument();
    });
  });

  describe('checkpoint actions', () => {
    it('shows restore button for each checkpoint', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const restoreButtons = screen.getAllByRole('button', { name: /restore/i });
      expect(restoreButtons).toHaveLength(3);
    });

    it('shows confirmation before restoring checkpoint', async () => {
      mockConfirm.mockReturnValue(false); // User cancels
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const restoreButtons = screen.getAllByRole('button', { name: /restore/i });
      await userEvent.click(restoreButtons[0]);

      expect(mockConfirm).toHaveBeenCalledWith(
        'Are you sure you want to restore from this checkpoint? The workflow will resume from this point.'
      );
      expect(mockOnRestore).not.toHaveBeenCalled();
    });

    it('calls onRestore when user confirms restoration', async () => {
      mockConfirm.mockReturnValue(true); // User confirms
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const restoreButtons = screen.getAllByRole('button', { name: /restore/i });
      await userEvent.click(restoreButtons[0]);

      await waitFor(() => {
        expect(mockOnRestore).toHaveBeenCalledWith('cp-1');
      });
    });
  });

  describe('checkpoint details', () => {
    it('expands checkpoint to show details when clicked', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCards = screen.getAllByText(/#3 - Node Completed/i)[0].closest('div');
      if (checkpointCards) {
        await userEvent.click(checkpointCards);

        expect(screen.getByText(/node information/i)).toBeInTheDocument();
        expect(screen.getByText(/workflow version/i)).toBeInTheDocument();
      }
    });

    it('displays node information in expanded details', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCards = screen.getAllByText(/#3 - Node Completed/i)[0].closest('div');
      if (checkpointCards) {
        await userEvent.click(checkpointCards);

        expect(screen.getByText(/Node ID:/i)).toBeInTheDocument();
        expect(screen.getByText('node-5')).toBeInTheDocument();
        expect(screen.getByText(/Completed: 5\/10 nodes/i)).toBeInTheDocument();
      }
    });

    it('displays state keys when available', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCards = screen.getAllByText(/#3 - Node Completed/i)[0].closest('div');
      if (checkpointCards) {
        await userEvent.click(checkpointCards);

        expect(screen.getByText(/state snapshot/i)).toBeInTheDocument();
        expect(screen.getByText('var1')).toBeInTheDocument();
        expect(screen.getByText('var2')).toBeInTheDocument();
      }
    });

    it('displays workflow version in details', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCards = screen.getAllByText(/#3 - Node Completed/i)[0].closest('div');
      if (checkpointCards) {
        await userEvent.click(checkpointCards);

        expect(screen.getByText(/workflow version: 1\.0\.0/i)).toBeInTheDocument();
      }
    });

    it('collapses details when clicked again', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCards = screen.getAllByText(/#3 - Node Completed/i)[0].closest('div');
      if (checkpointCards) {
        await userEvent.click(checkpointCards);
        expect(screen.getByText(/node information/i)).toBeInTheDocument();

        await userEvent.click(checkpointCards);
        expect(screen.queryByText(/node information/i)).not.toBeInTheDocument();
      }
    });
  });

  describe('checkpoint creation', () => {
    it('shows create checkpoint button when callback provided', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
          onCreateCheckpoint={mockOnCreateCheckpoint}
        />
      );

      expect(screen.getByRole('button', { name: /create checkpoint/i })).toBeInTheDocument();
    });

    it('hides create button when callback not provided', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.queryByRole('button', { name: /create checkpoint/i })).not.toBeInTheDocument();
    });

    it('calls onCreateCheckpoint when create button clicked', async () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
          onCreateCheckpoint={mockOnCreateCheckpoint}
        />
      );

      const createButton = screen.getByRole('button', { name: /create checkpoint/i });
      await userEvent.click(createButton);

      expect(mockOnCreateCheckpoint).toHaveBeenCalled();
    });
  });

  describe('loading state', () => {
    it('shows loading spinner when no checkpoints provided and loading', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          onRestore={mockOnRestore}
        />
      );

      // Component uses internal loading state - should show spinner initially
      const spinner = document.querySelector('.animate-spin');
      expect(spinner).toBeInTheDocument();
    });

    it('renders checkpoints when provided via props', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('3 checkpoints available')).toBeInTheDocument();
    });
  });

  describe('checkpoint types', () => {
    it('displays different checkpoint type styles', () => {
      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={mockCheckpoints}
          onRestore={mockOnRestore}
        />
      );

      // All checkpoint types should be rendered with their labels
      // Use regex since text may be split across DOM nodes
      expect(screen.getByText(/Node Completed/)).toBeInTheDocument();
      expect(screen.getByText(/Manual/)).toBeInTheDocument();
      expect(screen.getByText(/Error Handler/)).toBeInTheDocument();
    });

    it('displays conditional branch checkpoint type', () => {
      const conditionalCheckpoint: Checkpoint = {
        id: 'cp-conditional',
        checkpoint_type: 'conditional_branch',
        node_id: 'node-6',
        sequence_number: 4,
        created_at: '2025-01-04T11:00:00Z',
        age_seconds: 60,
        metadata: {
          progress_percentage: 80.0,
          total_nodes: 10,
          completed_nodes: 8,
          workflow_version: '1.0.0'
        }
      };

      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={[conditionalCheckpoint]}
          onRestore={mockOnRestore}
        />
      );

      // Component renders "#4 - Conditional" - use regex for substring match
      expect(screen.getByText(/Conditional/)).toBeInTheDocument();
    });

    it('displays batch completed checkpoint type', () => {
      const batchCheckpoint: Checkpoint = {
        id: 'cp-batch',
        checkpoint_type: 'batch_completed',
        node_id: 'node-7',
        sequence_number: 5,
        created_at: '2025-01-04T11:30:00Z',
        age_seconds: 30,
        metadata: {
          progress_percentage: 90.0,
          total_nodes: 10,
          completed_nodes: 9,
          workflow_version: '1.0.0'
        }
      };

      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={[batchCheckpoint]}
          onRestore={mockOnRestore}
        />
      );

      // Component renders "#5 - Batch Completed" - use regex for substring match
      expect(screen.getByText(/Batch Completed/)).toBeInTheDocument();
    });
  });

  describe('checkpoint metadata display', () => {
    it('displays custom metadata when available', async () => {
      const checkpointWithCustom: Checkpoint = {
        ...mockCheckpoints[0],
        metadata: {
          ...mockCheckpoints[0].metadata,
          custom: {
            customKey: 'customValue',
            anotherKey: 123
          }
        }
      };

      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={[checkpointWithCustom]}
          onRestore={mockOnRestore}
        />
      );

      const checkpointCard = screen.getByText(/#3 - Node Completed/i).closest('div');
      if (checkpointCard) {
        await userEvent.click(checkpointCard);

        expect(screen.getByText(/custom metadata/i)).toBeInTheDocument();
        expect(screen.getByText(/customKey/)).toBeInTheDocument();
      }
    });

    it('handles missing optional metadata gracefully', () => {
      const minimalCheckpoint: Checkpoint = {
        id: 'cp-minimal',
        checkpoint_type: 'node_completed',
        node_id: 'node-1',
        sequence_number: 1,
        created_at: '2025-01-04T10:00:00Z',
        metadata: {
          progress_percentage: 10.0
        }
      };

      renderWithProviders(
        <CheckpointHistoryViewer
          checkpoints={[minimalCheckpoint]}
          onRestore={mockOnRestore}
        />
      );

      expect(screen.getByText('10.0%')).toBeInTheDocument();
      // Default values when cost/duration not provided
      expect(screen.getByText('$0.0000')).toBeInTheDocument();
      // formatDuration(undefined) returns '0ms'
      expect(screen.getByText('0ms')).toBeInTheDocument();
    });
  });
});
