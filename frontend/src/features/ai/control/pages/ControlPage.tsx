import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import {
  ClipboardCheck, ScrollText, Wallet, ShieldAlert, GitBranch, Target, FileSearch,
} from 'lucide-react';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { SubNavRail } from '@/shared/components/navigation/SubNavRail';
import { PathTabs, PathTabSpec, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { ApprovalQueuePanel } from '@/features/ai/approvals/components/ApprovalQueuePanel';
import { ProposalsPanel } from '@/features/ai/autonomy/components/ProposalsPanel';
import { EscalationsPanel } from '@/features/ai/autonomy/components/EscalationsPanel';
import { ApprovalChainList } from '@/shared/components/approval-chains/ApprovalChainList';
import { InterventionPoliciesPanel } from '@/features/ai/autonomy/components/InterventionPoliciesPanel';
import { BudgetsPanel } from '@/features/ai/budgets/components/BudgetsPanel';
import { KillSwitchPanel } from '@/features/ai/autonomy/components/KillSwitchPanel';
import { ShadowModeResultsPanel } from '@/features/ai/autonomy/components/ShadowModeResultsPanel';
import { TelemetryEventStream } from '@/features/ai/autonomy/components/TelemetryEventStream';
import { FeedbackPanel } from '@/features/ai/autonomy/components/FeedbackPanel';
import { GoalsPanel } from '@/features/ai/autonomy/components/GoalsPanel';
import { AuditLogList } from '@/features/ai/audit/components/AuditLogList';
import { AsiComplianceMatrix } from '@/features/ai/security/components/AsiComplianceMatrix';
import { ControlSummaryStrip } from '@/features/ai/control/components/ControlSummaryStrip';
import { ComplianceTab } from '@/features/ai/control/components/ComplianceTab';
import { IdentitiesPanel } from '@/features/ai/control/components/IdentitiesPanel';
import { TrustScoresTab } from '@/features/ai/control/components/TrustScoresTab';
import { LineageTab } from '@/features/ai/control/components/LineageTab';
import { BehaviorTab } from '@/features/ai/control/components/BehaviorTab';
import { GovernanceReportsPanel } from '@/features/ai/control/components/GovernanceReportsPanel';
import { CollusionPanel } from '@/features/ai/control/components/CollusionPanel';
import { CONTROL_BASE_PATH } from '../controlPaths';

/**
 * AI → Control — replaces the Autonomy dashboard, the Governance page and the
 * Approval Chains page. One rail of seven leaves; a leaf with sub-views has
 * one row of path tabs. Every leaf and tab is a URL, and each is gated on the
 * permission its endpoints check, so an operator sees exactly what they can
 * use and the page opens on the first of it.
 *
 * Circuit breakers are deliberately absent: their one home is
 * Observability → Circuit Breakers.
 */

interface ControlTab extends PathTabSpec {
  element: React.ReactNode;
}

interface ControlLeafSpec extends PathTabSpec {
  /**
   * Sub-tabs; a leaf without them renders `element` directly and is gated on
   * its own `permission`. A leaf WITH tabs leaves `permission` empty: it is
   * open to anyone who can use one of its tabs.
   */
  tabs?: ControlTab[];
  element?: React.ReactNode;
}

const LEAVES: ControlLeafSpec[] = [
  {
    key: 'approvals', label: 'Approvals', permission: '', icon: <ClipboardCheck size={16} />,
    tabs: [
      { key: 'queue', label: 'Queue', permission: 'ai.agents.read', element: <ApprovalQueuePanel /> },
      { key: 'proposals', label: 'Proposals', permission: 'ai.proposals.view', element: <ProposalsPanel /> },
      { key: 'escalations', label: 'Escalations', permission: 'ai.escalations.view', element: <EscalationsPanel /> },
      { key: 'chains', label: 'Approval chains', permission: 'ai.approval_chains.manage', element: <ApprovalChainList /> },
    ],
  },
  {
    key: 'policies', label: 'Policies', permission: '', icon: <ScrollText size={16} />,
    tabs: [
      { key: 'intervention', label: 'Intervention', permission: 'ai.intervention_policies.manage', element: <InterventionPoliciesPanel /> },
      { key: 'compliance', label: 'Compliance', permission: 'ai.governance.read', element: <ComplianceTab /> },
    ],
  },
  { key: 'budgets', label: 'Budgets', permission: 'ai.agents.read', icon: <Wallet size={16} />, element: <BudgetsPanel /> },
  {
    key: 'safety', label: 'Safety', permission: '', icon: <ShieldAlert size={16} />,
    tabs: [
      { key: 'kill-switch', label: 'Kill switch', permission: 'ai.kill_switch.manage', element: <KillSwitchPanel /> },
      { key: 'identities', label: 'Identities & quarantine', permission: 'ai.security.manage', element: <IdentitiesPanel /> },
      { key: 'shadow-mode', label: 'Shadow mode', permission: 'ai.agents.read', element: <ShadowModeResultsPanel /> },
      { key: 'telemetry', label: 'Autonomy telemetry', permission: 'ai.agents.read', element: <TelemetryEventStream /> },
    ],
  },
  {
    key: 'trust-lineage', label: 'Trust & Lineage', permission: '', icon: <GitBranch size={16} />,
    tabs: [
      { key: 'trust', label: 'Trust', permission: 'ai.agents.read', element: <TrustScoresTab /> },
      { key: 'lineage', label: 'Lineage', permission: 'ai.agents.read', element: <LineageTab /> },
      { key: 'behavior', label: 'Behavior', permission: 'ai.agents.read', element: <BehaviorTab /> },
      { key: 'feedback', label: 'Feedback', permission: 'ai.feedback.view', element: <FeedbackPanel /> },
    ],
  },
  { key: 'goals', label: 'Goals', permission: 'ai.goals.manage', icon: <Target size={16} />, element: <GoalsPanel /> },
  {
    key: 'compliance-audit', label: 'Compliance Audit', permission: '', icon: <FileSearch size={16} />,
    tabs: [
      { key: 'audit-log', label: 'Audit log', permission: 'ai.governance.read', element: <AuditLogList /> },
      { key: 'reports', label: 'Reports', permission: 'ai.governance.read', element: <GovernanceReportsPanel /> },
      { key: 'collusion', label: 'Collusion', permission: 'ai.governance.read', element: <CollusionPanel /> },
      { key: 'asi-compliance', label: 'ASI compliance', permission: 'ai.security.manage', element: <AsiComplianceMatrix /> },
    ],
  },
];

/** The permissions the leaves and their tabs are gated on (pinned to CONTROL_PERMISSIONS). */
export function controlLeafPermissions(): string[] {
  return Array.from(new Set(
    LEAVES.flatMap((leaf) => (leaf.tabs ? leaf.tabs.map((t) => t.permission) : [leaf.permission])),
  ));
}

const SAFETY_BREAKER_NOTE = (
  <p className="text-sm text-theme-tertiary mb-4">
    Circuit breakers live in Observability → Circuit Breakers.
  </p>
);

const ControlLeaf: React.FC<{ leaf: ControlLeafSpec; hasPermission: (p: string) => boolean }> = ({
  leaf, hasPermission,
}) => {
  if (!leaf.tabs) return <>{leaf.element}</>;
  const basePath = `${CONTROL_BASE_PATH}/${leaf.key}`;
  const fallback = firstAccessibleTabPath(leaf.tabs, basePath, hasPermission);
  return (
    <>
      {leaf.key === 'safety' && SAFETY_BREAKER_NOTE}
      <PathTabs tabs={leaf.tabs} basePath={basePath} hasPermission={hasPermission}>
        <Routes>
          <Route index element={fallback ? <Navigate to={fallback} replace /> : null} />
          {leaf.tabs.filter((t) => hasPermission(t.permission)).map((t) => (
            <Route key={t.key} path={t.key} element={t.element} />
          ))}
        </Routes>
      </PathTabs>
    </>
  );
};

export const ControlPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const location = useLocation();

  // A leaf with tabs is open to anyone who can use one of its tabs.
  const canUseLeaf = (leaf: ControlLeafSpec) =>
    leaf.tabs ? leaf.tabs.some((t) => hasPermission(t.permission)) : hasPermission(leaf.permission);
  const railHasPermission = (leafKey: string) => {
    const leaf = LEAVES.find((l) => l.key === leafKey);
    return !!leaf && canUseLeaf(leaf);
  };
  // The rail asks about a leaf by its key; its own `permission` field is unused.
  const railItems: PathTabSpec[] = LEAVES.map(({ key, label, icon }) => ({ key, label, icon, permission: key }));
  const firstLeaf = LEAVES.find(canUseLeaf);

  const segments = location.pathname.slice(CONTROL_BASE_PATH.length).split('/').filter(Boolean);
  const activeLeaf = LEAVES.find((l) => l.key === segments[0]);
  const activeTab = activeLeaf?.tabs?.find((t) => t.key === segments[1]);
  const trail: BreadcrumbItem[] = [{ label: 'Control', href: CONTROL_BASE_PATH }];
  if (activeLeaf) {
    trail.push({ label: activeLeaf.label, href: `${CONTROL_BASE_PATH}/${activeLeaf.key}` });
    if (activeTab) trail.push({ label: activeTab.label });
  }

  return (
    <PageContainer
      title="Control"
      description="Approvals, policies, budgets, safety, trust and compliance for your AI agents"
      breadcrumbs={aiCrumbs(...trail)}
    >
      {firstLeaf && <ControlSummaryStrip />}
      <SubNavRail
        items={railItems}
        basePath={CONTROL_BASE_PATH}
        hasPermission={railHasPermission}
        ariaLabel="Control navigation"
        emptyState={<p className="text-theme-secondary">You do not have permission to view AI control.</p>}
      >
        <Routes>
          <Route index element={firstLeaf ? <Navigate to={`${CONTROL_BASE_PATH}/${firstLeaf.key}`} replace /> : null} />
          {LEAVES.filter(canUseLeaf).map((leaf) => (
            <Route
              key={leaf.key}
              path={leaf.tabs ? `${leaf.key}/*` : leaf.key}
              element={<ControlLeaf leaf={leaf} hasPermission={hasPermission} />}
            />
          ))}
        </Routes>
      </SubNavRail>
    </PageContainer>
  );
};

export default ControlPage;
