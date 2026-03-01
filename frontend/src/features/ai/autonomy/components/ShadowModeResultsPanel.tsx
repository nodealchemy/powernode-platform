import React from 'react';
import { Eye, CheckCircle, XCircle } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { useShadowExecutions } from '../api/autonomyApi';
import type { ShadowExecution } from '../types/autonomy';

const formatDate = (dateStr: string): string => {
  return new Date(dateStr).toLocaleString();
};

const ExecutionRow: React.FC<{ execution: ShadowExecution }> = ({ execution }) => (
  <div className="p-3 rounded-lg bg-theme-surface border border-theme-border">
    <div className="flex items-center justify-between mb-2">
      <div className="flex items-center gap-2">
        {execution.agreed ? (
          <CheckCircle className="h-4 w-4 text-theme-success" />
        ) : (
          <XCircle className="h-4 w-4 text-theme-error" />
        )}
        <span className="text-sm font-medium text-theme-primary">{execution.agent_name}</span>
        <span className="text-xs text-theme-muted">({execution.action_type})</span>
      </div>
      <Badge
        variant={execution.agreed ? 'success' : 'default'}
        size="sm"
      >
        {Math.round(execution.agreement_score * 100)}% match
      </Badge>
    </div>
    <p className="text-xs text-theme-muted">{formatDate(execution.created_at)}</p>
  </div>
);

export const ShadowModeResultsPanel: React.FC = () => {
  const { data: executions, isLoading } = useShadowExecutions();

  if (isLoading) return null;

  const agreed = executions?.filter(e => e.agreed).length ?? 0;
  const total = executions?.length ?? 0;
  const rate = total > 0 ? Math.round((agreed / total) * 100) : 0;

  return (
    <Card>
      <CardHeader title={`Shadow Mode Results (${rate}% agreement)`} />
      <CardContent>
        {executions && executions.length > 0 ? (
          <div className="space-y-2">
            {executions.slice(0, 20).map(e => (
              <ExecutionRow key={e.id} execution={e} />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <Eye className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No shadow executions recorded</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
