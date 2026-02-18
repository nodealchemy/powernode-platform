import React, { useState } from 'react';
import {
  Shield, Users, TrendingUp, TrendingDown, Eye, Bot,
  Zap, GitBranch, Radio, ShieldCheck, ClipboardCheck
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { useAutonomyStats, useTrustScores, useAgentBudgets, useAgentLineage } from '../api/autonomyApi';
import { TrustScoreCard } from '../components/TrustScoreCard';
import { AgentLineageTree } from '../components/AgentLineageTree';
import { BudgetAllocationPanel } from '../components/BudgetAllocationPanel';
import { BudgetRegimeIndicator } from '../components/BudgetRegimeIndicator';
import { CapabilityMatrixViewer } from '../components/CapabilityMatrixViewer';
import { CircuitBreakerStatusPanel } from '../components/CircuitBreakerStatusPanel';
import { BehavioralFingerprintChart } from '../components/BehavioralFingerprintChart';
import { ApprovalQueuePanel } from '../components/ApprovalQueuePanel';
import { DelegationPolicyPanel } from '../components/DelegationPolicyPanel';
import { ShadowModeResultsPanel } from '../components/ShadowModeResultsPanel';
import { TelemetryEventStream } from '../components/TelemetryEventStream';
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
  if (pct >= 90) { level = 'CRITICAL'; message = 'Budget nearly exhausted — immediate attention required'; }
  else if (pct >= 75) { level = 'LOW'; message = 'Budget running low — consider reducing agent spend'; }
  else if (pct >= 50) { level = 'MEDIUM'; message = 'Budget utilization is moderate'; }
  else { level = 'HIGH'; message = 'Budget availability is healthy'; }
  return { level, utilization_pct: pct, remaining_cents: remaining, message };
}

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
  const { data: lineage } = useAgentLineage(selectedAgentId);

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="Agent Lineage" />
        <CardContent>
          <div className="mb-4">
            <label className="block text-sm text-theme-muted mb-1">Select Agent</label>
            <select
              className="w-full max-w-xs rounded-md border border-theme-border bg-theme-bg-primary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
              value={selectedAgentId}
              onChange={(e) => onAgentSelect(e.target.value)}
            >
              <option value="">Choose an agent...</option>
              {trustScores.map((s) => (
                <option key={s.agent_id} value={s.agent_id}>
                  {s.agent_name}
                </option>
              ))}
            </select>
          </div>
          {lineage ? (
            <AgentLineageTree root={lineage} />
          ) : (
            <p className="text-sm text-theme-muted py-4 text-center">
              {selectedAgentId ? 'Loading lineage...' : 'Select an agent to view its lineage tree.'}
            </p>
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

export const AutonomyContent: React.FC = () => {
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

  return (
    <Tabs defaultValue="overview">
      <TabsList className="mb-2 overflow-x-auto">
        <TabsTrigger value="overview">
          <span className="flex items-center gap-1.5"><Bot className="h-3.5 w-3.5" /> Overview</span>
        </TabsTrigger>
        <TabsTrigger value="trust">
          <span className="flex items-center gap-1.5"><Shield className="h-3.5 w-3.5" /> Trust Scores</span>
        </TabsTrigger>
        <TabsTrigger value="lineage">
          <span className="flex items-center gap-1.5"><GitBranch className="h-3.5 w-3.5" /> Lineage</span>
        </TabsTrigger>
        <TabsTrigger value="budgets">
          <span className="flex items-center gap-1.5"><Zap className="h-3.5 w-3.5" /> Budgets</span>
        </TabsTrigger>
        <TabsTrigger value="approvals">
          <span className="flex items-center gap-1.5"><ClipboardCheck className="h-3.5 w-3.5" /> Approvals</span>
        </TabsTrigger>
        <TabsTrigger value="security">
          <span className="flex items-center gap-1.5"><ShieldCheck className="h-3.5 w-3.5" /> Security</span>
        </TabsTrigger>
        <TabsTrigger value="shadow">
          <span className="flex items-center gap-1.5"><Eye className="h-3.5 w-3.5" /> Shadow Mode</span>
        </TabsTrigger>
        <TabsTrigger value="telemetry">
          <span className="flex items-center gap-1.5"><Radio className="h-3.5 w-3.5" /> Telemetry</span>
        </TabsTrigger>
      </TabsList>

      <TabsContent value="overview">
        <OverviewTab stats={safeStats} />
      </TabsContent>

      <TabsContent value="trust">
        <TrustScoresTab trustScores={safeTrustScores} />
      </TabsContent>

      <TabsContent value="lineage">
        <LineageTab
          trustScores={safeTrustScores}
          selectedAgentId={selectedAgentId}
          onAgentSelect={setSelectedAgentId}
        />
      </TabsContent>

      <TabsContent value="budgets">
        <BudgetsTab budgets={safeBudgets} stats={safeStats} />
      </TabsContent>

      <TabsContent value="approvals">
        <ApprovalQueuePanel />
      </TabsContent>

      <TabsContent value="security">
        <SecurityTab selectedAgentId={selectedAgentId} />
      </TabsContent>

      <TabsContent value="shadow">
        <ShadowModeResultsPanel />
      </TabsContent>

      <TabsContent value="telemetry">
        <TelemetryEventStream />
      </TabsContent>
    </Tabs>
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
