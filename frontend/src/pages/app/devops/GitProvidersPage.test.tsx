import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { GitProvidersPage } from './GitProvidersPage';

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => ({}),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));

jest.mock('@/features/devops/git/services/git', () => ({
  gitProvidersApi: {
    getProviders: jest.fn(() => Promise.resolve([])),
    getProvider: jest.fn(),
  },
  credentialsApi: {
    getCredentials: jest.fn(() => Promise.resolve([])),
  },
}));

import type { PageAction } from '@/shared/components/layout/PageContainer';

describe('GitProvidersPage — Add Provider (fc-26 review item 2)', () => {
  // /devops/source-control/providers/new was deleted (it had no destination
  // of its own — the modal, not the URL, is the real UI); the button opens
  // the modal in place again instead.
  it('opens the modal in place, without navigating, when Add Provider is clicked', async () => {
    let capturedActions: PageAction[] = [];
    const onActionsReady = (actions: PageAction[]) => {
      capturedActions = actions;
    };

    render(
      <BrowserRouter>
        <GitProvidersPage onActionsReady={onActionsReady} />
      </BrowserRouter>
    );

    await waitFor(() => expect(capturedActions.some((a) => a.id === 'add-provider')).toBe(true));

    expect(screen.queryByText('Add Git Provider')).not.toBeInTheDocument();

    const addProvider = capturedActions.find((a) => a.id === 'add-provider');
    addProvider?.onClick?.();

    expect(await screen.findByText('Add Git Provider')).toBeInTheDocument();
    expect(mockNavigate).not.toHaveBeenCalled();
  });
});
