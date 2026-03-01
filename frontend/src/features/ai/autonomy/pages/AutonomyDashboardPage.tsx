import React, { useState } from 'react';
import {
  Shield, Users, TrendingUp, TrendingDown, Eye, Bot,
  Zap, GitBranch, Radio, ShieldCheck, ClipboardCheck,
  Power, Target, FileText, AlertOctagon, Star, Settings,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAutonomyStats, useTrustScores, useAgentBudgets, useAgentLineage, useAgentLineageForest, useKillSwitchStatus } from '../api/autonomyApi';
import { TrustScoreCard } from '../components/TrustScoreCard';
import { AgentLineageTree } from '../components/AgentLineageTree';
import { BudgetAllocationPanel } from '../components/BudgetAllocationPanel';
import { BudgetRegimeIndicator } from '../components/BudgetRegimeIndicator';
import { CapabilityMatrixViewer } from '../components/CapabilityMatrixViewer';
import { CircuitBreakerStatusPanel } from '../components/CircuitBreakerStatusPanel';
import { BehavioralFingerprintChart } from '../components/BehavioralFingerprintChart';
import { ApprovalQueuePanel } from '../components/ApprovalQueuePanel';
import { DelegationPolicyPanel } from '../components/DelegationPolicyPanel';
import { TelemetryEventStream } from '../components/TelemetryEventStream';
import { KillSwitchPanel } from '../components/KillSwitchPanel';
import { GoalsPanel } from '../components/GoalsPanel';
import { ProposalsPanel } from '../components/ProposalsPanel';
import { EscalationsPanel } from '../components/EscalationsPanel';
import { FeedbackPanel } from '../components/FeedbackPanel';
import { InterventionPoliciesPanel } from '../components/InterventionPoliciesPanel';
import type { TrustScore, AgentBudget, AutonomyStats, BudgetRegime } from '../types/autonomy';

const breadcrumbs = [
  { label: 'Dashboard', href: '/app' },
  { label: 'AI', href: '/app/ai' },
  { label: 'Autonomy' },
];

interface StatCardProps {
  label: string;
  value: number;
  icon: React.ComponentType<{ className?: string }>;
  iconColor: string;
}

const StatCard: React.FC<StatCardProps> = ({ label, value, icon: Icon, iconColor }) => (
  <Card className="p-4">
    <div className="flex items-center justify-between">
      <div>
        <p className="text-sm text-theme-muted">{label}</p>
        <p className="text-2xl font-semibold text-theme-primary">{value}</p>
      </div>
      <div className="h-10 w-10 bg-opacity-10 rounded-lg flex items-center justify-center" style={{ backgroundColor: 'var(--theme-bg-secondary)' }}>
        <Icon className={`h-5 w-5 ${iconColor}`} />
      </div>
    </div>
  </Card>
);

function computeBudgetRegime(stats: AutonomyStats): BudgetRegime | null {
  if (!stats.budgets || stats.budgets.total_budget_cents === 0) return null;
  const pct = (stats.budgets.total_spent_cents / stats.budgets.total_budget_cents) * 100;
  const remaining = stats.budgets.total_budget_cents - stats.budgets.total_spent_cents;
  let level: BudgetRegime['level'];
  let message: string;
  if (pct >= 100) { level = 'EXHAUSTED'; message = 'Budget exhausted — new executions blocked'; }
  else if (pct >= 80) { level = 'CRITICAL'; message = 'Budget is critically low — only essential operations permitted'; }
  else if (pct >= 50) { level = 'CAUTIOUS'; message = 'Budget utilization is moderate'; }
  else { level = 'NORMAL'; message = 'Budget availability is healthy'; }
  return { level, utilization_pct: pct, remaining_cents: remaining, message };
}

const KillSwitchStatusBar: React.FC = () => {
  const { data: status } = useKillSwitchStatus();
  if (!status?.halted) return null;

  return (
    <div className="flex items-center gap-3 p-3 mb-4 rounded-lg border border-theme-error/50 bg-theme-error/5">
      <div className="h-3 w-3 rounded-full bg-theme-error animate-pulse" />
      <div className="flex-1">
        <p className="text-sm font-medium text-theme-error">AI Activity Suspended</p>
        {status.reason && <p className="text-xs text-theme-secondary">{status.reason}</p>}
      </div>
      <span className="text-xs text-theme-muted">Since {new Date(status.halted_since!).toLocaleString()}</span>
    </div>
  );
};

