import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, Eye, PlayCircle, Shield, FileText, Database } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { DataTable, DataTableColumn } from '@/shared/components/ui/DataTable';
import { RiskTierBadge } from '../components/RiskTierBadge';
import { StatusBadge } from '../components/StatusBadge';
import { Badge } from '@/shared/components/ui/Badge';
import { useVendors, useCreateVendor, useStartAssessment } from '../hooks/useVendorRisk';
import { formatDistanceToNow } from 'date-fns';
import { AddVendorModal } from '../components/vendor/AddVendorModal';
import { StartAssessmentModal } from '../components/vendor/StartAssessmentModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

type VendorType = 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';
type RiskTier = 'critical' | 'high' | 'medium' | 'low';
type VendorStatus = 'active' | 'inactive' | 'pending' | 'suspended';

interface Vendor {
  id: string;
  name: string;
  vendor_type: VendorType;
  risk_tier: RiskTier;
  risk_score: number;
  status: VendorStatus;
  handles_pii: boolean;
  handles_phi: boolean;
  handles_pci: boolean;
  certifications: string[];
  last_assessment_at?: string;
  next_assessment_due?: string;
  created_at: string;
  updated_at: string;
}

export const VendorsPage: React.FC = () => {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState('all');
  const [currentPage, setCurrentPage] = useState(1);
  const [showAddModal, setShowAddModal] = useState(false);
  const [showAssessmentModal, setShowAssessmentModal] = useState(false);
  const [selectedVendorId, setSelectedVendorId] = useState<string | null>(null);
  const [selectedVendorName, setSelectedVendorName] = useState<string>('');

  const createVendorMutation = useCreateVendor();
  const startAssessmentMutation = useStartAssessment();
  const { showNotification } = useNotifications();

  const riskTierFilter = activeTab === 'critical' ? 'critical' : activeTab === 'high' ? 'high' : undefined;

  const { vendors, pagination, loading, error, refresh } = useVendors({
    page: currentPage,
    perPage: 20,
    riskTier: riskTierFilter,
  });

  const getTypeLabel = (type: VendorType): string => {
    const labels: Record<VendorType, string> = {
      saas: 'SaaS',
      api: 'API',
      library: 'Library',
      infrastructure: 'Infrastructure',
      hardware: 'Hardware',
      consulting: 'Consulting',
    };
    return labels[type];
  };

  const getRiskScoreColor = (score: number): string => {
    if (score >= 80) return 'text-theme-error';
    if (score >= 60) return 'text-theme-warning';
    if (score >= 40) return 'text-theme-info';
    return 'text-theme-success';
  };

  const handleAddVendor = async (data: {
    name: string;
    vendor_type: 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';
    contact_name?: string;
    contact_email?: string;
    website?: string;
    handles_pii?: boolean;
    handles_phi?: boolean;
    handles_pci?: boolean;
    certifications?: string[];
  }) => {
    try {
      await createVendorMutation.mutateAsync(data);
      showNotification('Vendor created successfully', 'success');
      setShowAddModal(false);
      refresh();
    } catch {
      showNotification('Failed to create vendor', 'error');
    }
  };

  const handleStartAssessment = async (assessmentType: 'initial' | 'periodic' | 'incident' | 'renewal') => {
    if (!selectedVendorId) return;
    try {
      await startAssessmentMutation.mutateAsync({
        vendorId: selectedVendorId,
        assessmentType,
      });
      showNotification('Assessment started successfully', 'success');
      setShowAssessmentModal(false);
      setSelectedVendorId(null);
      refresh();
    } catch {
      showNotification('Failed to start assessment', 'error');
    }
  };

  const openAssessmentModal = (vendorId: string, vendorName: string) => {
    setSelectedVendorId(vendorId);
    setSelectedVendorName(vendorName);
    setShowAssessmentModal(true);
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: refresh,
    loading,
  });

  const columns: DataTableColumn<Vendor>[] = [
    {
      key: 'name',
      header: 'Name',
      render: (vendor) => (
        <button
          onClick={() => navigate(`/app/supply-chain/vendors/${vendor.id}`)}
          className="text-theme-interactive-primary hover:underline font-medium"
        >
          {vendor.name}
        </button>
      ),
    },
    {
      key: 'vendor_type',
      header: 'Type',
      render: (vendor) => (
        <Badge variant="secondary" size="sm">
          {getTypeLabel(vendor.vendor_type)}
        </Badge>
      ),
    },
    {
      key: 'risk_tier',
      header: 'Risk Tier',
      render: (vendor) => <RiskTierBadge tier={vendor.risk_tier} />,
    },
    {
      key: 'risk_score',
      header: 'Risk Score',
      render: (vendor) => (
        <span className={`font-semibold ${getRiskScoreColor(vendor.risk_score)}`}>
          {vendor.risk_score}/100
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (vendor) => <StatusBadge status={vendor.status} />,
    },
    {
      key: 'data_sensitivity',
      header: 'Data Sensitivity',
      render: (vendor) => (
        <div className="flex items-center gap-2">
          {vendor.handles_pii && (
            <Badge variant="info" size="xs" className="flex items-center gap-1">
              <Shield className="w-3 h-3" />
              PII
            </Badge>
          )}
          {vendor.handles_phi && (
            <Badge variant="warning" size="xs" className="flex items-center gap-1">
              <FileText className="w-3 h-3" />
              PHI
            </Badge>
          )}
          {vendor.handles_pci && (
            <Badge variant="danger" size="xs" className="flex items-center gap-1">
              <Database className="w-3 h-3" />
              PCI
            </Badge>
          )}
          {!vendor.handles_pii && !vendor.handles_phi && !vendor.handles_pci && (
            <span className="text-theme-muted text-sm">None</span>
          )}
        </div>
      ),
    },
    {
      key: 'last_assessment',
      header: 'Last Assessment',
      render: (vendor) =>
        vendor.last_assessment_at ? (
          <span className="text-theme-secondary text-sm">
            {formatDistanceToNow(new Date(vendor.last_assessment_at), { addSuffix: true })}
          </span>
        ) : (
          <span className="text-theme-muted text-sm">Never</span>
        ),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (vendor) => (
        <div className="flex items-center gap-2">
          <button
            onClick={() => navigate(`/app/supply-chain/vendors/${vendor.id}`)}
            className="text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
            title="View Details"
          >
            <Eye className="w-4 h-4" />
          </button>
          <button
            onClick={() => openAssessmentModal(vendor.id, vendor.name)}
            className="text-theme-warning hover:text-theme-warning-hover"
            title="Start Assessment"
          >
            <PlayCircle className="w-4 h-4" />
          </button>
        </div>
      ),
    },
  ];

  const tabs = [
    { id: 'all', label: 'All Vendors' },
    { id: 'critical', label: 'Critical Risk' },
    { id: 'high', label: 'High Risk' },
    { id: 'needs-assessment', label: 'Needs Assessment' },
  ];

  const filteredVendors = (() => {
    if (activeTab === 'needs-assessment') {
      return vendors.filter(
        (v) =>
          !v.last_assessment_at ||
          (v.next_assessment_due && new Date(v.next_assessment_due) < new Date())
      );
    }
    return vendors;
  })();

  return (
    <PageContainer
      title="Vendor Management"
      description="Manage and assess third-party vendor risks"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Supply Chain', href: '/app/supply-chain' },
        { label: 'Vendors' },
      ]}
      actions={[
        refreshAction,
        {
          id: 'add-vendor',
          label: 'Add Vendor',
          onClick: () => setShowAddModal(true),
          variant: 'primary',
          icon: Plus,
        },
      ]}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        variant="underline"
      >
        <div className="mt-6">
          {error && (
            <div className="bg-theme-error bg-opacity-10 text-theme-error p-4 rounded-lg mb-4">
              {error}
            </div>
          )}

          <DataTable
            columns={columns}
            data={filteredVendors}
            loading={loading}
            pagination={pagination || undefined}
            onPageChange={setCurrentPage}
            emptyState={{
              title: 'No vendors found',
              description: 'Get started by adding your first vendor',
              action: {
                label: 'Add Vendor',
                onClick: () => setShowAddModal(true),
              },
            }}
          />
        </div>
      </TabContainer>

      {showAddModal && (
        <AddVendorModal
          onClose={() => setShowAddModal(false)}
          onAdd={handleAddVendor}
        />
      )}

      {showAssessmentModal && (
        <StartAssessmentModal
          onClose={() => {
            setShowAssessmentModal(false);
            setSelectedVendorId(null);
          }}
          onStart={handleStartAssessment}
          vendorName={selectedVendorName}
        />
      )}
    </PageContainer>
  );
};
