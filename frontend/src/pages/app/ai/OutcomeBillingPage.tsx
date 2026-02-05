// Outcome Billing Page - Success-Based AI Billing
import React, { useState, useEffect } from 'react';
import {
  Plus, DollarSign, FileText, Shield, BarChart3, AlertTriangle,
  Check, X, Play, Pause, TrendingUp
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import {
  outcomeBillingApi,
  OutcomeDefinition,
  SlaContract,
  OutcomeBillingRecord,
  SlaViolation,
  BillingSummary,
  SlaPerformance
} from '@/shared/services/ai/OutcomeBillingApiService';

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

type TabType = 'definitions' | 'contracts' | 'records' | 'violations' | 'performance' | 'summary';

const OutcomeBillingPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('definitions');
  const [definitions, setDefinitions] = useState<OutcomeDefinition[]>([]);
  const [contracts, setContracts] = useState<SlaContract[]>([]);
  const [records, setRecords] = useState<OutcomeBillingRecord[]>([]);
  const [violations, setViolations] = useState<SlaViolation[]>([]);
  const [summary, setSummary] = useState<BillingSummary | null>(null);
  const [slaPerformance, setSlaPerformance] = useState<SlaPerformance | null>(null);
  const [loading, setLoading] = useState(true);

  // Filters
  const [selectedRecordIds, setSelectedRecordIds] = useState<string[]>([]);

  // Create definition modal
  const [showCreateDefModal, setShowCreateDefModal] = useState(false);
  const [newDefName, setNewDefName] = useState('');
  const [newDefType, setNewDefType] = useState('ai_completion');
  const [newDefBasePrice, setNewDefBasePrice] = useState('0.01');
  const [newDefDescription, setNewDefDescription] = useState('');

  // Create contract modal
  const [showCreateContractModal, setShowCreateContractModal] = useState(false);
  const [newContractName, setNewContractName] = useState('');
  const [newContractSuccessTarget, setNewContractSuccessTarget] = useState('95');
  const [newContractBreachCredit, setNewContractBreachCredit] = useState('10');

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
      const [defsRes, contractsRes, recordsRes, violationsRes, summaryRes, perfRes] = await Promise.all([
        outcomeBillingApi.listDefinitions(),
        outcomeBillingApi.listContracts(),
        outcomeBillingApi.listRecords(),
        outcomeBillingApi.listViolations(),
        outcomeBillingApi.getBillingSummary(),
        outcomeBillingApi.getSlaPerformance()
      ]);
      setDefinitions(defsRes.definitions || []);
      setContracts(contractsRes.contracts || []);
      setRecords(recordsRes.records || []);
      setViolations(violationsRes.violations || []);
      setSummary(summaryRes);
      setSlaPerformance(perfRes);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load billing data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleCreateDefinition = async () => {
    if (!newDefName.trim()) return;
    try {
      const def = await outcomeBillingApi.createDefinition({
        name: newDefName,
        outcome_type: newDefType,
        base_price_usd: parseFloat(newDefBasePrice) || 0.01,
        description: newDefDescription || undefined
      });
      dispatch(addNotification({ type: 'success', message: 'Outcome definition created' }));
      setDefinitions([...definitions, def]);
      setShowCreateDefModal(false);
      setNewDefName('');
      setNewDefDescription('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create definition') }));
    }
  };

  const handleCreateContract = async () => {
    if (!newContractName.trim()) return;
    try {
      const contract = await outcomeBillingApi.createContract({
        name: newContractName,
        success_rate_target: parseFloat(newContractSuccessTarget) / 100,
        breach_credit_percentage: parseFloat(newContractBreachCredit)
      });
      dispatch(addNotification({ type: 'success', message: 'SLA contract created' }));
      setContracts([...contracts, contract]);
      setShowCreateContractModal(false);
      setNewContractName('');
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create contract') }));
    }
  };

  const handleContractAction = async (contractId: string, action: 'activate' | 'suspend' | 'cancel') => {
    try {
      let updated: SlaContract;
      switch (action) {
        case 'activate':
          updated = await outcomeBillingApi.activateContract(contractId);
          break;
        case 'suspend':
          updated = await outcomeBillingApi.suspendContract(contractId, 'Suspended by user');
          break;
        case 'cancel':
          updated = await outcomeBillingApi.cancelContract(contractId);
          break;
      }
      setContracts(contracts.map(c => c.id === contractId ? updated : c));
      dispatch(addNotification({ type: 'success', message: `Contract ${action}d` }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, `Failed to ${action} contract`) }));
    }
  };

  const handleViolationAction = async (violationId: string, action: 'approve' | 'apply' | 'reject') => {
    try {
      let updated: SlaViolation;
      switch (action) {
        case 'approve':
          updated = await outcomeBillingApi.approveViolation(violationId);
          break;
        case 'apply':
          updated = await outcomeBillingApi.applyViolationCredit(violationId);
          break;
        case 'reject':
          updated = await outcomeBillingApi.rejectViolation(violationId);
          break;
      }
      setViolations(violations.map(v => v.id === violationId ? updated : v));
      dispatch(addNotification({ type: 'success', message: `Violation ${action === 'apply' ? 'credit applied' : action + 'd'}` }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, `Failed to ${action} violation`) }));
    }
  };

  const handleMarkBilled = async () => {
    if (selectedRecordIds.length === 0) return;
    try {
      const result = await outcomeBillingApi.markAsBilled(selectedRecordIds);
      dispatch(addNotification({ type: 'success', message: `${result.updated_count} records marked as billed` }));
      setSelectedRecordIds([]);
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to mark records as billed') }));
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'active': case 'successful': case 'completed': case 'approved': case 'applied': return 'text-theme-success bg-theme-success/10';
      case 'pending': case 'draft': case 'pending_approval': case 'processing': return 'text-theme-warning bg-theme-warning/10';
      case 'failed': case 'cancelled': case 'rejected': case 'expired': case 'timeout': return 'text-theme-danger bg-theme-danger/10';
      case 'suspended': case 'waived': return 'text-theme-secondary bg-theme-surface';
      case 'refunded': return 'text-theme-info bg-theme-info/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const getSeverityColor = (severity: string): string => {
    switch (severity) {
      case 'critical': return 'text-theme-danger bg-theme-danger/10';
      case 'major': return 'text-theme-warning bg-theme-warning/10';
      case 'minor': return 'text-theme-info bg-theme-info/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadData,
    loading,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Outcome Billing' }
  ];

  const tabs = [
    { id: 'definitions' as TabType, label: 'Definitions', icon: FileText },
    { id: 'contracts' as TabType, label: 'Contracts', icon: Shield },
    { id: 'records' as TabType, label: 'Records', icon: DollarSign },
    { id: 'violations' as TabType, label: 'Violations', icon: AlertTriangle },
    { id: 'performance' as TabType, label: 'Performance', icon: BarChart3 },
    { id: 'summary' as TabType, label: 'Summary', icon: TrendingUp }
  ];

  return (
    <PageContainer
      title="Outcome Billing"
      description="Success-based AI billing, SLA contracts, and violation management"
      breadcrumbs={breadcrumbs}
      actions={[
        refreshAction,
        {
          id: 'create-definition',
          label: 'Create Definition',
          onClick: () => setShowCreateDefModal(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Outcomes</p>
                <p className="text-2xl font-bold text-theme-primary">{summary.total_outcomes}</p>
              </div>
              <DollarSign className="h-8 w-8 text-theme-accent" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">
              <span className="text-theme-success">{summary.successful_outcomes} successful</span>
              {summary.failed_outcomes > 0 && (
                <span className="text-theme-danger ml-2">{summary.failed_outcomes} failed</span>
              )}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Success Rate</p>
                <p className="text-2xl font-bold text-theme-primary">{(summary.success_rate * 100).toFixed(1)}%</p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-success" />
            </div>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Revenue</p>
                <p className="text-2xl font-bold text-theme-primary">${summary.total_revenue.toFixed(2)}</p>
              </div>
              <DollarSign className="h-8 w-8 text-theme-success" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">${summary.pending_revenue.toFixed(2)} pending</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Avg Quality</p>
                <p className="text-2xl font-bold text-theme-primary">{(summary.average_quality_score * 100).toFixed(0)}%</p>
              </div>
              <BarChart3 className="h-8 w-8 text-theme-info" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">Avg {(summary.average_duration_ms / 1000).toFixed(1)}s duration</p>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4 overflow-x-auto">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors whitespace-nowrap ${
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
          <p className="mt-4 text-theme-secondary">Loading billing data...</p>
        </div>
      ) : (
        <>
          {/* Definitions Tab */}
          {activeTab === 'definitions' && (
            <div className="space-y-4">
              {definitions.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <FileText size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No outcome definitions</h3>
                  <p className="text-theme-secondary mb-6">Create outcome definitions to start tracking billable AI outcomes</p>
                  <button onClick={() => setShowCreateDefModal(true)} className="btn-theme btn-theme-primary">
                    Create Definition
                  </button>
                </div>
              ) : (
                definitions.map(def => (
                  <div key={def.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{def.name}</h3>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{def.outcome_type}</span>
                        <span className={`px-2 py-1 text-xs rounded ${def.is_active ? 'text-theme-success bg-theme-success/10' : 'text-theme-secondary bg-theme-surface'}`}>
                          {def.is_active ? 'Active' : 'Inactive'}
                        </span>
                        {def.is_system && (
                          <span className="px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">System</span>
                        )}
                      </div>
                    </div>
                    {def.description && <p className="text-sm text-theme-secondary mb-2">{def.description}</p>}
                    <div className="flex flex-wrap gap-4 text-xs text-theme-secondary">
                      <span>Base: ${def.pricing.base_price_usd.toFixed(4)}</span>
                      {def.pricing.price_per_token && <span>Per token: ${def.pricing.price_per_token.toFixed(6)}</span>}
                      {def.pricing.price_per_minute && <span>Per minute: ${def.pricing.price_per_minute.toFixed(4)}</span>}
                      {def.pricing.max_charge_usd && <span>Max: ${def.pricing.max_charge_usd.toFixed(2)}</span>}
                      {def.free_tier_count > 0 && <span className="text-theme-info">{def.free_tier_count} free tier</span>}
                      {def.sla.enabled && (
                        <span className="text-theme-warning">
                          SLA: {(def.sla.target_percentage || 0) * 100}% target, {def.sla.credit_percentage || 0}% credit
                        </span>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Contracts Tab */}
          {activeTab === 'contracts' && (
            <div className="space-y-4">
              <div className="flex justify-end">
                <button onClick={() => setShowCreateContractModal(true)} className="btn-theme btn-theme-secondary btn-theme-sm">
                  <Plus size={14} className="mr-1 inline" /> Create Contract
                </button>
              </div>
              {contracts.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Shield size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No SLA contracts</h3>
                  <p className="text-theme-secondary mb-6">Create SLA contracts to define service level agreements</p>
                  <button onClick={() => setShowCreateContractModal(true)} className="btn-theme btn-theme-primary">
                    Create Contract
                  </button>
                </div>
              ) : (
                contracts.map(contract => (
                  <div key={contract.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{contract.name}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(contract.status)}`}>{contract.status}</span>
                        {contract.contract_type && (
                          <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{contract.contract_type}</span>
                        )}
                      </div>
                      <div className="flex items-center gap-2">
                        {contract.status === 'draft' && (
                          <button
                            onClick={() => handleContractAction(contract.id, 'activate')}
                            className="btn-theme btn-theme-success btn-theme-sm"
                          >
                            <Play size={14} className="mr-1" /> Activate
                          </button>
                        )}
                        {contract.status === 'active' && (
                          <button
                            onClick={() => handleContractAction(contract.id, 'suspend')}
                            className="btn-theme btn-theme-warning btn-theme-sm"
                          >
                            <Pause size={14} className="mr-1" /> Suspend
                          </button>
                        )}
                        {['draft', 'active', 'suspended'].includes(contract.status) && (
                          <button
                            onClick={() => handleContractAction(contract.id, 'cancel')}
                            className="btn-theme btn-theme-danger btn-theme-sm"
                          >
                            <X size={14} className="mr-1" /> Cancel
                          </button>
                        )}
                      </div>
                    </div>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-3">
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Success Target</p>
                        <p className="text-sm font-medium text-theme-primary">{(contract.targets.success_rate * 100).toFixed(1)}%</p>
                      </div>
                      {contract.targets.latency_p95_ms && (
                        <div className="p-2 bg-theme-bg rounded">
                          <p className="text-xs text-theme-secondary">Latency P95</p>
                          <p className="text-sm font-medium text-theme-primary">{contract.targets.latency_p95_ms}ms</p>
                        </div>
                      )}
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Breach Credit</p>
                        <p className="text-sm font-medium text-theme-primary">{contract.pricing.breach_credit_percentage}%</p>
                      </div>
                      {contract.current_period.success_rate !== null && (
                        <div className="p-2 bg-theme-bg rounded">
                          <p className="text-xs text-theme-secondary">Current Rate</p>
                          <p className={`text-sm font-medium ${
                            contract.current_period.breached ? 'text-theme-danger' : 'text-theme-success'
                          }`}>
                            {(contract.current_period.success_rate * 100).toFixed(1)}%
                          </p>
                        </div>
                      )}
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary mt-3">
                      <span>Period: {contract.current_period.total} outcomes ({contract.current_period.successful} successful)</span>
                      <span>Window: {contract.measurement_window_hours}h</span>
                      {contract.current_period.breached && (
                        <span className="text-theme-danger font-medium">SLA BREACHED</span>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Records Tab */}
          {activeTab === 'records' && (
            <div className="space-y-4">
              {/* Actions */}
              {selectedRecordIds.length > 0 && (
                <div className="flex items-center gap-4 p-3 bg-theme-accent/10 rounded-lg">
                  <span className="text-sm text-theme-accent">{selectedRecordIds.length} selected</span>
                  <button onClick={handleMarkBilled} className="btn-theme btn-theme-primary btn-theme-sm">
                    Mark as Billed
                  </button>
                  <button onClick={() => setSelectedRecordIds([])} className="btn-theme btn-theme-secondary btn-theme-sm">
                    Clear Selection
                  </button>
                </div>
              )}

              {records.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <DollarSign size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No billing records</h3>
                  <p className="text-theme-secondary">Billing records will appear as outcomes are tracked</p>
                </div>
              ) : (
                <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-theme bg-theme-bg">
                        <th className="px-4 py-3 text-left">
                          <input
                            type="checkbox"
                            checked={selectedRecordIds.length === records.filter(r => !r.is_billed).length && records.filter(r => !r.is_billed).length > 0}
                            onChange={(e) => {
                              if (e.target.checked) {
                                setSelectedRecordIds(records.filter(r => !r.is_billed).map(r => r.id));
                              } else {
                                setSelectedRecordIds([]);
                              }
                            }}
                            className="rounded border-theme"
                          />
                        </th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Outcome</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Status</th>
                        <th className="px-4 py-3 text-right text-xs font-medium text-theme-secondary uppercase">Charge</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Source</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Billed</th>
                        <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-theme">
                      {records.map(record => (
                        <tr key={record.id} className="hover:bg-theme-surface-hover transition-colors">
                          <td className="px-4 py-3">
                            {!record.is_billed && (
                              <input
                                type="checkbox"
                                checked={selectedRecordIds.includes(record.id)}
                                onChange={(e) => {
                                  if (e.target.checked) {
                                    setSelectedRecordIds([...selectedRecordIds, record.id]);
                                  } else {
                                    setSelectedRecordIds(selectedRecordIds.filter(id => id !== record.id));
                                  }
                                }}
                                className="rounded border-theme"
                              />
                            )}
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-primary">{record.outcome_name}</td>
                          <td className="px-4 py-3">
                            <span className={`px-2 py-1 text-xs rounded ${getStatusColor(record.status)}`}>{record.status}</span>
                          </td>
                          <td className="px-4 py-3 text-sm text-right font-medium text-theme-primary">
                            {record.charges.final_usd != null ? `$${record.charges.final_usd.toFixed(4)}` : '-'}
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-secondary">{record.source_name || record.source_type}</td>
                          <td className="px-4 py-3">
                            {record.is_billed ? (
                              <span className="text-theme-success text-xs">Billed</span>
                            ) : record.is_billable ? (
                              <span className="text-theme-warning text-xs">Pending</span>
                            ) : (
                              <span className="text-theme-secondary text-xs">N/A</span>
                            )}
                          </td>
                          <td className="px-4 py-3 text-sm text-theme-secondary">
                            {new Date(record.created_at).toLocaleString()}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {/* Violations Tab */}
          {activeTab === 'violations' && (
            <div className="space-y-4">
              {violations.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <AlertTriangle size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No SLA violations</h3>
                  <p className="text-theme-secondary">All SLA targets are being met</p>
                </div>
              ) : (
                violations.map(violation => (
                  <div key={violation.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{violation.contract_name}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getSeverityColor(violation.severity)}`}>
                          {violation.severity}
                        </span>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                          {violation.violation_type}
                        </span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(violation.credit.status)}`}>
                          {violation.credit.status}
                        </span>
                      </div>
                      <div className="flex items-center gap-2">
                        {violation.credit.status === 'pending' && (
                          <>
                            <button
                              onClick={() => handleViolationAction(violation.id, 'approve')}
                              className="btn-theme btn-theme-success btn-theme-sm"
                            >
                              <Check size={14} className="mr-1" /> Approve
                            </button>
                            <button
                              onClick={() => handleViolationAction(violation.id, 'reject')}
                              className="btn-theme btn-theme-danger btn-theme-sm"
                            >
                              <X size={14} className="mr-1" /> Reject
                            </button>
                          </>
                        )}
                        {violation.credit.status === 'approved' && (
                          <button
                            onClick={() => handleViolationAction(violation.id, 'apply')}
                            className="btn-theme btn-theme-primary btn-theme-sm"
                          >
                            Apply Credit
                          </button>
                        )}
                      </div>
                    </div>
                    {violation.description && <p className="text-sm text-theme-secondary mb-2">{violation.description}</p>}
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-3">
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Target</p>
                        <p className="text-sm font-medium text-theme-primary">{(violation.metrics.target * 100).toFixed(1)}%</p>
                      </div>
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Actual</p>
                        <p className="text-sm font-medium text-theme-danger">{(violation.metrics.actual * 100).toFixed(1)}%</p>
                      </div>
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Affected</p>
                        <p className="text-sm font-medium text-theme-primary">{violation.metrics.affected_outcomes} outcomes</p>
                      </div>
                      <div className="p-2 bg-theme-bg rounded">
                        <p className="text-xs text-theme-secondary">Credit</p>
                        <p className="text-sm font-medium text-theme-warning">${violation.credit.amount_usd.toFixed(2)}</p>
                      </div>
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary mt-3">
                      <span>Period: {new Date(violation.period.start).toLocaleDateString()} - {new Date(violation.period.end).toLocaleDateString()}</span>
                      <span>Created: {new Date(violation.created_at).toLocaleString()}</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Performance Tab */}
          {activeTab === 'performance' && (
            <div className="space-y-4">
              {!slaPerformance ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No performance data</h3>
                  <p className="text-theme-secondary">Performance data will appear once SLA contracts are active</p>
                </div>
              ) : (
                <>
                  <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                    <div className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">Active Contracts</p>
                      <p className="text-2xl font-bold text-theme-primary">{slaPerformance.active_contracts}</p>
                    </div>
                    <div className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">Total Violations</p>
                      <p className="text-2xl font-bold text-theme-danger">{slaPerformance.total_violations}</p>
                    </div>
                    <div className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">Credits Applied</p>
                      <p className="text-2xl font-bold text-theme-warning">${slaPerformance.total_credits_applied.toFixed(2)}</p>
                    </div>
                    <div className="bg-theme-surface border border-theme rounded-lg p-4">
                      <p className="text-sm text-theme-secondary">Contracts Meeting SLA</p>
                      <p className="text-2xl font-bold text-theme-success">
                        {slaPerformance.contracts_summary.filter(c => c.is_meeting_sla).length}/{slaPerformance.contracts_summary.length}
                      </p>
                    </div>
                  </div>

                  {slaPerformance.contracts_summary.length > 0 && (
                    <div className="bg-theme-surface border border-theme rounded-lg p-6">
                      <h3 className="text-lg font-semibold text-theme-primary mb-4">Contract Performance</h3>
                      <div className="space-y-4">
                        {slaPerformance.contracts_summary.map(contract => (
                          <div key={contract.id} className="p-4 bg-theme-bg rounded-lg">
                            <div className="flex items-center justify-between mb-2">
                              <div className="flex items-center gap-3">
                                <h4 className="font-medium text-theme-primary">{contract.name}</h4>
                                <span className={`px-2 py-1 text-xs rounded ${
                                  contract.is_meeting_sla ? 'text-theme-success bg-theme-success/10' : 'text-theme-danger bg-theme-danger/10'
                                }`}>
                                  {contract.is_meeting_sla ? 'Meeting SLA' : 'Below Target'}
                                </span>
                              </div>
                              <div className="text-sm text-theme-secondary">
                                {contract.violations_count} violations | ${contract.credits_applied.toFixed(2)} credits
                              </div>
                            </div>
                            <div className="flex items-center gap-4">
                              <div className="flex-1">
                                <div className="flex justify-between text-xs text-theme-secondary mb-1">
                                  <span>Current: {contract.current_success_rate !== null ? `${(contract.current_success_rate * 100).toFixed(1)}%` : 'N/A'}</span>
                                  <span>Target: {(contract.success_rate_target * 100).toFixed(1)}%</span>
                                </div>
                                <div className="w-full bg-theme-surface rounded-full h-2">
                                  <div
                                    className={`rounded-full h-2 transition-all ${
                                      contract.is_meeting_sla ? 'bg-theme-success' : 'bg-theme-danger'
                                    }`}
                                    style={{ width: `${Math.min(100, ((contract.current_success_rate || 0) / contract.success_rate_target) * 100)}%` }}
                                  />
                                </div>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {/* Summary Tab */}
          {activeTab === 'summary' && (
            <div className="space-y-4">
              {!summary ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <TrendingUp size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No billing summary</h3>
                  <p className="text-theme-secondary">Billing summary will appear once outcomes are tracked</p>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="bg-theme-surface border border-theme rounded-lg p-6">
                    <h3 className="text-lg font-semibold text-theme-primary mb-4">Billing Overview</h3>
                    <div className="space-y-3">
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Period</span>
                        <span className="text-sm font-medium text-theme-primary">{summary.period_days} days</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Total Outcomes</span>
                        <span className="text-sm font-medium text-theme-primary">{summary.total_outcomes}</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Successful</span>
                        <span className="text-sm font-medium text-theme-success">{summary.successful_outcomes}</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Failed</span>
                        <span className="text-sm font-medium text-theme-danger">{summary.failed_outcomes}</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Success Rate</span>
                        <span className="text-sm font-medium text-theme-primary">{(summary.success_rate * 100).toFixed(1)}%</span>
                      </div>
                    </div>
                  </div>
                  <div className="bg-theme-surface border border-theme rounded-lg p-6">
                    <h3 className="text-lg font-semibold text-theme-primary mb-4">Revenue & Performance</h3>
                    <div className="space-y-3">
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Total Revenue</span>
                        <span className="text-sm font-medium text-theme-success">${summary.total_revenue.toFixed(2)}</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Pending Revenue</span>
                        <span className="text-sm font-medium text-theme-warning">${summary.pending_revenue.toFixed(2)}</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Avg Duration</span>
                        <span className="text-sm font-medium text-theme-primary">{(summary.average_duration_ms / 1000).toFixed(1)}s</span>
                      </div>
                      <div className="flex justify-between p-3 bg-theme-bg rounded-lg">
                        <span className="text-sm text-theme-secondary">Avg Quality Score</span>
                        <span className="text-sm font-medium text-theme-primary">{(summary.average_quality_score * 100).toFixed(0)}%</span>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </>
      )}

      {/* Create Definition Modal */}
      <Modal
        isOpen={showCreateDefModal}
        onClose={() => setShowCreateDefModal(false)}
        title="Create Outcome Definition"
        maxWidth="md"
        icon={<FileText />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowCreateDefModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateDefinition} disabled={!newDefName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input
              type="text"
              value={newDefName}
              onChange={(e) => setNewDefName(e.target.value)}
              placeholder="Outcome definition name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Outcome Type</label>
            <select
              value={newDefType}
              onChange={(e) => setNewDefType(e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            >
              <option value="ai_completion">AI Completion</option>
              <option value="code_generation">Code Generation</option>
              <option value="data_analysis">Data Analysis</option>
              <option value="document_processing">Document Processing</option>
              <option value="image_generation">Image Generation</option>
              <option value="custom">Custom</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Base Price (USD)</label>
            <input
              type="number"
              value={newDefBasePrice}
              onChange={(e) => setNewDefBasePrice(e.target.value)}
              step="0.01"
              min="0"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea
              value={newDefDescription}
              onChange={(e) => setNewDefDescription(e.target.value)}
              placeholder="Optional description"
              rows={3}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
        </div>
      </Modal>

      {/* Create Contract Modal */}
      <Modal
        isOpen={showCreateContractModal}
        onClose={() => setShowCreateContractModal(false)}
        title="Create SLA Contract"
        maxWidth="md"
        icon={<Shield />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowCreateContractModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateContract} disabled={!newContractName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Contract Name</label>
            <input
              type="text"
              value={newContractName}
              onChange={(e) => setNewContractName(e.target.value)}
              placeholder="SLA contract name"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Success Rate Target (%)</label>
            <input
              type="number"
              value={newContractSuccessTarget}
              onChange={(e) => setNewContractSuccessTarget(e.target.value)}
              step="0.1"
              min="0"
              max="100"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Breach Credit (%)</label>
            <input
              type="number"
              value={newContractBreachCredit}
              onChange={(e) => setNewContractBreachCredit(e.target.value)}
              step="1"
              min="0"
              max="100"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
            />
          </div>
        </div>
      </Modal>
    </PageContainer>
  );
};

export default OutcomeBillingPage;