const OverviewTab: React.FC<{ stats: AutonomyStats }> = ({ stats }) => {
  const regime = computeBudgetRegime(stats);
  return (
    <>
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-4 mb-6">
        <StatCard label="Total Agents" value={stats.total_agents} icon={Bot} iconColor="text-theme-info" />
        <StatCard label="Supervised" value={stats.supervised} icon={Eye} iconColor="text-theme-warning" />
        <StatCard label="Monitored" value={stats.monitored} icon={Shield} iconColor="text-theme-info" />
        <StatCard label="Trusted" value={stats.trusted} icon={Users} iconColor="text-theme-success" />
        <StatCard label="Autonomous" value={stats.autonomous} icon={Bot} iconColor="text-theme-primary" />
        <StatCard label="Pending Promotions" value={stats.pending_promotions} icon={TrendingUp} iconColor="text-theme-success" />
        <StatCard label="Pending Demotions" value={stats.pending_demotions} icon={TrendingDown} iconColor="text-theme-error" />
      </div>
      {regime && <BudgetRegimeIndicator regime={regime} />}
    </>
  );
};

const TrustScoresTab: React.FC<{ trustScores: TrustScore[] }> = ({ trustScores }) => (
  <div className="space-y-6">
    {trustScores.length > 0 ? (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {trustScores.map((score) => (
          <TrustScoreCard key={score.id} score={score} />
        ))}
      </div>
    ) : (
      <Card>
        <CardContent className="p-8 text-center text-theme-muted">
          <Shield className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p>No trust scores available. Agents need evaluations to build trust scores.</p>
        </CardContent>
      </Card>
    )}
    <CapabilityMatrixViewer />
  </div>
);

