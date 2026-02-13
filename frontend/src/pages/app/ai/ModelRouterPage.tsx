// Model Router Page - Intelligent AI Request Routing
import React, { useState, useEffect } from 'react';
import {
  Route, Search, BarChart3, Zap, Trash2,
  TrendingUp, ToggleLeft, ToggleRight, Lightbulb, Play,
  ChevronDown, ChevronUp, Clock, Shield, Loader2, Crosshair
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  modelRouterApi,
  RoutingRule,
  RoutingDecision,
  RoutingStatistics,
  CostAnalysis,
  ProviderRanking,
  OptimizationRecommendation,
  CostOptimizationLog,
  OptimizationStats
} from '@/shared/services/ai/ModelRouterApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'rules' | 'decisions' | 'analytics' | 'optimization';

// ============================================================================
// Detail rendering helpers
// ============================================================================

const formatLabel = (key: string): string =>
  key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

const DetailValue: React.FC<{ value: unknown }> = ({ value }) => {
  if (value === null || value === undefined) return <span className="text-theme-tertiary italic">—</span>;
  if (Array.isArray(value)) {
    if (value.length === 0) return <span className="text-theme-tertiary italic">none</span>;
    return (
      <div className="flex flex-wrap gap-1 mt-0.5">
        {value.map((v, i) => (
          <span key={i} className="px-1.5 py-0.5 text-xs bg-theme-surface rounded border border-theme font-mono">
            {String(v)}
          </span>
        ))}
      </div>
    );
  }
  if (typeof value === 'object') {
    return (
      <pre className="text-xs bg-theme-surface p-2 rounded overflow-x-auto font-mono mt-0.5">
        {JSON.stringify(value, null, 2)}
      </pre>
    );
  }
  if (typeof value === 'boolean') {
    return <span className={value ? 'text-theme-success' : 'text-theme-danger'}>{value ? 'Yes' : 'No'}</span>;
  }
  if (typeof value === 'number') {
    return <span className="font-mono">{value.toLocaleString()}</span>;
  }
  return <span className="font-mono">{String(value)}</span>;
};

const DetailSection: React.FC<{ title: string; icon: React.ReactNode; children: React.ReactNode }> = ({ title, icon, children }) => (
  <div className="bg-theme-bg rounded-lg p-3">
    <h4 className="flex items-center gap-1.5 text-xs font-semibold text-theme-secondary uppercase tracking-wide mb-2.5">
      {icon} {title}
    </h4>
    {children}
  </div>
);

const renderJsonEntries = (obj: Record<string, unknown> | undefined): React.ReactNode => {
  if (!obj || Object.keys(obj).length === 0) {
    return <p className="text-xs text-theme-tertiary italic">Not configured</p>;
  }
  return (
    <dl className="space-y-2">
      {Object.entries(obj).map(([key, value]) => (
        <div key={key}>
          <dt className="text-xs text-theme-secondary">{formatLabel(key)}</dt>
          <dd className="text-xs text-theme-primary">
            <DetailValue value={value} />
          </dd>
        </div>
      ))}
    </dl>
  );
};

const renderThresholds = (thresholds: RoutingRule['thresholds']): React.ReactNode => {
  if (!thresholds) return <p className="text-xs text-theme-tertiary italic">No thresholds set</p>;
  const entries: [string, string | null][] = [
    ['Max Cost / 1k Tokens', thresholds.max_cost_per_1k_tokens != null ? `$${Number(thresholds.max_cost_per_1k_tokens).toFixed(4)}` : null],
    ['Max Latency', thresholds.max_latency_ms != null ? `${Number(thresholds.max_latency_ms).toLocaleString()}ms` : null],
    ['Min Quality Score', thresholds.min_quality_score != null ? Number(thresholds.min_quality_score).toFixed(2) : null],
  ];
  const validEntries = entries.filter((e): e is [string, string] => e[1] !== null);
  if (validEntries.length === 0) return <p className="text-xs text-theme-tertiary italic">No thresholds set</p>;
  return (
    <dl className="space-y-1.5">
      {validEntries.map(([label, val]) => (
        <div key={label} className="flex justify-between text-xs">
          <dt className="text-theme-secondary">{label}</dt>
          <dd className="font-mono text-theme-primary">{val}</dd>
        </div>
      ))}
    </dl>
  );
};

