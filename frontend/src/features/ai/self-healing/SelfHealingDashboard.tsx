import React, { useState, useCallback, useEffect } from 'react';
import { Shield, Activity, AlertTriangle, Clock, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { RemediationTimeline } from './RemediationTimeline';
import { HealthCorrelationView } from './HealthCorrelationView';
import { apiClient } from '@/shared/services/apiClient';

interface RemediationLog {
  id: string;
  trigger_source: string;
  trigger_event: string;
  action_type: string;
  result: string;
  result_message: string;
  executed_at: string;
  before_state: Record<string, unknown>;
  after_state: Record<string, unknown>;
}

interface HealthSummary {
  overall_status: string;
  remediation_count_1h: number;
  success_rate: number;
  active_circuit_breakers: number;
  feature_flag_enabled: boolean;
}

interface Correlation {
  ai_failure: Record<string, unknown>;
  correlated_devops_events: Record<string, unknown>[];
  confidence: number;
  suggested_cause: string;
}

export const SelfHealingDashboard: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [remediationLogs, setRemediationLogs] = useState<RemediationLog[]>([]);
  const [healthSummary, setHealthSummary] = useState<HealthSummary | null>(null);
  const [correlations, setCorrelations] = useState<Correlation[]>([]);
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [logsRes, healthRes, correlationsRes] = await Promise.all([
        apiClient.get('/ai/self_healing/remediation_logs'),
        apiClient.get('/ai/self_healing/health_summary'),
        apiClient.get('/ai/self_healing/correlations'),
      ]);

      setRemediationLogs(logsRes.data?.remediation_logs || []);
      setHealthSummary(logsRes.data?.health_summary || healthRes.data);
      setCorrelations(correlationsRes.data?.correlations || []);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load self-healing data' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 30000);
    return () => clearInterval(interval);
  }, [loadData]);

  if (loading && !healthSummary) return <LoadingSpinner />;

  const statusColor = healthSummary?.overall_status === 'healthy'
    ? 'text-theme-success'
    : healthSummary?.overall_status === 'degraded'
      ? 'text-theme-warning'
      : 'text-theme-error';

  return (
    <PageContainer
      title="Self-Healing"
      description="Automated remediation and health monitoring"
      actions={[
        {
          label: 'Refresh',
          onClick: loadData,
          variant: 'outline',
          icon: RefreshCw,
        },
      ]}
    >
      <div className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <Shield className={`w-8 h-8 ${statusColor}`} />
                <div>
                  <p className="text-sm text-theme-muted">Status</p>
                  <p className={`text-lg font-semibold ${statusColor}`}>
                    {healthSummary?.overall_status || 'Unknown'}
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <Activity className="w-8 h-8 text-theme-info" />
                <div>
                  <p className="text-sm text-theme-muted">Actions (1h)</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {healthSummary?.remediation_count_1h ?? 0}
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <AlertTriangle className="w-8 h-8 text-theme-warning" />
                <div>
                  <p className="text-sm text-theme-muted">Success Rate</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {healthSummary?.success_rate ?? 0}%
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-3">
                <Clock className="w-8 h-8 text-theme-muted" />
                <div>
                  <p className="text-sm text-theme-muted">Open Breakers</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {healthSummary?.active_circuit_breakers ?? 0}
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {!healthSummary?.feature_flag_enabled && (
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-2 text-theme-warning">
                <AlertTriangle className="w-5 h-5" />
                <span className="text-sm font-medium">
                  Self-healing remediation is currently disabled. Enable the feature flag to activate automated actions.
                </span>
              </div>
            </CardContent>
          </Card>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader title="Remediation Timeline" />
            <CardContent>
              <RemediationTimeline logs={remediationLogs} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader title="Cross-System Correlations" />
            <CardContent>
              <HealthCorrelationView correlations={correlations} />
            </CardContent>
          </Card>
        </div>
      </div>
    </PageContainer>
  );
};
