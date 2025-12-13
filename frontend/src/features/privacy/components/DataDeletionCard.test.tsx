import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DataDeletionCard } from './DataDeletionCard';
import { DataDeletionRequest } from '../services/privacyApi';

describe('DataDeletionCard', () => {
  const mockDeletionRequest: DataDeletionRequest = {
    id: 'req-1',
    status: 'pending',
    deletion_type: 'full',
    in_grace_period: true,
    days_until_deletion: 25,
    grace_period_ends_at: '2025-02-15T00:00:00Z',
    can_be_cancelled: true,
    created_at: new Date().toISOString()
  };

  const defaultProps = {
    deletionRequest: null,
    onRequestDeletion: jest.fn().mockResolvedValue(undefined),
    onCancelDeletion: jest.fn().mockResolvedValue(undefined),
    loading: false
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('normal state - no active request', () => {
    it('shows title', () => {
      render(<DataDeletionCard {...defaultProps} />);

      expect(screen.getByText('Delete Your Data')).toBeInTheDocument();
    });

    it('shows description', () => {
      render(<DataDeletionCard {...defaultProps} />);

      expect(screen.getByText('Request permanent deletion of your personal data')).toBeInTheDocument();
    });

    it('shows GDPR information', () => {
      render(<DataDeletionCard {...defaultProps} />);

      expect(screen.getByText(/GDPR Article 17/)).toBeInTheDocument();
    });

    it('shows grace period information', () => {
      render(<DataDeletionCard {...defaultProps} />);

      expect(screen.getByText(/30-day grace period/)).toBeInTheDocument();
    });

    it('shows Request Data Deletion button', () => {
      render(<DataDeletionCard {...defaultProps} />);

      expect(screen.getByText('Request Data Deletion')).toBeInTheDocument();
    });
  });

  describe('confirmation dialog', () => {
    it('shows confirmation dialog when Request button clicked', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      expect(screen.getByText('Important Notice')).toBeInTheDocument();
    });

    it('shows warning list in confirmation dialog', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      expect(screen.getByText(/This action cannot be undone/)).toBeInTheDocument();
      expect(screen.getByText(/Some data may be retained/)).toBeInTheDocument();
      expect(screen.getByText(/You have 30 days to cancel/)).toBeInTheDocument();
    });

    it('shows deletion type options', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      expect(screen.getByText('Deletion Type')).toBeInTheDocument();
      expect(screen.getByText('Full Deletion')).toBeInTheDocument();
      expect(screen.getByText('Anonymization')).toBeInTheDocument();
    });

    it('shows reason textarea', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      expect(screen.getByText('Reason (Optional)')).toBeInTheDocument();
      expect(screen.getByPlaceholderText(/Help us improve/)).toBeInTheDocument();
    });

    it('shows Confirm and Cancel buttons', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      expect(screen.getByText('Confirm Deletion Request')).toBeInTheDocument();
      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('hides confirmation when Cancel clicked', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      expect(screen.getByText('Important Notice')).toBeInTheDocument();

      fireEvent.click(screen.getByText('Cancel'));
      expect(screen.queryByText('Important Notice')).not.toBeInTheDocument();
    });
  });

  describe('deletion type selection', () => {
    it('defaults to Full Deletion', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      const fullDeletionRadio = screen.getByDisplayValue('full');
      expect(fullDeletionRadio).toBeChecked();
    });

    it('allows selecting Anonymization', () => {
      render(<DataDeletionCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));

      const anonymizeRadio = screen.getByDisplayValue('anonymize');
      fireEvent.click(anonymizeRadio);

      expect(anonymizeRadio).toBeChecked();
    });
  });

  describe('request submission', () => {
    it('calls onRequestDeletion with full deletion type', async () => {
      const onRequestDeletion = jest.fn().mockResolvedValue(undefined);
      render(<DataDeletionCard {...defaultProps} onRequestDeletion={onRequestDeletion} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      fireEvent.click(screen.getByText('Confirm Deletion Request'));

      await waitFor(() => {
        expect(onRequestDeletion).toHaveBeenCalledWith({
          deletion_type: 'full',
          reason: ''
        });
      });
    });

    it('calls onRequestDeletion with anonymize type when selected', async () => {
      const onRequestDeletion = jest.fn().mockResolvedValue(undefined);
      render(<DataDeletionCard {...defaultProps} onRequestDeletion={onRequestDeletion} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      fireEvent.click(screen.getByDisplayValue('anonymize'));
      fireEvent.click(screen.getByText('Confirm Deletion Request'));

      await waitFor(() => {
        expect(onRequestDeletion).toHaveBeenCalledWith({
          deletion_type: 'anonymize',
          reason: ''
        });
      });
    });

    it('includes reason when provided', async () => {
      const onRequestDeletion = jest.fn().mockResolvedValue(undefined);
      render(<DataDeletionCard {...defaultProps} onRequestDeletion={onRequestDeletion} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      fireEvent.change(screen.getByPlaceholderText(/Help us improve/), {
        target: { value: 'Moving to another service' }
      });
      fireEvent.click(screen.getByText('Confirm Deletion Request'));

      await waitFor(() => {
        expect(onRequestDeletion).toHaveBeenCalledWith({
          deletion_type: 'full',
          reason: 'Moving to another service'
        });
      });
    });

    it('shows Submitting... while requesting', async () => {
      const onRequestDeletion = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<DataDeletionCard {...defaultProps} onRequestDeletion={onRequestDeletion} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      fireEvent.click(screen.getByText('Confirm Deletion Request'));

      expect(screen.getByText('Submitting...')).toBeInTheDocument();
    });

    it('closes dialog after successful submission', async () => {
      const onRequestDeletion = jest.fn().mockResolvedValue(undefined);
      render(<DataDeletionCard {...defaultProps} onRequestDeletion={onRequestDeletion} />);

      fireEvent.click(screen.getByText('Request Data Deletion'));
      fireEvent.click(screen.getByText('Confirm Deletion Request'));

      await waitFor(() => {
        expect(screen.queryByText('Important Notice')).not.toBeInTheDocument();
      });
    });
  });

  describe('active deletion request state', () => {
    it('shows scheduled deletion message', () => {
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} />);

      expect(screen.getByText('Account Deletion Scheduled')).toBeInTheDocument();
    });

    it('shows days until deletion', () => {
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} />);

      expect(screen.getByText(/25 days/)).toBeInTheDocument();
    });

    it('shows grace period end date', () => {
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} />);

      expect(screen.getByText(/Grace period ends:/)).toBeInTheDocument();
    });

    it('shows Cancel Deletion Request button when cancellable', () => {
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} />);

      expect(screen.getByText('Cancel Deletion Request')).toBeInTheDocument();
    });

    it('hides cancel button when not cancellable', () => {
      const nonCancellableRequest = { ...mockDeletionRequest, can_be_cancelled: false };
      render(<DataDeletionCard {...defaultProps} deletionRequest={nonCancellableRequest} />);

      expect(screen.queryByText('Cancel Deletion Request')).not.toBeInTheDocument();
    });

    it('calls onCancelDeletion when cancel clicked', async () => {
      const onCancelDeletion = jest.fn().mockResolvedValue(undefined);
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} onCancelDeletion={onCancelDeletion} />);

      fireEvent.click(screen.getByText('Cancel Deletion Request'));

      await waitFor(() => {
        expect(onCancelDeletion).toHaveBeenCalledWith('req-1');
      });
    });

    it('shows processing message when not in grace period', () => {
      const processingRequest = { ...mockDeletionRequest, in_grace_period: false };
      render(<DataDeletionCard {...defaultProps} deletionRequest={processingRequest} />);

      expect(screen.getByText(/deletion request is being processed/)).toBeInTheDocument();
    });
  });

  describe('different status handling', () => {
    it('shows deletion UI for approved status', () => {
      const approvedRequest = { ...mockDeletionRequest, status: 'approved' as const };
      render(<DataDeletionCard {...defaultProps} deletionRequest={approvedRequest} />);

      expect(screen.getByText('Account Deletion Scheduled')).toBeInTheDocument();
    });

    it('shows deletion UI for processing status', () => {
      const processingRequest = { ...mockDeletionRequest, status: 'processing' as const };
      render(<DataDeletionCard {...defaultProps} deletionRequest={processingRequest} />);

      expect(screen.getByText('Account Deletion Scheduled')).toBeInTheDocument();
    });

    it('shows normal UI for completed status', () => {
      const completedRequest = { ...mockDeletionRequest, status: 'completed' as const };
      render(<DataDeletionCard {...defaultProps} deletionRequest={completedRequest} />);

      expect(screen.getByText('Delete Your Data')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('disables cancel button when loading', () => {
      render(<DataDeletionCard {...defaultProps} deletionRequest={mockDeletionRequest} loading={true} />);

      expect(screen.getByText('Cancel Deletion Request')).toBeDisabled();
    });
  });
});
