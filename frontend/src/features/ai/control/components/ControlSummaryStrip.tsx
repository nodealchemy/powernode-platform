import React from 'react';
import { Shield, Users, TrendingUp, TrendingDown, Eye, Bot, FileCheck, AlertTriangle } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Card } from '@/shared/components/ui/Card';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAutonomyStats } from '@/features/ai/autonomy/api/autonomyApi';
import { governanceApi } from '@/shared/services/ai/GovernanceApiService';

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
        <p className="text-sm text-theme-tertiary">{label}</p>
        <p className="text-2xl font-semibold text-theme-primary">{value}</p>
      </div>
      <div className="h-10 w-10 rounded-lg flex items-center justify-center" style={{ backgroundColor: 'var(--theme-bg-secondary)' }}>
        <Icon className={`h-5 w-5 ${iconColor}`} />
      </div>
    </div>
  </Card>
);

/**
 * The strip at the top of AI → Control: agents by autonomy tier and pending
 * tier changes (ai.agents.read, what /ai/autonomy/stats checks), then active
 * compliance policies and open violations (ai.governance.read). Each half is
 * shown only to holders of its permission.
 */
export const ControlSummaryStrip: React.FC = () => {
  const { hasPermission } = usePermissions();
  const canReadAgents = hasPermission('ai.agents.read');
  const canReadGovernance = hasPermission('ai.governance.read');
  const { data: stats } = useAutonomyStats({ enabled: canReadAgents });
  const { data: compliance } = useQuery({
    queryKey: ['control', 'governance-summary'],
    queryFn: async () => (await governanceApi.getSummary()).summary ?? null,
    enabled: canReadGovernance,
  });

  if (!stats && !compliance) return null;

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-9 gap-4 mb-6" data-testid="control-summary">
      {stats && (
        <>
          <StatCard label="Total Agents" value={stats.total_agents} icon={Bot} iconColor="text-theme-info-fg" />
          <StatCard label="Supervised" value={stats.supervised} icon={Eye} iconColor="text-theme-warning-fg" />
          <StatCard label="Monitored" value={stats.monitored} icon={Shield} iconColor="text-theme-info-fg" />
          <StatCard label="Trusted" value={stats.trusted} icon={Users} iconColor="text-theme-success-fg" />
          <StatCard label="Autonomous" value={stats.autonomous} icon={Bot} iconColor="text-theme-primary" />
          <StatCard label="Pending Promotions" value={stats.pending_promotions} icon={TrendingUp} iconColor="text-theme-success-fg" />
          <StatCard label="Pending Demotions" value={stats.pending_demotions} icon={TrendingDown} iconColor="text-theme-error-fg" />
        </>
      )}
      {compliance && (
        <>
          <StatCard label="Active Policies" value={compliance.policies.active} icon={FileCheck} iconColor="text-theme-info-fg" />
          <StatCard label="Open Violations" value={compliance.violations.open} icon={AlertTriangle} iconColor="text-theme-error-fg" />
        </>
      )}
    </div>
  );
};
