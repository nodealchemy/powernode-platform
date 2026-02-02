import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { RefreshCw, Trash2, Package, AlertTriangle, CheckCircle, XCircle, GitCompare, Shield, Calculator } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { sbomsApi } from '../services/sbomsApi';
import { VulnerabilityActionsMenu } from '../components/sbom/VulnerabilityActionsMenu';
import { RemediationStatusSelect } from '../components/sbom/RemediationStatusSelect';
import { ComplianceStatusCard } from '../components/sbom/ComplianceStatusCard';
import { CreateDiffModal } from '../components/sbom/CreateDiffModal';
import { ExportFormatDropdown } from '../components/sbom/ExportFormatDropdown';
import {
  useSbomCompliance,
  useSbomDiffs,
  useCreateSbomDiff,
  useUpdateVulnerabilityStatus,
  useSuppressVulnerability,
  useMarkFalsePositive,
  useCalculateRisk,
  useCorrelateVulnerabilities,
} from '../hooks/useSboms';

type SbomStatus = 'draft' | 'generating' | 'completed' | 'failed';
type DependencyType = 'direct' | 'transitive' | 'dev';
type Severity = 'critical' | 'high' | 'medium' | 'low';
type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';

interface Sbom {
  id: string;
  sbom_id: string;
  name: string;
  format: string;
  version: string;
  status: SbomStatus;
  component_count: number;
  vulnerability_count: number;
  risk_score: number;
  ntia_minimum_compliant: boolean;
  commit_sha?: string;
  branch?: string;
  repository_id?: string;
  created_at: string;
  updated_at: string;
  repository?: { id: string; name: string; full_name: string };
}

interface SbomComponent {
  id: string;
  purl: string;
  name: string;
  version: string;
  ecosystem: string;
  dependency_type: DependencyType;
  depth: number;
  risk_score: number;
  has_known_vulnerabilities: boolean;
  license_id?: string;
}

interface SbomVulnerability {
  id: string;
  vulnerability_id: string;
  severity: Severity;
  cvss_score: number;
  cvss_vector?: string;
  remediation_status: RemediationStatus;
  fixed_version?: string;
  component: { name: string; version: string };
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

const StatusBadge: React.FC<{ status: SbomStatus }> = ({ status }) => {
  const variants = {
    draft: 'secondary' as const,
    generating: 'warning' as const,
    completed: 'success' as const,
    failed: 'danger' as const,
  };

  return (
    <Badge variant={variants[status]} size="sm">
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </Badge>
  );
};

const SeverityBadge: React.FC<{ severity: Severity }> = ({ severity }) => {
  const variants = {
    critical: 'danger' as const,
    high: 'danger' as const,
    medium: 'warning' as const,
    low: 'info' as const,
  };

  return (
    <Badge variant={variants[severity]} size="sm">
      {severity.charAt(0).toUpperCase() + severity.slice(1)}
    </Badge>
  );
};

const RemediationBadge: React.FC<{ status: RemediationStatus }> = ({ status }) => {
  const variants = {
    open: 'danger' as const,
    in_progress: 'warning' as const,
    fixed: 'success' as const,
    wont_fix: 'secondary' as const,
  };

  const labels = {
    open: 'Open',
    in_progress: 'In Progress',
    fixed: 'Fixed',
    wont_fix: "Won't Fix",
  };

  return (
    <Badge variant={variants[status]} size="sm">
      {labels[status]}
    </Badge>
  );
};

const SbomDetailPageContent: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const [sbom, setSbom] = useState<Sbom | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const [showDiffModal, setShowDiffModal] = useState(false);

  // New hooks for enhanced functionality
  const { compliance, loading: complianceLoading } = useSbomCompliance(id || null);
  const { diffs, refresh: refreshDiffs } = useSbomDiffs(id || null);
  const createDiffMutation = useCreateSbomDiff();
  const updateStatusMutation = useUpdateVulnerabilityStatus();
  const suppressMutation = useSuppressVulnerability();
  const markFalsePositiveMutation = useMarkFalsePositive();
  const calculateRiskMutation = useCalculateRisk();
  const correlateVulnsMutation = useCorrelateVulnerabilities();

  const [components, setComponents] = useState<SbomComponent[]>([]);
  const [componentsPagination, setComponentsPagination] = useState<Pagination | null>(null);
  const [componentsLoading, setComponentsLoading] = useState(false);
  const [componentsPage, setComponentsPage] = useState(1);
  const [ecosystemFilter, setEcosystemFilter] = useState('');

