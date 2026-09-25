import { render, screen } from '@testing-library/react';
import { InterventionPoliciesPanel } from './InterventionPoliciesPanel';

// ONE intervention-policy panel. The core Autonomy page mounts it unscoped:
// the grouped editor over every domain, plus the per-row list (create, edit,
// delete, test resolution). An extension embeds it scoped to its own namespace,
// where only the grouped editor for that namespace's domains belongs.

jest.mock('./PolicyDomainSections', () => ({
  PolicyDomainSections: ({ namespace }: { namespace?: string }) => (
    <div data-testid="policy-domain-sections" data-namespace={namespace ?? ''} />
  ),
}));

jest.mock('../api/autonomyApi', () => ({
  useInterventionPolicies: () => ({ data: [], isLoading: false }),
  useCreateInterventionPolicy: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useUpdateInterventionPolicy: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useDeleteInterventionPolicy: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useResolveInterventionPolicy: () => ({ mutateAsync: jest.fn(), isPending: false }),
  useTrustScores: () => ({ data: [] }),
  useInvalidateInterventionPolicies: () => jest.fn(),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

describe('InterventionPoliciesPanel', () => {
  it('unscoped: shows the grouped editor over every domain and the per-row list', () => {
    render(<InterventionPoliciesPanel />);

    expect(screen.getByTestId('policy-domain-sections')).toHaveAttribute('data-namespace', '');
    expect(screen.getByText('Create Policy')).toBeInTheDocument();
    expect(screen.getByText('Test Resolution')).toBeInTheDocument();
  });

  it('scoped to a namespace: shows only that namespace\'s grouped editor', () => {
    render(<InterventionPoliciesPanel namespace="ext" />);

    expect(screen.getByTestId('policy-domain-sections')).toHaveAttribute('data-namespace', 'ext');
    expect(screen.queryByText('Create Policy')).not.toBeInTheDocument();
    expect(screen.queryByText('Test Resolution')).not.toBeInTheDocument();
  });
});
