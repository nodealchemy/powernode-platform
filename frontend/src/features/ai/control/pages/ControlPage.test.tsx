import React from 'react';
import { render, screen, within, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';

// AI → Control: one page for what Autonomy, Governance and Approval Chains
// split three ways. Seven URL-addressable leaves on one rail, each with at
// most one row of path tabs, every leaf and tab gated on the permission its
// endpoints check. The panels themselves have their own suites; here each is a
// stub that names itself, so these tests are about routing and gating only.

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, breadcrumbs = [], children }: {
    title: string; breadcrumbs?: Array<{ label: string }>; children: React.ReactNode;
  }) => (
    <div>
      <h1>{title}</h1>
      <div data-testid="breadcrumbs">{breadcrumbs.map((b) => b.label).join(' / ')}</div>
      {children}
    </div>
  ),
}));

let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockPermissions.includes(p) }),
}));

const stub = (id: string) => () => <div data-testid={id} />;
jest.mock('@/features/ai/control/components/ControlSummaryStrip', () => ({ ControlSummaryStrip: stub('summary-strip') }));
jest.mock('@/features/ai/approvals/components/ApprovalQueuePanel', () => ({ ApprovalQueuePanel: stub('approval-queue') }));
jest.mock('@/features/ai/autonomy/components/ProposalsPanel', () => ({ ProposalsPanel: stub('proposals') }));
jest.mock('@/features/ai/autonomy/components/EscalationsPanel', () => ({ EscalationsPanel: stub('escalations') }));
jest.mock('@/shared/components/approval-chains/ApprovalChainList', () => ({ ApprovalChainList: stub('approval-chains') }));
jest.mock('@/features/ai/autonomy/components/InterventionPoliciesPanel', () => ({ InterventionPoliciesPanel: stub('intervention-policies') }));
jest.mock('@/features/ai/control/components/ComplianceTab', () => ({ ComplianceTab: stub('compliance') }));
jest.mock('@/features/ai/budgets/components/BudgetsPanel', () => ({ BudgetsPanel: stub('budgets') }));
jest.mock('@/features/ai/autonomy/components/KillSwitchPanel', () => ({ KillSwitchPanel: stub('kill-switch') }));
jest.mock('@/features/ai/control/components/IdentitiesPanel', () => ({ IdentitiesPanel: stub('identities') }));
jest.mock('@/features/ai/autonomy/components/ShadowModeResultsPanel', () => ({ ShadowModeResultsPanel: stub('shadow-mode') }));
jest.mock('@/features/ai/autonomy/components/TelemetryEventStream', () => ({ TelemetryEventStream: stub('telemetry') }));
jest.mock('@/features/ai/control/components/TrustScoresTab', () => ({ TrustScoresTab: stub('trust') }));
jest.mock('@/features/ai/control/components/LineageTab', () => ({ LineageTab: stub('lineage') }));
jest.mock('@/features/ai/control/components/BehaviorTab', () => ({ BehaviorTab: stub('behavior') }));
jest.mock('@/features/ai/autonomy/components/FeedbackPanel', () => ({ FeedbackPanel: stub('feedback') }));
jest.mock('@/features/ai/autonomy/components/GoalsPanel', () => ({ GoalsPanel: stub('goals') }));
jest.mock('@/features/ai/audit/components/AuditLogList', () => ({ AuditLogList: stub('audit-log') }));
jest.mock('@/features/ai/control/components/GovernanceReportsPanel', () => ({ GovernanceReportsPanel: stub('reports') }));
jest.mock('@/features/ai/control/components/CollusionPanel', () => ({ CollusionPanel: stub('collusion') }));
jest.mock('@/features/ai/security/components/AsiComplianceMatrix', () => ({ AsiComplianceMatrix: stub('asi-compliance') }));

import { ControlPage, controlLeafPermissions } from './ControlPage';
import { CONTROL_PERMISSIONS } from '../controlPaths';

const EVERYTHING = [
  'ai.agents.read', 'ai.proposals.view', 'ai.escalations.view', 'ai.approval_chains.manage',
  'ai.intervention_policies.manage', 'ai.governance.read', 'ai.kill_switch.manage', 'ai.security.manage',
  'ai.feedback.view', 'ai.goals.manage',
];

