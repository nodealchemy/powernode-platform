import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import type { PageAction, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { useCodeFactory } from '../hooks/useCodeFactory';
import { ContractList } from '../components/ContractList';
import { ContractEditor } from '../components/ContractEditor';
import { RunList } from '../components/RunList';
import { HarnessGapTracker } from '../components/HarnessGapTracker';
import { EvidenceViewer } from '../components/EvidenceViewer';
import { CodeFactoryStatsCards } from '../components/CodeFactoryStatsCards';
import type { RiskContract } from '../types/codeFactory';

const TABS = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'contracts', label: 'Contracts' },
  { id: 'runs', label: 'Runs' },
  { id: 'harness-gaps', label: 'Harness Gaps' },
  { id: 'evidence', label: 'Evidence' },
] as const;

type TabId = typeof TABS[number]['id'];

const TAB_SEGMENTS: Record<TabId, string> = {
  dashboard: '',
  contracts: 'contracts',
  runs: 'runs',
  'harness-gaps': 'harness-gaps',
  evidence: 'evidence',
};

export const CodeFactoryContent: React.FC<{
  basePath?: string;
  onActionsReady?: (actions: PageAction[]) => void;
}> = ({ basePath = '/app/ai/code-factory', onActionsReady }) => {
  const location = useLocation();
  const navigate = useNavigate();

  const getActiveTabFromPath = useCallback((pathname: string): TabId => {
    const suffix = pathname.startsWith(basePath) ? pathname.slice(basePath.length) : '';
    const segment = suffix.split('/').filter(Boolean)[0] || '';
    const match = (Object.entries(TAB_SEGMENTS) as [TabId, string][]).find(
      ([, seg]) => seg !== '' && seg === segment
    );
    return match ? match[0] : 'dashboard';
  }, [basePath]);

  const [activeTab, setActiveTab] = useState<TabId>(() => getActiveTabFromPath(location.pathname));
  const [editingContract, setEditingContract] = useState<RiskContract | null>(null);
  const [showEditor, setShowEditor] = useState(false);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);

  const {
    contracts,
    reviewStates,
    harnessGaps,
    gapMetrics,
    slaCompliance,
    loading,
    hasReadPermission,
    hasManagePermission,
    fetchContracts,
    fetchReviewStates,
    fetchHarnessGaps,
    createContract,
    updateContract,
    activateContract,
    addTestCase,
    closeHarnessGap,
  } = useCodeFactory();

  useEffect(() => {
    const newTab = getActiveTabFromPath(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname, getActiveTabFromPath]);

  useEffect(() => {
    if (hasReadPermission) {
      fetchContracts();
      fetchReviewStates();
      fetchHarnessGaps();
    }
  }, [hasReadPermission, fetchContracts, fetchReviewStates, fetchHarnessGaps]);

  const handleRefresh = useCallback(() => {
    fetchContracts();
    fetchReviewStates();
    fetchHarnessGaps();
  }, [fetchContracts, fetchReviewStates, fetchHarnessGaps]);

  const handleCreateContract = () => {
    setEditingContract(null);
    setShowEditor(true);
  };

  const handleSaveContract = async (data: Partial<RiskContract>) => {
    if (editingContract) {
      await updateContract(editingContract.id, data);
    } else {
      await createContract(data);
    }
    setShowEditor(false);
    setEditingContract(null);
  };

  const handleNavigateToContract = (contractId: string) => {
    navigate(`${basePath}/contracts`);
    void contractId;
  };

  const handleSelectRun = (runId: string) => {
    setSelectedRunId(runId);
    navigate(`${basePath}/runs`);
  };

  const navigateTab = (tab: string) => {
    setSelectedRunId(null);
    const segment = TAB_SEGMENTS[tab as TabId] || '';
    const path = segment ? `${basePath}/${segment}` : basePath;
    navigate(path);
  };

  // Bubble up actions to parent
  const actions = useMemo<PageAction[]>(() => {
    const items: PageAction[] = [
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: handleRefresh,
        variant: 'secondary',
        icon: RefreshCw,
        disabled: loading,
      },
    ];
    if (hasManagePermission) {
      items.push({
        id: 'create-contract',
        label: 'New Contract',
        onClick: handleCreateContract,
        variant: 'primary',
      });
    }
    return items;
  }, [handleRefresh, loading, hasManagePermission]);

  useEffect(() => {
    if (onActionsReady) onActionsReady(actions);
  }, [actions, onActionsReady]);

  if (!hasReadPermission) {
    return (
      <div className="text-center py-12 text-theme-secondary">
        You do not have permission to view Code Factory.
      </div>
    );
  }

  return (
    <>
      <div className="space-y-6">
        {/* Tab Navigation */}
        <div className="flex space-x-1 border-b border-theme-border">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => navigateTab(tab.id)}
              className={`px-4 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'text-theme-accent border-b-2 border-theme-accent'
                  : 'text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Tab Content */}
        {activeTab === 'dashboard' && (
          <div className="space-y-6">
            <CodeFactoryStatsCards
              contracts={contracts}
              reviewStates={reviewStates}
              harnessGaps={harnessGaps}
              gapMetrics={gapMetrics}
              slaCompliance={slaCompliance}
              onNavigateTab={navigateTab}
            />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div className="card-theme p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-theme-primary">Active Contracts</h3>
                  <button
                    onClick={() => navigateTab('contracts')}
                    className="text-xs text-theme-accent hover:underline"
                  >
                    View All
                  </button>
                </div>
                <ContractList
                  contracts={contracts.filter(c => c.status === 'active').slice(0, 5)}
                  compact
                  onNavigateToContract={handleNavigateToContract}
                />
              </div>
              <div className="card-theme p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-theme-primary">Recent Runs</h3>
                  <button
                    onClick={() => navigateTab('runs')}
                    className="text-xs text-theme-accent hover:underline"
                  >
                    View All
                  </button>
                </div>
                <RunList
                  reviewStates={reviewStates.slice(0, 5)}
                  compact
                  onNavigateToContract={handleNavigateToContract}
                  onSelectRun={handleSelectRun}
                />
              </div>
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div className="card-theme p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-theme-primary">Harness Gaps</h3>
                  <button
                    onClick={() => navigateTab('harness-gaps')}
                    className="text-xs text-theme-accent hover:underline"
                  >
                    View All
                  </button>
                </div>
                {harnessGaps.filter(g => g.status === 'open' || g.status === 'in_progress').length === 0 ? (
                  <div className="text-xs text-theme-success text-center py-4">No open gaps</div>
                ) : (
                  <div className="space-y-2">
                    {harnessGaps
                      .filter(g => g.status === 'open' || g.status === 'in_progress')
                      .slice(0, 5)
                      .map((gap) => (
                        <div key={gap.id} className="flex items-center gap-2 bg-theme-secondary-bg rounded-lg px-3 py-2">
                          <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${
                            gap.severity === 'critical' ? 'bg-theme-danger/20 text-theme-danger'
                              : gap.severity === 'high' ? 'bg-theme-error-bg text-theme-error'
                              : gap.severity === 'medium' ? 'bg-theme-warning-bg text-theme-warning'
                              : 'bg-theme-secondary-bg text-theme-secondary'
                          }`}>
                            {gap.severity}
                          </span>
                          <span className="text-xs font-mono text-theme-primary">{gap.incident_id}</span>
                          <span className="text-xs text-theme-secondary truncate flex-1">{gap.description}</span>
                          {gap.test_case_added && (
                            <span className="text-[10px] text-theme-success flex-shrink-0">{'\u2713'} Test</span>
                          )}
                        </div>
                      ))}
                    {harnessGaps.filter(g => g.status === 'open' || g.status === 'in_progress').length > 5 && (
                      <div className="text-[10px] text-theme-secondary text-center">
                        +{harnessGaps.filter(g => g.status === 'open' || g.status === 'in_progress').length - 5} more
                      </div>
                    )}
                  </div>
                )}
              </div>
              <div className="card-theme p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-theme-primary">Evidence</h3>
                  <button
                    onClick={() => navigateTab('evidence')}
                    className="text-xs text-theme-accent hover:underline"
                  >
                    View All
                  </button>
                </div>
                {(() => {
                  const manifests = reviewStates.flatMap(rs =>
                    (rs.evidence_manifests || []).map(m => ({ ...m, pr_number: rs.pr_number }))
                  );
                  const verified = manifests.filter(m => m.status === 'verified').length;
                  const pending = manifests.filter(m => m.status === 'pending').length;
                  const failed = manifests.filter(m => m.status === 'failed').length;

                  if (manifests.length === 0) {
                    return <div className="text-xs text-theme-secondary text-center py-4">No evidence captured yet</div>;
                  }

                  return (
                    <div className="space-y-3">
                      <div className="grid grid-cols-3 gap-2">
                        <div className="bg-theme-success-bg rounded-lg p-2 text-center">
                          <div className="text-lg font-semibold text-theme-success">{verified}</div>
                          <div className="text-[10px] text-theme-secondary">Verified</div>
                        </div>
                        <div className="bg-theme-secondary-bg rounded-lg p-2 text-center">
                          <div className="text-lg font-semibold text-theme-primary">{pending}</div>
                          <div className="text-[10px] text-theme-secondary">Pending</div>
                        </div>
                        <div className="bg-theme-error-bg rounded-lg p-2 text-center">
                          <div className="text-lg font-semibold text-theme-error">{failed}</div>
                          <div className="text-[10px] text-theme-secondary">Failed</div>
                        </div>
                      </div>
                      <div className="space-y-1.5">
                        {manifests.slice(0, 4).map((m) => (
                          <div key={m.id} className="flex items-center justify-between bg-theme-secondary-bg rounded-lg px-3 py-2">
                            <div className="flex items-center gap-2 min-w-0">
                              <span className="text-xs text-theme-primary capitalize">{m.manifest_type.replace(/_/g, ' ')}</span>
                              <span className="text-xs text-theme-secondary">PR #{m.pr_number}</span>
                            </div>
                            <div className="flex items-center gap-2 flex-shrink-0">
                              <span className="text-[10px] text-theme-secondary">{m.assertions.length} assertions</span>
                              <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-medium ${
                                m.status === 'verified' ? 'bg-theme-success-bg text-theme-success'
                                  : m.status === 'failed' ? 'bg-theme-error-bg text-theme-error'
                                  : 'bg-theme-secondary-bg text-theme-secondary'
                              }`}>
                                {m.status}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  );
                })()}
              </div>
            </div>
          </div>
        )}

        {activeTab === 'contracts' && (
          <ContractList
            contracts={contracts}
            onActivate={activateContract}
            onSave={updateContract}
            loading={loading}
          />
        )}

        {activeTab === 'runs' && (
          <RunList
            reviewStates={reviewStates}
            initialExpandedId={selectedRunId}
            onNavigateToContract={handleNavigateToContract}
          />
        )}

        {activeTab === 'harness-gaps' && (
          <HarnessGapTracker
            gaps={harnessGaps}
            metrics={gapMetrics}
            slaCompliance={slaCompliance}
            onRefresh={() => fetchHarnessGaps()}
            onAddTestCase={hasManagePermission ? addTestCase : undefined}
            onCloseGap={hasManagePermission ? closeHarnessGap : undefined}
            onNavigateToContract={handleNavigateToContract}
          />
        )}

        {activeTab === 'evidence' && (
          <EvidenceViewer reviewStates={reviewStates} />
        )}
      </div>

      {/* Contract Editor Modal */}
      {showEditor && (
        <ContractEditor
          contract={editingContract}
          onSave={handleSaveContract}
          onClose={() => { setShowEditor(false); setEditingContract(null); }}
        />
      )}
    </>
  );
};

export const CodeFactoryPage: React.FC = () => {
  const location = useLocation();
  const [actions, setActions] = useState<PageAction[]>([]);

  const getActiveTabFromPath = (pathname: string): TabId => {
    const segment = pathname.split('/').filter(Boolean).pop() || '';
    const match = (Object.entries(TAB_SEGMENTS) as [TabId, string][]).find(
      ([, seg]) => seg !== '' && seg === segment
    );
    return match ? match[0] : 'dashboard';
  };

  const activeTab = getActiveTabFromPath(location.pathname);

  const breadcrumbs = useMemo<BreadcrumbItem[]>(() => {
    const base: BreadcrumbItem[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    if (activeTab === 'dashboard') {
      base.push({ label: 'Code Factory' });
    } else {
      base.push({ label: 'Code Factory', href: '/app/ai/code-factory' });
      const tab = TABS.find(t => t.id === activeTab);
      if (tab) base.push({ label: tab.label });
    }
    return base;
  }, [activeTab]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="Code Factory"
      description="Automated code review, remediation, and evidence loops"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <CodeFactoryContent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};
