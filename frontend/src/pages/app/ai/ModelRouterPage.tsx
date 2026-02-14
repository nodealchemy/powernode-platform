// Model Router Page - Intelligent AI Request Routing
import React, { useState, useEffect } from 'react';
import { Route, BarChart3, Zap, Trash2, TrendingUp } from 'lucide-react';
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
import {
  RulesTab,
  DecisionsTab,
  AnalyticsTab,
  OptimizationTab,
} from '@/features/ai/model-router/components/router-page';

// Type guard for API errors
interface ApiErrorResponse {
  response?: { data?: { error?: string } };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) return error.response?.data?.error || fallback;
  if (error instanceof Error) return error.message;
  return fallback;
}

type TabType = 'rules' | 'decisions' | 'analytics' | 'optimization';

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

  usePageWebSocket({ pageType: 'ai', onDataUpdate: () => { loadData(); } });

  useEffect(() => { loadData(); }, []);

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
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to load model router data') }));
    } finally {
      setLoading(false);
    }
  };

  const handleToggleRule = async (ruleId: string) => {
    try {
      const updated = await modelRouterApi.toggleRule(ruleId);
      setRules(rules.map(r => r.id === ruleId ? updated : r));
      dispatch(addNotification({ type: 'success', message: `Rule ${updated.is_active ? 'enabled' : 'disabled'}` }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to toggle rule') }));
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
      dispatch(addNotification({ type: 'success', message: `Found ${result.opportunities_found} opportunities, created ${result.new_optimizations_created} new optimizations` }));
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
    if (expandedRuleId === ruleId) { setExpandedRuleId(null); return; }
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
                activeTab === tab.id ? 'border-theme-accent text-theme-accent' : 'border-transparent text-theme-secondary hover:text-theme-primary'
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
          {activeTab === 'rules' && (
            <RulesTab
              rules={rules}
              expandedRuleId={expandedRuleId}
              expandedRuleDetails={expandedRuleDetails}
              loadingExpandId={loadingExpandId}
              onExpandRule={handleExpandRule}
              onToggleRule={handleToggleRule}
              onDeleteClick={setDeleteConfirmId}
              onCreateClick={() => setShowCreateModal(true)}
              getRuleTypeColor={getRuleTypeColor}
            />
          )}
          {activeTab === 'decisions' && <DecisionsTab decisions={decisions} getDecisionColor={getDecisionColor} />}
          {activeTab === 'analytics' && <AnalyticsTab costAnalysis={costAnalysis} rankings={rankings} recommendations={recommendations} />}
          {activeTab === 'optimization' && (
            <OptimizationTab
              optimizations={optimizations}
              optimizationStats={optimizationStats}
              onIdentifyOptimizations={handleIdentifyOptimizations}
              onApplyOptimization={handleApplyOptimization}
            />
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
            <button onClick={() => deleteConfirmId && handleDeleteRule(deleteConfirmId)} className="inline-flex items-center gap-2 px-4 py-2 rounded-md bg-theme-danger text-white hover:bg-theme-danger/90 transition-colors text-sm font-medium">
              <Trash2 size={14} /> Delete Rule
            </button>
          </div>
        }
      >
        <div className="p-4">
          <p className="text-sm text-theme-primary">Are you sure you want to delete <span className="font-semibold">{ruleToDelete?.name}</span>?</p>
          <p className="text-sm text-theme-secondary mt-2">This action cannot be undone. Any routing decisions referencing this rule will lose their rule association.</p>
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
            <input type="text" value={newRuleName} onChange={(e) => setNewRuleName(e.target.value)} placeholder="Rule name" className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Type</label>
            <select value={newRuleType} onChange={(e) => setNewRuleType(e.target.value)} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent">
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
            <textarea value={newRuleDescription} onChange={(e) => setNewRuleDescription(e.target.value)} placeholder="Optional description" rows={3} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
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
