import React, { useState } from 'react';
import { Shield, Users, TrendingUp, TrendingDown, Eye, Bot } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAutonomyStats, useTrustScores, useAgentBudgets, useAgentLineage } from '../api/autonomyApi';
import { TrustScoreCard } from '../components/TrustScoreCard';
import { AgentLineageTree } from '../components/AgentLineageTree';
import { BudgetAllocationPanel } from '../components/BudgetAllocationPanel';

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

export const AutonomyContent: React.FC = () => {
  const [selectedAgentId, setSelectedAgentId] = useState('');

  const { data: stats, isLoading: statsLoading } = useAutonomyStats();
  const { data: trustScores, isLoading: scoresLoading } = useTrustScores();
  const { data: budgets, isLoading: budgetsLoading } = useAgentBudgets();
  const { data: lineage } = useAgentLineage(selectedAgentId);

  const isLoading = statsLoading || scoresLoading || budgetsLoading;

  if (isLoading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading autonomy data..." />;
  }

  return (
    <>
      {/* Stats Overview */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-4 mb-6">
        <StatCard label="Total Agents" value={stats?.total_agents ?? 0} icon={Bot} iconColor="text-theme-info" />
        <StatCard label="Supervised" value={stats?.supervised ?? 0} icon={Eye} iconColor="text-theme-warning" />
        <StatCard label="Monitored" value={stats?.monitored ?? 0} icon={Shield} iconColor="text-theme-info" />
        <StatCard label="Trusted" value={stats?.trusted ?? 0} icon={Users} iconColor="text-theme-success" />
        <StatCard label="Autonomous" value={stats?.autonomous ?? 0} icon={Bot} iconColor="text-theme-primary" />
        <StatCard label="Pending Promotions" value={stats?.pending_promotions ?? 0} icon={TrendingUp} iconColor="text-theme-success" />
        <StatCard label="Pending Demotions" value={stats?.pending_demotions ?? 0} icon={TrendingDown} iconColor="text-theme-error" />
      </div>

      {/* Trust Scores */}
      <div className="mb-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Trust Scores</h2>
        {trustScores && trustScores.length > 0 ? (
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
      </div>

      {/* Lineage Tree */}
      <div className="mb-6">
        <Card>
          <CardHeader title="Agent Lineage" />
          <CardContent>
            <div className="mb-4">
              <label className="block text-sm text-theme-muted mb-1">Select Agent</label>
              <select
                className="w-full max-w-xs rounded-md border border-theme-border bg-theme-bg-primary text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info"
                value={selectedAgentId}
                onChange={(e) => setSelectedAgentId(e.target.value)}
              >
                <option value="">Choose an agent...</option>
                {trustScores?.map((s) => (
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
      </div>

      {/* Budget Allocations */}
      <BudgetAllocationPanel budgets={budgets ?? []} />
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
