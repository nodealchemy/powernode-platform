import { screen, waitFor } from '@testing-library/react';
import { render } from '@/test-utils';
import { TemplatesContent } from './DevOpsTemplatesPage';
import type { PageAction } from '@/shared/components/layout/PageContainer';

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
//
// fc-26 review item 7: the standalone default-export page (its own
// PageContainer + Refresh/Create Template actions, which is what these
// tests originally rendered) was deleted along with its now-unused route —
// TemplatesContent (embedded in CiCdPage's "Templates" tab) is the only
// surface left, so these tests render it directly and capture its actions
// via onActionsReady instead of finding a rendered button.

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
    let actions: PageAction[] = [];
    render(<TemplatesContent onActionsReady={(a) => { actions = a; }} />);

    await waitFor(() => expect(actions.some((a) => a.label === 'Create Template')).toBe(true));
    expect(actions.some((a) => a.label === 'New Execution')).toBe(false);
  });

  it('has no "Analytics" tab button, so its "coming soon" placeholder is unreachable', async () => {
    render(<TemplatesContent />);

    await screen.findByRole('button', { name: /^templates$/i });
    expect(screen.queryByRole('button', { name: /^analytics$/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/coming soon/i)).not.toBeInTheDocument();
  });
});
