import React, { useState } from 'react';
import { 
  Zap, RefreshCw, Trash2, HardDrive, Database, 
  Clock, AlertTriangle, CheckCircle, Loader
} from 'lucide-react';
import { performanceApi, OptimizationAction } from '../../services/performanceApi';
import { useNotification } from '../../hooks/useNotification';

interface PerformanceOptimizationPanelProps {
  onOptimizationComplete?: () => void;
}

interface ActionCardProps {
  action: OptimizationAction;
  onExecute: (actionId: string) => void;
  executing: boolean;
}

const ActionCard: React.FC<ActionCardProps> = ({ action, onExecute, executing }) => {
  const impactColors = {
    low: 'border-theme-info bg-theme-info-background text-theme-info',
    medium: 'border-theme-warning bg-theme-warning-background text-theme-warning',
    high: 'border-theme-success bg-theme-success-background text-theme-success'
  };

  const riskColors = {
    safe: 'text-theme-success',
    medium: 'text-theme-warning',
    high: 'text-theme-error'
  };

  const getActionIcon = (type: string) => {
    switch (type) {
      case 'cache_clear': return <Trash2 className="w-5 h-5" />;
      case 'restart_workers': return <RefreshCw className="w-5 h-5" />;
      case 'compress_logs': return <HardDrive className="w-5 h-5" />;
      case 'rebuild_indexes': return <Database className="w-5 h-5" />;
      case 'cleanup_temp_files': return <Trash2 className="w-5 h-5" />;
      default: return <Zap className="w-5 h-5" />;
    }
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg text-theme-interactive-primary">
            {getActionIcon(action.type)}
          </div>
          <div>
            <h3 className="font-semibold text-theme-primary">{action.name}</h3>
            <p className="text-sm text-theme-secondary mt-1">{action.description}</p>
          </div>
        </div>
        
        <div className={`px-2 py-1 rounded-full text-xs font-medium ${impactColors[action.estimated_impact]}`}>
          {action.estimated_impact.toUpperCase()} IMPACT
        </div>
      </div>
      
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4 text-sm">
          <div className="flex items-center gap-1">
            <Clock className="w-4 h-4 text-theme-secondary" />
            <span className="text-theme-secondary">{action.estimated_time}</span>
          </div>
          <div className={`flex items-center gap-1 ${riskColors[action.risk_level]}`}>
            <AlertTriangle className="w-4 h-4" />
            <span className="capitalize">{action.risk_level} risk</span>
          </div>
        </div>
        
        <button
          onClick={() => onExecute(action.id)}
          disabled={executing}
          className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
        >
          {executing ? (
            <>
              <Loader className="w-4 h-4 animate-spin" />
              Running...
            </>
          ) : (
            <>
              <Zap className="w-4 h-4" />
              Execute
            </>
          )}
        </button>
      </div>
    </div>
  );
};

export const PerformanceOptimizationPanel: React.FC<PerformanceOptimizationPanelProps> = ({
  onOptimizationComplete
}) => {
  const [actions, setActions] = useState<OptimizationAction[]>([]);
  const [loading, setLoading] = useState(true);
  const [executingActions, setExecutingActions] = useState<Set<string>>(new Set());
  const [recentExecutions, setRecentExecutions] = useState<{[key: string]: Date}>({});
  
  const { showNotification } = useNotification();

  React.useEffect(() => {
    loadOptimizationActions();
  }, []);

  const loadOptimizationActions = async () => {
    try {
      setLoading(true);
      const response = await performanceApi.getOptimizationActions();
      if (response.success && response.data) {
        setActions(response.data);
      }
    } catch (error) {
      console.error('Failed to load optimization actions:', error);
      showNotification('Failed to load optimization actions', 'error');
    } finally {
      setLoading(false);
    }
  };

  const executeOptimization = async (actionId: string) => {
    const action = actions.find(a => a.id === actionId);
    if (!action) return;

    // Confirmation for high-risk actions
    if (action.risk_level === 'high') {
      const confirmed = window.confirm(
        `This is a high-risk operation: ${action.name}. Are you sure you want to proceed?`
      );
      if (!confirmed) return;
    }

    try {
      setExecutingActions(prev => {
        const newSet = new Set(prev);
        newSet.add(actionId);
        return newSet;
      });
      
      const response = await performanceApi.executeOptimization(actionId);
      
      if (response.success) {
        showNotification(`${action.name} completed successfully`, 'success');
        setRecentExecutions(prev => ({ ...prev, [actionId]: new Date() }));
        onOptimizationComplete?.();
      } else {
        showNotification(response.error || `Failed to execute ${action.name}`, 'error');
      }
    } catch (error) {
      console.error('Failed to execute optimization:', error);
      showNotification(`Failed to execute ${action.name}`, 'error');
    } finally {
      setExecutingActions(prev => {
        const newSet = new Set(prev);
        newSet.delete(actionId);
        return newSet;
      });
    }
  };

  const getQuickActions = () => [
    {
      id: 'cache_clear',
      name: 'Clear Application Cache',
      description: 'Clear all cached data to free up memory and ensure fresh data',
      type: 'cache_clear' as const,
      estimated_impact: 'medium' as const,
      risk_level: 'safe' as const,
      estimated_time: '1-2 minutes'
    },
    {
      id: 'restart_workers',
      name: 'Restart Background Workers',
      description: 'Restart all background job workers to clear stuck processes',
      type: 'restart_workers' as const,
      estimated_impact: 'high' as const,
      risk_level: 'medium' as const,
      estimated_time: '2-3 minutes'
    }
  ];

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader className="w-8 h-8 animate-spin text-theme-interactive-primary" />
      </div>
    );
  }

  const availableActions = actions.length > 0 ? actions : getQuickActions();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Performance Optimization</h3>
          <p className="text-theme-secondary">Execute optimization actions to improve system performance</p>
        </div>
        
        <button
          onClick={loadOptimizationActions}
          className="p-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface"
          title="Refresh actions"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {/* Recent Executions */}
      {Object.keys(recentExecutions).length > 0 && (
        <div className="bg-theme-success-background border border-theme-success rounded-lg p-4">
          <div className="flex items-start gap-3">
            <CheckCircle className="w-5 h-5 text-theme-success mt-0.5" />
            <div>
              <h4 className="font-medium text-theme-success mb-2">Recent Optimizations</h4>
              <div className="space-y-1">
                {Object.entries(recentExecutions).map(([actionId, executedAt]) => {
                  const action = availableActions.find(a => a.id === actionId);
                  return (
                    <p key={actionId} className="text-sm text-theme-success">
                      {action?.name || actionId} completed at {executedAt.toLocaleTimeString()}
                    </p>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Optimization Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {availableActions.map(action => (
          <ActionCard
            key={action.id}
            action={action}
            onExecute={executeOptimization}
            executing={executingActions.has(action.id)}
          />
        ))}
      </div>

      {/* Safety Notice */}
      <div className="bg-theme-warning-background border border-theme-warning rounded-lg p-4">
        <div className="flex items-start gap-3">
          <AlertTriangle className="w-5 h-5 text-theme-warning mt-0.5" />
          <div>
            <h4 className="font-medium text-theme-warning mb-2">Safety Guidelines</h4>
            <ul className="text-sm text-theme-warning space-y-1 list-disc list-inside">
              <li>Always review the impact and risk level before executing optimizations</li>
              <li>High-risk operations may cause temporary service interruptions</li>
              <li>Consider running optimizations during maintenance windows</li>
              <li>Monitor system metrics after optimization completion</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PerformanceOptimizationPanel;