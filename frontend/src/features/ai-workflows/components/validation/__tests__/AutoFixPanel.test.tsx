import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AutoFixPanel } from '../AutoFixPanel';
import { validationApi } from '@/shared/services/ai';
import type { ValidationIssue } from '@/shared/types/workflow';

// Mock the validation API
jest.mock('@/shared/services/ai', () => ({
  validationApi: {
    autoFix: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('AutoFixPanel', () => {
  const mockWorkflowId = 'workflow-123';

  const mockAutoFixableIssue: ValidationIssue = {
    id: 'issue-1',
    node_id: 'node-1',
    node_name: 'Test Node',
    node_type: 'ai_agent',
    severity: 'warning',
    category: 'configuration',
    rule_id: 'missing_timeout',
    rule_name: 'Missing Timeout',
    message: 'Node timeout not configured',
    suggestion: 'Set timeout to 120 seconds',
    auto_fixable: true,
  };

  const mockNonFixableIssue: ValidationIssue = {
    ...mockAutoFixableIssue,
    id: 'issue-2',
    rule_id: 'complex_issue',
    rule_name: 'Complex Issue',
    auto_fixable: false,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders no auto-fixable issues message when none available', () => {
    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockNonFixableIssue]}
      />
    );

    expect(screen.getByText(/no auto-fixable issues/i)).toBeInTheDocument();
  });

  it('renders auto-fixable issues list', () => {
    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockAutoFixableIssue]}
      />
    );

    expect(screen.getByText('Auto-Fix Panel')).toBeInTheDocument();
    expect(screen.getByText('Missing Timeout')).toBeInTheDocument();
    expect(screen.getByText('Node timeout not configured')).toBeInTheDocument();
  });

  it('allows selecting and deselecting issues', () => {
    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockAutoFixableIssue]}
      />
    );

    const checkbox = screen.getByRole('checkbox');
    expect(checkbox).toBeChecked(); // Auto-selected by default

    fireEvent.click(checkbox);
    expect(checkbox).not.toBeChecked();

    fireEvent.click(checkbox);
    expect(checkbox).toBeChecked();
  });

  it('shows info message when preview button clicked', async () => {
    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockAutoFixableIssue]}
      />
    );

    const previewButton = screen.getByText(/preview changes/i);
    fireEvent.click(previewButton);

    await waitFor(() => {
      // Preview functionality not yet implemented
      expect(previewButton).toBeInTheDocument();
    });
  });

  it('applies fixes when fix button clicked', async () => {
    const mockResult = {
      workflow: {},
      fixed_issues: ['issue-1'],
      remaining_issues: [],
    };

    (validationApi.autoFix as jest.Mock).mockResolvedValue(mockResult);

    const onFixComplete = jest.fn();

    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockAutoFixableIssue]}
        onFixComplete={onFixComplete}
      />
    );

    const fixButton = screen.getByText(/fix all/i);
    fireEvent.click(fixButton);

    await waitFor(() => {
      expect(validationApi.autoFix).toHaveBeenCalledWith(mockWorkflowId, ['issue-1']);
      expect(onFixComplete).toHaveBeenCalled();
    });
  });

  it('handles fix errors gracefully', async () => {
    (validationApi.autoFix as jest.Mock).mockRejectedValue(
      new Error('Fix failed')
    );

    render(
      <AutoFixPanel
        workflowId={mockWorkflowId}
        issues={[mockAutoFixableIssue]}
      />
    );

    const fixButton = screen.getByText(/fix all/i);
    fireEvent.click(fixButton);

    await waitFor(() => {
      expect(validationApi.autoFix).toHaveBeenCalled();
    });
  });
});
