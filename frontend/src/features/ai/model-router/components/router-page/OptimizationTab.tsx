import React from 'react';
import { TrendingUp, Search, Play } from 'lucide-react';
import { CostOptimizationLog, OptimizationStats } from '@/shared/services/ai/ModelRouterApiService';

interface OptimizationTabProps {
  optimizations: CostOptimizationLog[];
  optimizationStats: OptimizationStats | null;
  onIdentifyOptimizations: () => void;
  onApplyOptimization: (optimizationId: string) => void;
}

export const OptimizationTab: React.FC<OptimizationTabProps> = ({
  optimizations,
  optimizationStats,
  onIdentifyOptimizations,
  onApplyOptimization,
}) => {
  return (
    <div className="space-y-6">
      {/* Stats */}
      {optimizationStats && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {Object.entries(optimizationStats).filter(([, value]) => typeof value === 'number').slice(0, 4).map(([key, value]) => (
            <div key={key} className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-sm text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
              <p className="text-2xl font-bold text-theme-primary">{typeof value === 'number' ? value.toLocaleString() : String(value)}</p>
            </div>
          ))}
        </div>
      )}

      {/* Actions */}
      <div className="flex justify-end">
        <button onClick={onIdentifyOptimizations} className="btn-theme btn-theme-secondary">
          <Search size={14} className="mr-1 inline" /> Identify Optimizations
        </button>
      </div>

      {/* Optimization List */}
      {optimizations.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <TrendingUp size={48} className="mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No optimizations found</h3>
          <p className="text-theme-secondary mb-6">Click &quot;Identify Optimizations&quot; to scan for cost-saving opportunities</p>
        </div>
      ) : (
        <div className="space-y-4">
          {optimizations.map(opt => (
            <div key={opt.id} className="bg-theme-surface border border-theme rounded-lg p-4">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-3">
                  <h3 className="font-medium text-theme-primary">{opt.optimization_type}</h3>
                  <span className={`px-2 py-1 text-xs rounded ${
                    opt.status === 'applied' ? 'text-theme-success bg-theme-success/10' :
                    opt.status === 'identified' ? 'text-theme-warning bg-theme-warning/10' :
                    opt.status === 'recommended' ? 'text-theme-info bg-theme-info/10' :
                    'text-theme-secondary bg-theme-surface'
                  }`}>{opt.status}</span>
                </div>
                {(opt.status === 'identified' || opt.status === 'recommended') && (
                  <button onClick={() => onApplyOptimization(opt.id)} className="btn-theme btn-theme-success btn-theme-sm">
                    <Play size={14} className="mr-1" /> Apply
                  </button>
                )}
              </div>
              {opt.description && <p className="text-sm text-theme-secondary mb-2">{opt.description}</p>}
              <div className="flex gap-4 text-xs text-theme-secondary">
                {opt.potential_savings_usd && <span className="text-theme-success">Est. savings: ${opt.potential_savings_usd.toFixed(2)}</span>}
                {opt.actual_savings_usd && <span className="text-theme-success">Actual savings: ${opt.actual_savings_usd.toFixed(2)}</span>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