  const [vulnerabilities, setVulnerabilities] = useState<SbomVulnerability[]>([]);
  const [vulnerabilitiesPagination, setVulnerabilitiesPagination] = useState<Pagination | null>(null);
  const [vulnerabilitiesLoading, setVulnerabilitiesLoading] = useState(false);
  const [vulnerabilitiesPage, setVulnerabilitiesPage] = useState(1);
  const [severityFilter, setSeverityFilter] = useState<Severity | ''>('');

  const fetchSbom = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      const data = await sbomsApi.get(id);
      setSbom(data);
    } catch {
      showNotification(err instanceof Error ? err.message : 'Failed to fetch SBOM', 'error');
    } finally {
      setLoading(false);
    }
  }, [id, showNotification]);

  const fetchComponents = useCallback(async () => {
    if (!id) return;
    try {
      setComponentsLoading(true);
      const data = await sbomsApi.getComponents(id, {
        page: componentsPage,
        per_page: 20,
        ecosystem: ecosystemFilter || undefined,
      });
      setComponents(data.components);
      setComponentsPagination(data.pagination);
    } catch {
      showNotification(err instanceof Error ? err.message : 'Failed to fetch components', 'error');
    } finally {
      setComponentsLoading(false);
    }
  }, [id, componentsPage, ecosystemFilter, showNotification]);

  const fetchVulnerabilities = useCallback(async () => {
    if (!id) return;
    try {
      setVulnerabilitiesLoading(true);
      const data = await sbomsApi.getVulnerabilities(id, {
        page: vulnerabilitiesPage,
        per_page: 20,
        severity: severityFilter || undefined,
      });
      setVulnerabilities(data.vulnerabilities);
      setVulnerabilitiesPagination(data.pagination);
    } catch {
      showNotification(err instanceof Error ? err.message : 'Failed to fetch vulnerabilities', 'error');
    } finally {
      setVulnerabilitiesLoading(false);
    }
  }, [id, vulnerabilitiesPage, severityFilter, showNotification]);

  useEffect(() => {
    fetchSbom();
  }, [fetchSbom]);

  useEffect(() => {
    if (activeTab === 'components') {
      fetchComponents();
    } else if (activeTab === 'vulnerabilities') {
      fetchVulnerabilities();
    }
  }, [activeTab, fetchComponents, fetchVulnerabilities]);

  const handleExport = async (format: 'json' | 'xml' | 'pdf' | 'cyclonedx' | 'spdx') => {
    if (!id) return;
    try {
      const blob = await sbomsApi.exportSbom(id, format);
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      const extension = format === 'cyclonedx' || format === 'spdx' ? 'json' : format;
      a.download = `${sbom?.name || 'sbom'}.${extension}`;
      a.click();
      window.URL.revokeObjectURL(url);
      showNotification(`SBOM exported as ${format.toUpperCase()}`, 'success');
    } catch {
      showNotification(err instanceof Error ? err.message : 'Failed to export SBOM', 'error');
    }
  };

  const handleUpdateVulnStatus = async (vulnId: string, status: RemediationStatus) => {
    if (!id) return;
    try {
      await updateStatusMutation.mutateAsync({ sbomId: id, vulnId, status });
      showNotification('Status updated', 'success');
      fetchVulnerabilities();
    } catch {
      showNotification('Failed to update status', 'error');
    }
  };

  const handleSuppressVuln = async (vulnId: string) => {
    if (!id) return;
    try {
      await suppressMutation.mutateAsync({ sbomId: id, vulnId });
      showNotification('Vulnerability suppressed', 'success');
      fetchVulnerabilities();
    } catch {
      showNotification('Failed to suppress vulnerability', 'error');
    }
  };

  const handleMarkFalsePositive = async (vulnId: string) => {
    if (!id) return;
    const reason = window.prompt('Enter reason for marking as false positive:');
    if (!reason) return;
    try {
      await markFalsePositiveMutation.mutateAsync({ sbomId: id, vulnId, reason });
      showNotification('Marked as false positive', 'success');
      fetchVulnerabilities();
    } catch {
      showNotification('Failed to mark as false positive', 'error');
    }
  };

  const handleCreateDiff = async (compareSbomId: string) => {
    if (!id) return;
    try {
      const diff = await createDiffMutation.mutateAsync({ sbomId: id, compareSbomId });
      showNotification('Diff created successfully', 'success');
      refreshDiffs();
      navigate(`/app/supply-chain/sboms/${id}/diff/${diff.id}`);
    } catch {
      showNotification('Failed to create diff', 'error');
    }
  };

  const handleCalculateRisk = async () => {
    if (!id) return;
    try {
      const result = await calculateRiskMutation.mutateAsync(id);
      showNotification(`Risk calculated: ${result.overall_score.toFixed(1)}`, 'success');
      fetchSbom();
    } catch {
      showNotification('Failed to calculate risk', 'error');
    }
  };

  const handleCorrelateVulns = async () => {
    if (!id) return;
    try {
      const result = await correlateVulnsMutation.mutateAsync(id);
      showNotification(`Found ${result.new_vulnerabilities} new vulnerabilities`, 'success');
      fetchVulnerabilities();
    } catch {
      showNotification('Failed to correlate vulnerabilities', 'error');
    }
  };

  const handleRescan = async () => {
    if (!id) return;
    try {
      const updated = await sbomsApi.rescan(id);
      setSbom(updated);
      showNotification('SBOM re-scan initiated', 'success');
    } catch {
      showNotification(err instanceof Error ? err.message : 'Failed to re-scan SBOM', 'error');
    }
  };

  const handleDelete = () => {
    if (!id || !sbom) return;
    confirm({
      title: 'Delete SBOM',
      message: `Are you sure you want to delete "${sbom.name}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await sbomsApi.delete(id);
          showNotification('SBOM deleted successfully', 'success');
          navigate('/app/supply-chain/sboms');
        } catch {
          showNotification(err instanceof Error ? err.message : 'Failed to delete SBOM', 'error');
        }
      },
    });
  };

  const componentColumns = [
    {
      key: 'name',
      header: 'Component',
      render: (item: SbomComponent) => (
        <div>
          <div className="font-medium text-theme-primary">{item.name}</div>
          <div className="text-xs text-theme-tertiary">{item.version}</div>
        </div>
      ),
    },
    {
      key: 'ecosystem',
      header: 'Ecosystem',
      render: (item: SbomComponent) => (
        <Badge variant="outline" size="sm">
          {item.ecosystem}
        </Badge>
      ),
    },
    {
      key: 'dependency_type',
      header: 'Type',
      render: (item: SbomComponent) => (
        <span className="text-theme-secondary text-sm capitalize">{item.dependency_type}</span>
      ),
    },
    {
      key: 'depth',
      header: 'Depth',
      render: (item: SbomComponent) => <span className="text-theme-tertiary text-sm">{item.depth}</span>,
    },
    {
      key: 'vulnerabilities',
      header: 'Vulnerabilities',
      render: (item: SbomComponent) => (
        <div className="flex items-center gap-1">
          {item.has_known_vulnerabilities ? (
            <AlertTriangle className="w-4 h-4 text-theme-error" />
          ) : (
            <CheckCircle className="w-4 h-4 text-theme-success" />
          )}
        </div>
      ),
    },
    {
      key: 'risk_score',
      header: 'Risk',
      render: (item: SbomComponent) => {
        const variant = item.risk_score >= 7 ? 'danger' : item.risk_score >= 4 ? 'warning' : 'success';
        return (
          <Badge variant={variant} size="sm">
            {item.risk_score.toFixed(1)}
          </Badge>
        );
      },
    },
  ];

  const vulnerabilityColumns = [
    {
      key: 'vulnerability_id',
      header: 'Vulnerability',
      render: (item: SbomVulnerability) => (
        <div>
          <div className="font-medium text-theme-primary">{item.vulnerability_id}</div>
          <div className="text-xs text-theme-tertiary">
            {item.component.name}@{item.component.version}
          </div>
        </div>
      ),
    },
    {
      key: 'severity',
      header: 'Severity',
      render: (item: SbomVulnerability) => <SeverityBadge severity={item.severity} />,
    },
    {
      key: 'cvss_score',
      header: 'CVSS',
      render: (item: SbomVulnerability) => (
        <span className="font-mono text-sm text-theme-primary">{item.cvss_score.toFixed(1)}</span>
      ),
    },
    {
      key: 'remediation_status',
      header: 'Status',
      render: (item: SbomVulnerability) => <RemediationBadge status={item.remediation_status} />,
    },
    {
      key: 'fixed_version',
      header: 'Fixed In',
      render: (item: SbomVulnerability) => (
        <span className="text-theme-secondary text-sm">{item.fixed_version || 'N/A'}</span>
      ),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (item: SbomVulnerability) => (
        <div className="flex items-center gap-2">
          <RemediationStatusSelect
            value={item.remediation_status}
            onChange={(status) => handleUpdateVulnStatus(item.id, status)}
            size="sm"
          />
          <VulnerabilityActionsMenu
            vulnerabilityId={item.id}
            currentStatus={item.remediation_status}
            onSuppress={() => handleSuppressVuln(item.id)}
            onUnsuppress={() => handleSuppressVuln(item.id)}
            onMarkFalsePositive={() => handleMarkFalsePositive(item.id)}
            onUpdateStatus={(status) => handleUpdateVulnStatus(item.id, status)}
          />
        </div>
      ),
    },
  ];

  if (loading || !sbom) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <LoadingSpinner size="lg" />
        <span className="ml-3 text-theme-secondary">Loading SBOM...</span>
      </div>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'SBOMs', href: '/app/supply-chain/sboms' },
    { label: sbom.name },
  ];

  const actions = [
    {
      id: 'compare',
      label: 'Compare',
      onClick: () => setShowDiffModal(true),
      variant: 'secondary' as const,
      icon: GitCompare,
    },
    {
      id: 'rescan',
      label: 'Re-scan',
      onClick: handleRescan,
      variant: 'secondary' as const,
      icon: RefreshCw,
      disabled: sbom.status === 'generating',
    },
    {
      id: 'delete',
      label: 'Delete',
      onClick: handleDelete,
      variant: 'danger' as const,
      icon: Trash2,
    },
  ];

  const tabs = [
    {
      id: 'overview',
      label: 'Overview',
      content: (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-2 text-theme-secondary mb-1">
                <Package className="w-4 h-4" />
                <span className="text-sm">Components</span>
              </div>
              <p className="text-2xl font-bold text-theme-primary">{sbom.component_count}</p>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-2 text-theme-error mb-1">
                <AlertTriangle className="w-4 h-4" />
                <span className="text-sm">Vulnerabilities</span>
              </div>
              <p className="text-2xl font-bold text-theme-error">{sbom.vulnerability_count}</p>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-2 text-theme-warning mb-1">
                <span className="text-sm">Risk Score</span>
              </div>
              <p className="text-2xl font-bold text-theme-warning">{sbom.risk_score.toFixed(1)}</p>
            </div>
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-2 text-theme-secondary mb-1">
                <span className="text-sm">NTIA Compliant</span>
              </div>
              <div className="flex items-center gap-2">
                {sbom.ntia_minimum_compliant ? (
                  <>
                    <CheckCircle className="w-6 h-6 text-theme-success" />
                    <span className="text-lg font-medium text-theme-success">Yes</span>
                  </>
                ) : (
                  <>
                    <XCircle className="w-6 h-6 text-theme-error" />
                    <span className="text-lg font-medium text-theme-error">No</span>
                  </>
                )}
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg p-6 border border-theme space-y-4">
            <h3 className="text-lg font-medium text-theme-primary">Details</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <span className="text-sm text-theme-secondary">Format:</span>
                <p className="text-theme-primary">{sbom.format.toUpperCase()}</p>
              </div>
              <div>
                <span className="text-sm text-theme-secondary">Version:</span>
                <p className="text-theme-primary">{sbom.version}</p>
              </div>
              <div>
                <span className="text-sm text-theme-secondary">Status:</span>
                <div className="mt-1">
                  <StatusBadge status={sbom.status} />
                </div>
              </div>
              <div>
                <span className="text-sm text-theme-secondary">SBOM ID:</span>
                <p className="text-theme-primary font-mono text-sm">{sbom.sbom_id}</p>
              </div>
              {sbom.repository && (
                <div>
                  <span className="text-sm text-theme-secondary">Repository:</span>
                  <p className="text-theme-primary">{sbom.repository.full_name}</p>
                </div>
              )}
              {sbom.branch && (
                <div>
                  <span className="text-sm text-theme-secondary">Branch:</span>
                  <p className="text-theme-primary">{sbom.branch}</p>
                </div>
              )}
              {sbom.commit_sha && (
                <div>
                  <span className="text-sm text-theme-secondary">Commit:</span>
                  <p className="text-theme-primary font-mono text-sm">{sbom.commit_sha.substring(0, 12)}</p>
                </div>
              )}
              <div>
                <span className="text-sm text-theme-secondary">Created:</span>
                <p className="text-theme-primary">{new Date(sbom.created_at).toLocaleString()}</p>
              </div>
            </div>
          </div>
        </div>
      ),
    },
    {
      id: 'components',
      label: 'Components',
      badge: sbom.component_count,
      content: (
        <div className="space-y-4">
          <div className="flex items-center gap-4">
            <select
              value={ecosystemFilter}
              onChange={(e) => {
                setEcosystemFilter(e.target.value);
                setComponentsPage(1);
              }}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
            >
              <option value="">All Ecosystems</option>
              <option value="npm">NPM</option>
              <option value="pypi">PyPI</option>
              <option value="gem">RubyGems</option>
              <option value="maven">Maven</option>
            </select>
          </div>
          <DataTable
            columns={componentColumns}
            data={components}
            loading={componentsLoading}
            pagination={componentsPagination || undefined}
            onPageChange={setComponentsPage}
            emptyState={{
              icon: Package,
              title: 'No Components Found',
              description: 'No components match your current filters.',
            }}
          />
        </div>
      ),
    },
    {
      id: 'vulnerabilities',
      label: 'Vulnerabilities',
      badge: sbom.vulnerability_count,
      content: (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <select
              value={severityFilter}
              onChange={(e) => {
                setSeverityFilter(e.target.value as Severity | '');
                setVulnerabilitiesPage(1);
              }}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
            >
              <option value="">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
            <div className="flex items-center gap-2">
              <Button
                variant="secondary"
                size="sm"
                onClick={handleCalculateRisk}
                disabled={calculateRiskMutation.isLoading}
              >
                <Calculator className="w-4 h-4 mr-1" />
                {calculateRiskMutation.isLoading ? 'Calculating...' : 'Calculate Risk'}
              </Button>
              <Button
                variant="secondary"
                size="sm"
                onClick={handleCorrelateVulns}
                disabled={correlateVulnsMutation.isLoading}
              >
                <RefreshCw className="w-4 h-4 mr-1" />
                {correlateVulnsMutation.isLoading ? 'Correlating...' : 'Correlate'}
              </Button>
            </div>
          </div>
          <DataTable
            columns={vulnerabilityColumns}
            data={vulnerabilities}
            loading={vulnerabilitiesLoading}
            pagination={vulnerabilitiesPagination || undefined}
            onPageChange={setVulnerabilitiesPage}
            emptyState={{
              icon: CheckCircle,
              title: 'No Vulnerabilities Found',
              description: 'No vulnerabilities detected in this SBOM.',
            }}
          />
        </div>
      ),
    },
    {
      id: 'compliance',
      label: 'Compliance',
      content: complianceLoading ? (
        <div className="flex justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      ) : compliance ? (
        <ComplianceStatusCard compliance={compliance} />
      ) : (
        <div className="text-center py-12 text-theme-muted">
          <Shield className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>Compliance data not available</p>
        </div>
      ),
    },
    {
      id: 'diffs',
      label: 'Diff History',
      badge: diffs.length,
      content: (
        <div className="space-y-4">
          <div className="flex justify-end">
            <Button variant="primary" size="sm" onClick={() => setShowDiffModal(true)}>
              <GitCompare className="w-4 h-4 mr-1" />
              Create Diff
            </Button>
          </div>
          {diffs.length === 0 ? (
            <div className="text-center py-12 text-theme-muted">
              <GitCompare className="w-12 h-12 mx-auto mb-4 opacity-50" />
              <p>No diffs created yet</p>
              <p className="text-sm mt-2">Compare this SBOM with another version to track changes</p>
            </div>
          ) : (
            <div className="space-y-3">
              {diffs.map((diff) => (
                <button
                  key={diff.id}
                  onClick={() => navigate(`/app/supply-chain/sboms/${id}/diff/${diff.id}`)}
                  className="w-full p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-interactive-primary transition-colors text-left"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      <span className="text-theme-success">+{diff.added_count}</span>
                      <span className="text-theme-error">-{diff.removed_count}</span>
                      <span className="text-theme-warning">~{diff.changed_count}</span>
                    </div>
                    <span className="text-sm text-theme-secondary">
                      {new Date(diff.created_at).toLocaleDateString()}
                    </span>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      ),
    },
  ];

  return (
    <PageContainer title={sbom.name} breadcrumbs={breadcrumbs} actions={actions}>
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <StatusBadge status={sbom.status} />
            <Badge variant="outline" size="sm">
              {sbom.format.toUpperCase()}
            </Badge>
          </div>
          <ExportFormatDropdown onExport={handleExport} />
        </div>

        <TabContainer tabs={tabs} activeTab={activeTab} onTabChange={setActiveTab} variant="underline" />
      </div>
      {ConfirmationDialog}
      {showDiffModal && (
        <CreateDiffModal
          currentSbomId={id!}
          currentSbomName={sbom.name}
          onClose={() => setShowDiffModal(false)}
          onCreateDiff={handleCreateDiff}
        />
      )}
    </PageContainer>
  );
};

export const SbomDetailPage: React.FC = () => (
  <PageErrorBoundary>
    <SbomDetailPageContent />
  </PageErrorBoundary>
);

export default SbomDetailPage;
