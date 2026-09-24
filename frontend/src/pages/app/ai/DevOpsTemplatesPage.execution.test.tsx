import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import DevOpsTemplatesPage from './DevOpsTemplatesPage';

// fc-05 review (H1): "New Execution" looked wired (the client had a
// createExecution method calling POST /ai/devops/executions, which
// succeeds), but nothing ever advances the execution it creates —
// Ai::DevopsService#execute_pipeline calls execution.start! and then the
// job that would actually run the pipeline is commented out
// (server/app/services/ai/devops_service.rb ~101), so every execution
// created this way sits in "running" forever. Wiring a button to an
// endpoint that creates a permanently-stuck record is not fixing the
// stub, it's hiding it one layer down — so the action is removed instead,
// same as the "Analytics" tab (fc-05's original fix) had no distinct
// backend behind it either. The now-orphaned client method
// (devopsApi.createExecution) was deleted too.

jest.mock('@/shared/services/ai/DevopsApiService', () => ({
  devopsApi: {
    getTemplates: () => Promise.resolve({ items: [] }),
    getInstallations: () => Promise.resolve({ items: [] }),
    getExecutions: () => Promise.resolve({ items: [] }),
    getRisks: () => Promise.resolve({ items: [] }),
    getReviews: () => Promise.resolve({ items: [] }),
    getAnalytics: () => Promise.resolve({ analytics: null }),
  },
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => {} }));

describe('DevOpsTemplatesPage stub removal (fc-05)', () => {
  it('has no "New Execution" action (the endpoint it would call cannot progress the record it creates)', async () => {
    render(<DevOpsTemplatesPage />);

    await screen.findByRole('button', { name: /create template/i });
    expect(screen.queryByRole('button', { name: /new execution/i })).not.toBeInTheDocument();
  });

  it('has no "Analytics" tab button, so its "coming soon" placeholder is unreachable', async () => {
    render(<DevOpsTemplatesPage />);

    await screen.findByRole('button', { name: /create template/i });
    expect(screen.queryByRole('button', { name: /^analytics$/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/coming soon/i)).not.toBeInTheDocument();
  });
});