// ============================================================================
// Main Component
// ============================================================================

export const ModelRouterContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('rules');
  const [rules, setRules] = useState<RoutingRule[]>([]);
  const [decisions, setDecisions] = useState<RoutingDecision[]>([]);
  const [statistics, setStatistics] = useState<RoutingStatistics | null>(null);
  const [costAnalysis, setCostAnalysis] = useState<CostAnalysis | null>(null);
  const [rankings, setRankings] = useState<ProviderRanking[]>([]);
  const [recommendations, setRecommendations] = useState<OptimizationRecommendation[]>([]);
  const [optimizations, setOptimizations] = useState<CostOptimizationLog[]>([]);
  const [optimizationStats, setOptimizationStats] = useState<OptimizationStats | null>(null);
  const [loading, setLoading] = useState(true);

  // Create rule modal
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newRuleName, setNewRuleName] = useState('');
  const [newRuleType, setNewRuleType] = useState<string>('cost_based');
  const [newRuleDescription, setNewRuleDescription] = useState('');

  // Delete confirmation
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);
  const ruleToDelete = rules.find(r => r.id === deleteConfirmId);

  // Expandable rule details
  const [expandedRuleId, setExpandedRuleId] = useState<string | null>(null);
  const [expandedRuleDetails, setExpandedRuleDetails] = useState<Record<string, RoutingRule>>({});
  const [loadingExpandId, setLoadingExpandId] = useState<string | null>(null);

  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      loadData();
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setLoading(true);
      const [rulesRes, decisionsRes, statsRes, costRes, rankingsRes, recsRes, optsRes] = await Promise.all([
        modelRouterApi.getRules(),
        modelRouterApi.getDecisions(),
        modelRouterApi.getStatistics(),
        modelRouterApi.getCostAnalysis(),
        modelRouterApi.getProviderRankings(),
        modelRouterApi.getRecommendations(),
        modelRouterApi.getOptimizations()
      ]);
      const rulesData = rulesRes as unknown as { rules?: RoutingRule[]; items?: RoutingRule[] };
      const decisionsData = decisionsRes as unknown as { decisions?: RoutingDecision[]; items?: RoutingDecision[] };
      setRules(rulesData.rules || rulesData.items || []);
      setDecisions(decisionsData.decisions || decisionsData.items || []);
      const statsData = statsRes as unknown as { statistics?: RoutingStatistics };
      setStatistics(statsData.statistics || statsRes);
      const costData = costRes as unknown as { cost_analysis?: CostAnalysis };
      setCostAnalysis(costData.cost_analysis || costRes);
      const rankData = rankingsRes as unknown as { rankings?: ProviderRanking[] };
      setRankings(rankData.rankings || (Array.isArray(rankingsRes) ? rankingsRes : []));
      const recsData = recsRes as unknown as { recommendations?: OptimizationRecommendation[] };
      setRecommendations(recsData.recommendations || (Array.isArray(recsRes) ? recsRes : []));
      setOptimizations(optsRes.optimizations || []);
      setOptimizationStats(optsRes.stats || null);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load model router data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleToggleRule = async (ruleId: string) => {
    try {
      const updated = await modelRouterApi.toggleRule(ruleId);
      setRules(rules.map(r => r.id === ruleId ? updated : r));
      dispatch(addNotification({
        type: 'success',
        message: `Rule ${updated.is_active ? 'enabled' : 'disabled'}`
      }));
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to toggle rule')
      }));
    }
  };

  const handleDeleteRule = async (ruleId: string) => {
    try {
      await modelRouterApi.deleteRule(ruleId);
      setRules(rules.filter(r => r.id !== ruleId));
      if (expandedRuleId === ruleId) setExpandedRuleId(null);
      dispatch(addNotification({ type: 'success', message: 'Rule deleted' }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to delete rule') }));
    } finally {
      setDeleteConfirmId(null);
    }
  };

  const handleCreateRule = async () => {
    if (!newRuleName.trim()) return;
    try {
      const rule = await modelRouterApi.createRule({
        name: newRuleName,
        rule_type: newRuleType as RoutingRule['rule_type'],
        description: newRuleDescription || undefined
      });
      setRules([...rules, rule]);
      dispatch(addNotification({ type: 'success', message: 'Rule created' }));
      setShowCreateModal(false);
      setNewRuleName('');
      setNewRuleDescription('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create rule') }));
    }
  };

  const handleIdentifyOptimizations = async () => {
    try {
      const result = await modelRouterApi.identifyOptimizations();
      dispatch(addNotification({
        type: 'success',
        message: `Found ${result.opportunities_found} opportunities, created ${result.new_optimizations_created} new optimizations`
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to identify optimizations') }));
    }
  };

  const handleApplyOptimization = async (optimizationId: string) => {
    try {
      await modelRouterApi.applyOptimization(optimizationId);
      dispatch(addNotification({ type: 'success', message: 'Optimization applied' }));
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to apply optimization') }));
    }
  };

  const handleExpandRule = async (ruleId: string) => {
    if (expandedRuleId === ruleId) {
      setExpandedRuleId(null);
      return;
    }
    setExpandedRuleId(ruleId);
    if (!expandedRuleDetails[ruleId]) {
      try {
        setLoadingExpandId(ruleId);
        const res = await modelRouterApi.getRule(ruleId);
        const detail = (res as unknown as { rule?: RoutingRule }).rule || res;
        setExpandedRuleDetails(prev => ({ ...prev, [ruleId]: detail }));
      } catch {
        dispatch(addNotification({ type: 'error', message: 'Failed to load rule details' }));
        setExpandedRuleId(null);
      } finally {
        setLoadingExpandId(null);
      }
    }
  };

  const getRuleTypeColor = (type: string): string => {
    switch (type) {
      case 'cost_based': return 'text-theme-success bg-theme-success/10';
      case 'latency_based': return 'text-theme-warning bg-theme-warning/10';
      case 'quality_based': return 'text-theme-info bg-theme-info/10';
      case 'capability_based': return 'text-theme-accent bg-theme-accent/10';
      case 'custom': return 'text-theme-danger bg-theme-danger/10';
      case 'ml_optimized': return 'text-theme-primary bg-theme-primary/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const getDecisionColor = (outcome: string): string => {
    switch (outcome) {
      case 'success': return 'text-theme-success bg-theme-success/10';
      case 'failure': return 'text-theme-danger bg-theme-danger/10';
      case 'timeout': return 'text-theme-warning bg-theme-warning/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const tabs = [
    { id: 'rules' as TabType, label: 'Rules', icon: Route },
    { id: 'decisions' as TabType, label: 'Decisions', icon: Zap },
    { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 },
    { id: 'optimization' as TabType, label: 'Optimization', icon: TrendingUp }
  ];

  return (
    <>
      {/* Statistics Summary */}
      {statistics && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          {Object.entries(statistics).filter(([, value]) => typeof value === 'number').slice(0, 4).map(([key, value]) => (
            <div key={key} className="bg-theme-surface border border-theme rounded-lg p-4">
              <p className="text-sm text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
              <p className="text-2xl font-bold text-theme-primary">{typeof value === 'number' ? value.toLocaleString() : String(value)}</p>
            </div>
          ))}
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading router data...</p>
        </div>
      ) : (
        <>
          {/* Rules Tab */}
          {activeTab === 'rules' && (
            <div className="space-y-4">
              {rules.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Route size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No routing rules</h3>
                  <p className="text-theme-secondary mb-6">Create routing rules to optimize AI request distribution</p>
                  <button onClick={() => setShowCreateModal(true)} className="btn-theme btn-theme-primary">
                    Create Rule
                  </button>
                </div>
              ) : (
                rules.map(rule => {
                  const isExpanded = expandedRuleId === rule.id;
                  const detail = expandedRuleDetails[rule.id];
                  const isLoadingDetail = loadingExpandId === rule.id;

                  return (
                    <div key={rule.id} className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
                      {/* Clickable header */}
                      <div
                        className="flex items-center justify-between p-4 cursor-pointer select-none hover:bg-theme-surface-hover/50 transition-colors"
                        onClick={() => handleExpandRule(rule.id)}
                      >
                        <div className="flex items-center gap-3">
                          {isExpanded
                            ? <ChevronUp size={16} className="text-theme-accent flex-shrink-0" />
                            : <ChevronDown size={16} className="text-theme-secondary flex-shrink-0" />
                          }
                          <span className="text-sm font-mono text-theme-secondary">#{rule.priority}</span>
                          <h3 className="font-medium text-theme-primary">{rule.name}</h3>
                          <span className={`px-2 py-1 text-xs rounded ${getRuleTypeColor(rule.rule_type)}`}>{rule.rule_type}</span>
                        </div>
                        <div className="flex items-center gap-3" onClick={e => e.stopPropagation()}>
                          <button
                            onClick={() => handleToggleRule(rule.id)}
                            className="text-theme-secondary hover:text-theme-primary transition-colors"
                            title={rule.is_active ? 'Disable' : 'Enable'}
                          >
                            {rule.is_active ? <ToggleRight size={20} className="text-theme-success" /> : <ToggleLeft size={20} />}
                          </button>
                          <button
                            onClick={() => setDeleteConfirmId(rule.id)}
                            className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded border border-theme-danger/30 text-theme-danger hover:bg-theme-danger/10 transition-colors"
                            title="Delete rule"
                          >
                            <Trash2 size={13} />
                            Delete
                          </button>
                        </div>
                      </div>

                      {/* Description & stats (always visible) */}
                      {(rule.description || rule.stats) && (
                        <div className="px-4 pb-3 -mt-1">
                          {rule.description && <p className="text-sm text-theme-secondary mb-2 pl-7">{rule.description}</p>}
                          {rule.stats && (
                            <div className="flex gap-4 text-xs text-theme-secondary pl-7">
                              <span>{rule.stats.times_matched} matched</span>
                              <span className="text-theme-success">{rule.stats.times_succeeded} succeeded</span>
                              <span className="text-theme-danger">{rule.stats.times_failed} failed</span>
                              <span>{(rule.stats.success_rate * 100).toFixed(1)}% success</span>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Expanded details */}
                      {isExpanded && (
                        <div className="border-t border-theme px-4 py-4">
                          {isLoadingDetail ? (
                            <div className="flex items-center justify-center py-8">
                              <Loader2 size={20} className="animate-spin text-theme-accent" />
                              <span className="ml-2 text-sm text-theme-secondary">Loading rule details...</span>
                            </div>
                          ) : detail ? (
                            <div>
                              {/* Description from full details if not shown in collapsed view */}
                              {detail.description && !rule.description && (
                                <p className="text-sm text-theme-secondary mb-4">{detail.description}</p>
                              )}

                              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                                {/* Conditions */}
                                <DetailSection title="Conditions" icon={<Search size={12} />}>
                                  {renderJsonEntries(detail.conditions)}
                                </DetailSection>

                                {/* Target */}
                                <DetailSection title="Target" icon={<Crosshair size={12} />}>
                                  {renderJsonEntries(detail.target)}
                                </DetailSection>

                                {/* Thresholds */}
                                <DetailSection title="Thresholds" icon={<Shield size={12} />}>
                                  {renderThresholds(detail.thresholds)}
                                </DetailSection>

                                {/* Metadata */}
                                <DetailSection title="Metadata" icon={<Clock size={12} />}>
                                  <dl className="space-y-1.5">
                                    <div className="flex justify-between text-xs">
                                      <dt className="text-theme-secondary">Rule ID</dt>
                                      <dd className="font-mono text-theme-primary truncate ml-2" title={detail.id}>
                                        {detail.id.length > 16 ? `${detail.id.slice(0, 16)}...` : detail.id}
                                      </dd>
                                    </div>
                                    {detail.created_at && (
                                      <div className="flex justify-between text-xs">
                                        <dt className="text-theme-secondary">Created</dt>
                                        <dd className="text-theme-primary">{new Date(detail.created_at).toLocaleDateString()}</dd>
                                      </div>
                                    )}
                                    {detail.updated_at && (
                                      <div className="flex justify-between text-xs">
                                        <dt className="text-theme-secondary">Updated</dt>
                                        <dd className="text-theme-primary">{new Date(detail.updated_at).toLocaleDateString()}</dd>
                                      </div>
                                    )}
                                    {detail.stats?.last_matched_at && (
                                      <div className="flex justify-between text-xs">
                                        <dt className="text-theme-secondary">Last Matched</dt>
                                        <dd className="text-theme-primary">{new Date(detail.stats.last_matched_at).toLocaleDateString()}</dd>
                                      </div>
                                    )}
                                  </dl>
                                </DetailSection>
                              </div>
                            </div>
                          ) : null}
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          )}

          {/* Decisions Tab */}
          {activeTab === 'decisions' && (
            <div className="space-y-4">
              {decisions.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Zap size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No routing decisions</h3>
                  <p className="text-theme-secondary">Routing decisions will appear as requests are processed</p>
                </div>
              ) : (
                <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-theme bg-theme-bg">
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Decision</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Strategy</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Provider</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Outcome</th>
                        <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Latency</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Time</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-theme">
                      {decisions.map(decision => (
                        <tr key={decision.id} className="hover:bg-theme-surface-hover transition-colors">
                          <td className="px-4 py-3 text-sm font-mono text-theme-primary">{decision.id.slice(0, 8)}</td>
                          <td className="px-4 py-3 text-sm text-theme-primary">{decision.strategy_used || '-'}</td>
                          <td className="px-4 py-3 text-sm text-theme-primary">{decision.selected_provider?.name || '-'}</td>
                          <td className="px-4 py-3">
                            <span className={`px-2 py-1 text-xs rounded ${getDecisionColor(decision.outcome)}`}>
                              {decision.outcome}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-sm text-right text-theme-secondary">
                            {decision.performance?.latency_ms ? `${decision.performance.latency_ms}ms` : '-'}
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-secondary">
                            {new Date(decision.created_at).toLocaleString()}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {/* Analytics Tab */}
          {activeTab === 'analytics' && (
            <div className="space-y-6">
              {/* Cost Analysis */}
              {costAnalysis && (
                <div className="bg-theme-surface border border-theme rounded-lg p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Cost Analysis</h3>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    {Object.entries(costAnalysis).filter(([, value]) => typeof value === 'number').slice(0, 6).map(([key, value]) => (
                      <div key={key} className="p-3 bg-theme-bg rounded-lg">
                        <p className="text-xs text-theme-secondary">{key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</p>
                        <p className="text-lg font-semibold text-theme-primary">
                          {key.includes('usd') || key.includes('cost') || key.includes('savings')
                            ? `$${(value as number).toFixed(2)}`
                            : (value as number).toLocaleString()}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Provider Rankings */}
              {rankings.length > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Provider Rankings</h3>
                  <div className="space-y-3">
                    {rankings.map((ranking, idx) => (
                      <div key={ranking.provider_id || idx} className="flex items-center justify-between p-3 bg-theme-bg rounded-lg">
                        <div className="flex items-center gap-3">
                          <span className="text-lg font-bold text-theme-accent">#{idx + 1}</span>
                          <span className="text-sm font-medium text-theme-primary">{ranking.provider_name || ranking.provider_id}</span>
                        </div>
                        <div className="flex gap-4 text-xs text-theme-secondary">
                          {ranking.latency_score > 0 && <span>Latency: {ranking.latency_score.toFixed(1)}</span>}
                          {ranking.success_rate > 0 && <span>{(ranking.success_rate * 100).toFixed(1)}% success</span>}
                          {ranking.cost_score > 0 && <span>Cost: {ranking.cost_score.toFixed(1)}</span>}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Recommendations */}
              {recommendations.length > 0 && (
                <div className="bg-theme-surface border border-theme rounded-lg p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Recommendations</h3>
                  <div className="space-y-3">
                    {recommendations.map((rec, idx) => (
                      <div key={idx} className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
                        <Lightbulb size={16} className="text-theme-warning mt-0.5 flex-shrink-0" />
                        <div>
                          <p className="text-sm font-medium text-theme-primary">{rec.title}</p>
                          {rec.description && <p className="text-xs text-theme-secondary mt-1">{rec.description}</p>}
                          {rec.potential_savings_usd && (
                            <span className="inline-block mt-1 text-xs text-theme-success">
                              Est. savings: ${rec.potential_savings_usd.toFixed(2)}
                            </span>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Optimization Tab */}
          {activeTab === 'optimization' && (
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
                <button onClick={handleIdentifyOptimizations} className="btn-theme btn-theme-secondary">
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
                          <button
                            onClick={() => handleApplyOptimization(opt.id)}
                            className="btn-theme btn-theme-success btn-theme-sm"
                          >
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
          )}
        </>
      )}

      {/* Delete Confirmation Modal */}
      <Modal
        isOpen={!!deleteConfirmId}
        onClose={() => setDeleteConfirmId(null)}
        title="Delete Routing Rule"
        maxWidth="sm"
        icon={<Trash2 className="text-theme-danger" />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setDeleteConfirmId(null)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button
              onClick={() => deleteConfirmId && handleDeleteRule(deleteConfirmId)}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-md bg-theme-danger text-white hover:bg-theme-danger/90 transition-colors text-sm font-medium"
            >
              <Trash2 size={14} />
              Delete Rule
            </button>
          </div>
        }
      >
        <div className="p-4">
          <p className="text-sm text-theme-primary">
            Are you sure you want to delete <span className="font-semibold">{ruleToDelete?.name}</span>?
          </p>
          <p className="text-sm text-theme-secondary mt-2">
            This action cannot be undone. Any routing decisions referencing this rule will lose their rule association.
          </p>
        </div>
      </Modal>

      {/* Create Rule Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        title="Create Routing Rule"
        maxWidth="md"
        icon={<Route />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowCreateModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateRule} disabled={!newRuleName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input
              type="text"
              value={newRuleName}
              onChange={(e) => setNewRuleName(e.target.value)}
              placeholder="Rule name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Type</label>
            <select
              value={newRuleType}
              onChange={(e) => setNewRuleType(e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="cost_based">Cost Based</option>
              <option value="latency_based">Latency Based</option>
              <option value="quality_based">Quality Based</option>
              <option value="capability_based">Capability Based</option>
              <option value="custom">Custom</option>
              <option value="ml_optimized">ML Optimized</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea
              value={newRuleDescription}
              onChange={(e) => setNewRuleDescription(e.target.value)}
              placeholder="Optional description"
              rows={3}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
        </div>
      </Modal>
    </>
  );
};

const ModelRouterPage: React.FC = () => {
  return (
    <PageContainer
      title="Model Router"
      description="Intelligent AI request routing, cost optimization, and provider selection"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Model Router' }
      ]}
    >
      <ModelRouterContent />
    </PageContainer>
  );
};

export default ModelRouterPage;