const LineageTab: React.FC<{
  trustScores: TrustScore[];
  selectedAgentId: string;
  onAgentSelect: (id: string) => void;
}> = ({ trustScores, selectedAgentId, onAgentSelect }) => {
  const { data: forest, isLoading: forestLoading } = useAgentLineageForest();
  const { data: singleLineage } = useAgentLineage(selectedAgentId);
  const [showOrphans, setShowOrphans] = useState(false);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="Agent Lineage" />
        <CardContent>
          <div className="mb-4">
            <label className="block text-sm text-theme-muted mb-1">Filter by Agent (optional)</label>
            <select
              className="w-full max-w-xs rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
              value={selectedAgentId}
              onChange={(e) => onAgentSelect(e.target.value)}
            >
              <option value="">All agents (forest view)</option>
              {trustScores.map((s) => (
                <option key={s.agent_id} value={s.agent_id}>
                  {s.agent_name}
                </option>
              ))}
            </select>
          </div>

          {selectedAgentId ? (
            singleLineage ? (
              <AgentLineageTree root={singleLineage} />
            ) : (
              <p className="text-sm text-theme-muted py-4 text-center">Loading lineage...</p>
            )
          ) : forestLoading ? (
            <p className="text-sm text-theme-muted py-4 text-center">Loading lineage forest...</p>
          ) : forest && forest.trees.length > 0 ? (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {forest.trees.map((tree) => (
                <div key={tree.id} className="border border-theme rounded-lg p-3">
                  <AgentLineageTree root={tree} />
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-theme-muted py-4 text-center">
              No lineage trees found. Agent lineage is created when agents are organized into team hierarchies.
            </p>
          )}

          {!selectedAgentId && forest && forest.orphans.length > 0 && (
            <div className="mt-4">
              <button
                onClick={() => setShowOrphans(!showOrphans)}
                className="text-sm text-theme-info hover:underline flex items-center gap-1"
              >
                <GitBranch className="h-3.5 w-3.5" />
                {showOrphans ? 'Hide' : 'Show'} Standalone Agents ({forest.orphans.length})
              </button>
              {showOrphans && (
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-3 mt-3">
                  {forest.orphans.map((agent) => (
                    <div key={agent.id} className="border border-theme rounded-lg p-3">
                      <AgentLineageTree root={agent} />
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
      <DelegationPolicyPanel />
    </div>
  );
};

const BudgetsTab: React.FC<{ budgets: AgentBudget[]; stats: AutonomyStats }> = ({ budgets, stats }) => {
  const regime = computeBudgetRegime(stats);
  return (
    <div className="space-y-6">
      <BudgetAllocationPanel budgets={budgets} />
      {regime && <BudgetRegimeIndicator regime={regime} />}
    </div>
  );
};

const SecurityTab: React.FC<{ selectedAgentId: string }> = ({ selectedAgentId }) => (
  <div className="space-y-6">
    <CircuitBreakerStatusPanel />
    <BehavioralFingerprintChart agentId={selectedAgentId} />
  </div>
);

const SIDEBAR_ITEMS = [
  { id: 'overview', label: 'Overview', icon: Bot },
  { id: 'goals', label: 'Goals', icon: Target },
  { id: 'proposals', label: 'Proposals', icon: FileText },
  { id: 'escalations', label: 'Escalations', icon: AlertOctagon },
  { id: 'trust', label: 'Trust', icon: Shield },
  { id: 'lineage', label: 'Lineage', icon: GitBranch },
  { id: 'budgets', label: 'Budgets', icon: Zap },
  { id: 'policies', label: 'Policies', icon: Settings },
  { id: 'feedback', label: 'Feedback', icon: Star },
  { id: 'approvals', label: 'Approvals', icon: ClipboardCheck },
  { id: 'security', label: 'Security', icon: ShieldCheck },
  { id: 'killswitch', label: 'Kill Switch', icon: Power },
  { id: 'telemetry', label: 'Telemetry', icon: Radio },
] as const satisfies ReadonlyArray<{ id: string; label: string; icon: LucideIcon }>;

type SectionId = typeof SIDEBAR_ITEMS[number]['id'];

export const AutonomyContent: React.FC = () => {
  const [activeSection, setActiveSection] = useState<SectionId>('overview');
  const [selectedAgentId, setSelectedAgentId] = useState('');

  const { data: stats, isLoading: statsLoading } = useAutonomyStats();
  const { data: trustScores, isLoading: scoresLoading } = useTrustScores();
  const { data: budgets, isLoading: budgetsLoading } = useAgentBudgets();

  const isLoading = statsLoading || scoresLoading || budgetsLoading;

  if (isLoading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading autonomy data..." />;
  }

  const safeStats: AutonomyStats = stats ?? { total_agents: 0, supervised: 0, monitored: 0, trusted: 0, autonomous: 0, pending_promotions: 0, pending_demotions: 0 };
  const safeTrustScores = trustScores ?? [];
  const safeBudgets = budgets ?? [];

  const renderContent = () => {
    switch (activeSection) {
      case 'overview':
        return <OverviewTab stats={safeStats} />;
      case 'goals':
        return <GoalsPanel />;
      case 'proposals':
        return <ProposalsPanel />;
      case 'escalations':
        return <EscalationsPanel />;
      case 'trust':
        return <TrustScoresTab trustScores={safeTrustScores} />;
      case 'lineage':
        return (
          <LineageTab
            trustScores={safeTrustScores}
            selectedAgentId={selectedAgentId}
            onAgentSelect={setSelectedAgentId}
          />
        );
      case 'budgets':
        return <BudgetsTab budgets={safeBudgets} stats={safeStats} />;
      case 'policies':
        return <InterventionPoliciesPanel />;
      case 'feedback':
        return <FeedbackPanel />;
      case 'approvals':
        return <ApprovalQueuePanel />;
      case 'security':
        return <SecurityTab selectedAgentId={selectedAgentId} />;
      case 'killswitch':
        return <KillSwitchPanel />;
      case 'telemetry':
        return <TelemetryEventStream />;
    }
  };

  return (
    <>
      <KillSwitchStatusBar />

      {/* Mobile section selector */}
      <select
        className="md:hidden w-full mb-4 rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
        value={activeSection}
        onChange={(e) => setActiveSection(e.target.value as SectionId)}
      >
        {SIDEBAR_ITEMS.map((item) => (
          <option key={item.id} value={item.id}>{item.label}</option>
        ))}
      </select>

      <div className="flex gap-6">
        {/* Sidebar — hidden on mobile, visible md+ */}
        <nav className="hidden md:block w-48 shrink-0">
          <div className="sticky top-4 space-y-1">
            {SIDEBAR_ITEMS.map((item) => {
              const Icon = item.icon;
              const isActive = activeSection === item.id;
              return (
                <button
                  key={item.id}
                  onClick={() => setActiveSection(item.id)}
                  className={`w-full flex items-center gap-2.5 px-3 py-2 text-sm rounded-r-md transition-colors text-left ${
                    isActive
                      ? 'bg-theme-surface border-l-2 border-theme-interactive-primary text-theme-primary font-medium'
                      : 'border-l-2 border-transparent text-theme-secondary hover:text-theme-primary hover:bg-theme-surface/50'
                  }`}
                >
                  <Icon className="h-4 w-4 shrink-0" />
                  {item.label}
                </button>
              );
            })}
          </div>
        </nav>

        {/* Content area */}
        <div className="flex-1 min-w-0">
          {renderContent()}
        </div>
      </div>
    </>
  );
};

export const AutonomyDashboardPage: React.FC = () => (
  <PageContainer
    title="Agent Autonomy"
    description="Monitor agent trust, lineage, and budgets"
    breadcrumbs={breadcrumbs}
  >
    <AutonomyContent />
  </PageContainer>
);

export default AutonomyDashboardPage;
