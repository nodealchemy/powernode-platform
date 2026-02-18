import React from 'react';
import { Activity, AlertTriangle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { useBehavioralFingerprints } from '../api/autonomyApi';
import type { BehavioralFingerprint } from '../types/autonomy';

interface BehavioralFingerprintChartProps {
  agentId: string;
}

const FingerprintRow: React.FC<{ fp: BehavioralFingerprint }> = ({ fp }) => {
  const hasAnomalies = fp.anomaly_count > 0;

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-theme-surface border border-theme-border">
      <div className="flex items-center gap-3">
        {hasAnomalies ? (
          <AlertTriangle className="h-4 w-4 text-theme-warning" />
        ) : (
          <Activity className="h-4 w-4 text-theme-success" />
        )}
        <div>
          <span className="text-sm font-medium text-theme-primary">
            {fp.metric_name.replace(/_/g, ' ')}
          </span>
          <div className="text-xs text-theme-muted mt-0.5">
            Mean: {fp.baseline_mean.toFixed(3)} | StdDev: {fp.baseline_stddev.toFixed(3)} | Threshold: {fp.deviation_threshold}σ
          </div>
        </div>
      </div>
      <div className="text-right">
        <p className="text-sm font-medium text-theme-primary">{fp.observation_count}</p>
        <p className="text-xs text-theme-muted">observations</p>
        {hasAnomalies && (
          <p className="text-xs text-theme-warning">{fp.anomaly_count} anomalies</p>
        )}
      </div>
    </div>
  );
};

export const BehavioralFingerprintChart: React.FC<BehavioralFingerprintChartProps> = ({ agentId }) => {
  const { data: fingerprints, isLoading } = useBehavioralFingerprints(agentId);

  if (isLoading || !agentId) return null;

  return (
    <Card>
      <CardHeader title="Behavioral Fingerprints" />
      <CardContent>
        {fingerprints && fingerprints.length > 0 ? (
          <div className="space-y-2">
            {fingerprints.map(fp => (
              <FingerprintRow key={fp.id} fp={fp} />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <Activity className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No behavioral data yet. Fingerprints build as agents operate.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