let currentPath = '';
let currentSearch = '';
const LocationProbe = () => {
  const location = useLocation();
  currentPath = location.pathname;
  currentSearch = location.search;
  return null;
};

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/ai/control/*" element={<><ControlPage /><LocationProbe /></>} />
      </Routes>
    </MemoryRouter>,
  );
}

const railLabels = () =>
  within(screen.getByRole('navigation', { name: 'Control navigation' }))
    .getAllByRole('link').map((l) => l.textContent?.trim());

beforeEach(() => {
  mockPermissions = [...EVERYTHING];
  currentPath = '';
  currentSearch = '';
});

describe('ControlPage — seven leaves on one rail', () => {
  it('lists the leaves in order, and nothing else', () => {
    renderAt('/app/ai/control/approvals/queue');

    expect(railLabels()).toEqual([
      'Approvals', 'Policies', 'Budgets', 'Safety', 'Trust & Lineage', 'Goals', 'Compliance Audit',
    ]);
    expect(screen.getByRole('heading', { name: 'Control' })).toBeInTheDocument();
    expect(screen.getByTestId('summary-strip')).toBeInTheDocument();
  });

  it('opens on the first leaf the operator can use', () => {
    renderAt('/app/ai/control');
    expect(currentPath).toBe('/app/ai/control/approvals/queue');
    expect(screen.getByTestId('approval-queue')).toBeInTheDocument();
  });

  it.each([
    ['/app/ai/control/approvals/queue', 'approval-queue'],
    ['/app/ai/control/approvals/proposals', 'proposals'],
    ['/app/ai/control/approvals/escalations', 'escalations'],
    ['/app/ai/control/approvals/chains', 'approval-chains'],
    ['/app/ai/control/policies/intervention', 'intervention-policies'],
    ['/app/ai/control/policies/compliance-rules', 'compliance'],
    ['/app/ai/control/budgets', 'budgets'],
    ['/app/ai/control/safety/kill-switch', 'kill-switch'],
    ['/app/ai/control/safety/identities', 'identities'],
    ['/app/ai/control/safety/shadow-mode', 'shadow-mode'],
    ['/app/ai/control/safety/telemetry', 'telemetry'],
    ['/app/ai/control/trust-lineage/trust', 'trust'],
    ['/app/ai/control/trust-lineage/lineage', 'lineage'],
    ['/app/ai/control/trust-lineage/behavior', 'behavior'],
    ['/app/ai/control/trust-lineage/feedback', 'feedback'],
    ['/app/ai/control/goals', 'goals'],
    ['/app/ai/control/compliance-audit/audit-log', 'audit-log'],
    ['/app/ai/control/compliance-audit/reports', 'reports'],
    ['/app/ai/control/compliance-audit/collusion', 'collusion'],
    ['/app/ai/control/compliance-audit/asi-compliance', 'asi-compliance'],
  ])('%s renders its own view and stays put', (path, testId) => {
    renderAt(path);
    expect(screen.getByTestId(testId)).toBeInTheDocument();
    expect(currentPath).toBe(path);
  });

  it('labels the Policies tabs so compliance rules are not mistaken for the Compliance Audit leaf', () => {
    renderAt('/app/ai/control/policies/intervention');
    const tabs = screen.getAllByRole('link').map((l) => l.textContent?.trim());
    expect(tabs).toEqual(expect.arrayContaining(['Intervention', 'Compliance rules']));
    expect(tabs).not.toContain('Compliance');
  });

  it('opens a leaf with sub-tabs on its first tab', () => {
    renderAt('/app/ai/control/safety');
    expect(currentPath).toBe('/app/ai/control/safety/kill-switch');
  });

  it('keeps a deep-linked approval request in the URL', () => {
    renderAt('/app/ai/control/approvals/queue?request=req-7');
    expect(screen.getByTestId('approval-queue')).toBeInTheDocument();
    expect(currentSearch).toBe('?request=req-7');
  });

  it('names the leaf and tab in the breadcrumb trail', () => {
    renderAt('/app/ai/control/safety/telemetry');
    expect(screen.getByTestId('breadcrumbs').textContent).toBe('Dashboard / AI / Control / Safety / Autonomy telemetry');
  });

  it('moves the URL when a rail item is clicked', () => {
    renderAt('/app/ai/control/approvals/queue');
    fireEvent.click(within(screen.getByRole('navigation', { name: 'Control navigation' })).getByText('Goals'));
    expect(currentPath).toBe('/app/ai/control/goals');
    expect(screen.getByTestId('goals')).toBeInTheDocument();
  });
});

describe('ControlPage — Safety has no circuit breakers', () => {
  it('points at Observability for breakers instead of showing them', () => {
    renderAt('/app/ai/control/safety/kill-switch');

    expect(screen.getByText(/Observability → Circuit Breakers/)).toBeInTheDocument();
    const tabs = screen.getAllByRole('link').map((l) => l.textContent?.trim());
    expect(tabs).toEqual(expect.arrayContaining(['Kill switch', 'Identities & quarantine', 'Shadow mode', 'Autonomy telemetry']));
    expect(tabs.join(' ')).not.toMatch(/circuit/i);
  });
});

describe('ControlPage — gated on what each leaf\'s endpoints check', () => {
  it('shows a governance-only reader just the compliance views, and opens on them', () => {
    mockPermissions = ['ai.governance.read'];
    renderAt('/app/ai/control');

    expect(railLabels()).toEqual(['Policies', 'Compliance Audit']);
    expect(currentPath).toBe('/app/ai/control/policies/compliance-rules');
    expect(screen.queryByText('Intervention')).not.toBeInTheDocument();
  });

  it('hides approval chains without ai.approval_chains.manage', () => {
    mockPermissions = EVERYTHING.filter((p) => p !== 'ai.approval_chains.manage');
    renderAt('/app/ai/control/approvals/queue');

    expect(screen.queryByText('Approval chains')).not.toBeInTheDocument();
    expect(screen.getByText('Queue')).toBeInTheDocument();
  });

  it('hides the kill switch without ai.kill_switch.manage', () => {
    mockPermissions = EVERYTHING.filter((p) => p !== 'ai.kill_switch.manage');
    renderAt('/app/ai/control/safety');

    expect(screen.queryByText('Kill switch')).not.toBeInTheDocument();
    expect(currentPath).toBe('/app/ai/control/safety/identities');
  });

  it('shows nothing but a notice to someone with none of the permissions', () => {
    mockPermissions = [];
    renderAt('/app/ai/control');

    expect(screen.getByText(/You do not have permission to view AI control/)).toBeInTheDocument();
    expect(screen.queryByTestId('approval-queue')).not.toBeInTheDocument();
  });
});

describe('CONTROL_PERMISSIONS — the route and nav gate', () => {
  it('is exactly the set of permissions the leaves and tabs are gated on', () => {
    expect([...CONTROL_PERMISSIONS].sort()).toEqual(controlLeafPermissions().sort());
  });
});
