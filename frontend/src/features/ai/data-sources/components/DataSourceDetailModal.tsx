import React, { useState, useEffect, useRef } from 'react';
import { Database, AlertCircle, Key, Activity } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { DataSourceOverviewTab } from './DataSourceOverviewTab';
import { DataSourceCredentialsTab } from './DataSourceCredentialsTab';
import { DataSourceQuotaTab } from './DataSourceQuotaTab';
import { DataSourceActionsBar } from './DataSourceActionsBar';
import { SOURCE_TYPE_LABELS } from './sourceTypeLabels';
import type { AiDataSource } from '@/shared/types/ai';

export interface DataSourceDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  dataSourceId: string;
  onUpdate?: () => void;
  onEdit?: (dataSourceId: string) => void;
  onDelete?: (dataSourceId: string) => void;
}

export const DataSourceDetailModal: React.FC<DataSourceDetailModalProps> = ({
  isOpen, onClose, dataSourceId, onUpdate, onEdit, onDelete
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [dataSource, setDataSource] = useState<AiDataSource | null>(null);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const testingRef = useRef(false);

  const canManageDataSources = currentUser?.permissions?.includes('ai.data_sources.update') || false;
  const canDeleteDataSources = currentUser?.permissions?.includes('ai.data_sources.delete') || false;
  const canTestConnection = currentUser?.permissions?.includes('ai.data_sources.update') || false;

  const loadDataSource = async () => {
    if (!dataSourceId || !isOpen) return;
    try {
      setLoading(true); setError(null);
      const response = await dataSourcesApi.getDataSource(dataSourceId);
      setDataSource(response);
    } catch (_error) {
      setError('Failed to load data source details. Please try again.');
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load data source details' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen && dataSourceId) { setDataSource(null); setLoading(true); setError(null); loadDataSource(); }
  }, [isOpen, dataSourceId]);

  const handleTestConnection = async () => {
    if (!dataSource || !canTestConnection || testingRef.current) return;
    testingRef.current = true;
    try {
      setTesting(true);
      const response = await dataSourcesApi.testConnection(dataSource.id);
      const timeDisplay = response.response_time_ms != null ? `${response.response_time_ms}ms` : 'N/A';
      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Connection Test',
        message: response.success ? `Connection successful (${timeDisplay})` : `Connection failed: ${response.error || 'Unknown error'}`,
      });
      if (response.success) { loadDataSource(); onUpdate?.(); }
    } catch (_error) {
      addNotification({ type: 'error', title: 'Test Failed', message: 'Failed to test data source connection' });
    } finally {
      setTesting(false); testingRef.current = false;
    }
  };

  const handleEdit = () => { if (dataSource) { onEdit?.(dataSource.id); onClose(); } };
  const handleDelete = async () => {
    if (!dataSource) return;
    if (confirm(`Are you sure you want to delete the data source "${dataSource.name}"? This action cannot be undone.`)) {
      await onDelete?.(dataSource.id); onClose();
    }
  };

  const getSourceTypeLabel = (type: string): string => {
    return SOURCE_TYPE_LABELS[type] || type.replace(/_/g, ' ');
  };

  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy': return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'degraded': return <Badge variant="warning" size="sm">Degraded</Badge>;
      case 'critical': return <Badge variant="danger" size="sm">Critical</Badge>;
      default: return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getSourceTypeIcon = (type: string): string => {
    const iconMap: Record<string, string> = {
      'noaa_ncei': '🌡️', 'noaa_gfs': '🌤️', 'noaa_observations': '📡',
      'open_meteo': '☁️', 'custom': '🔧'
    };
    return iconMap[type] || '📊';
  };

  if (loading || !dataSource) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Loading Data Source..." maxWidth="3xl" icon={<Database />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <LoadingSpinner className="py-12" />
      </Modal>
    );
  }

  if (error) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Error Loading Data Source" maxWidth="md" icon={<Database />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <div className="text-center py-8">
          <p className="text-theme-error">{error}</p>
          <Button variant="outline" onClick={loadDataSource} className="mt-4">Try Again</Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen} onClose={onClose}
      title={
        <div className="flex items-center gap-3">
          <div className="h-8 w-8 bg-theme-surface-secondary rounded-lg flex items-center justify-center">
            <span className="text-lg">{getSourceTypeIcon(dataSource.source_type)}</span>
          </div>
          {dataSource.name}
        </div>
      }
      subtitle={dataSource.description} maxWidth="3xl" variant="centered" icon={<Database />}
      footer={
        <DataSourceActionsBar
          dataSource={dataSource} canManageDataSources={canManageDataSources}
          canDeleteDataSources={canDeleteDataSources} canTestConnection={canTestConnection}
          testing={testing} onClose={onClose}
          onTestConnection={handleTestConnection}
          onEdit={handleEdit} onDelete={handleDelete}
        />
      }
    >
      <div className="space-y-4 overflow-hidden">
        {/* Header Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-tertiary">Status</p>{getHealthStatusBadge(dataSource.health_status)}</div><Activity className="h-5 w-5 text-theme-tertiary" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-tertiary">Type</p><Badge variant="outline" size="sm">{getSourceTypeLabel(dataSource.source_type)}</Badge></div><Database className="h-5 w-5 text-theme-tertiary" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-tertiary">Priority</p><p className="text-lg font-semibold text-theme-primary">#{dataSource.priority_order}</p></div><Activity className="h-5 w-5 text-theme-tertiary" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-tertiary">Credentials</p><p className="text-lg font-semibold text-theme-primary">{dataSource.credential_count}</p></div><Key className="h-5 w-5 text-theme-tertiary" /></div></CardContent></Card>
        </div>

        {/* Warning Messages */}
        {(!dataSource.is_active || dataSource.health_status === 'critical' || ((dataSource.credential_count ?? 0) === 0 && dataSource.requires_auth)) && (
          <div className="space-y-3">
            {!dataSource.is_active && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2"><AlertCircle className="h-4 w-4 text-theme-warning" /><span className="text-sm text-theme-warning">Data source is currently inactive</span></div>
              </div>
            )}
            {dataSource.health_status === 'critical' && (
              <div className="p-4 bg-theme-error/10 border border-theme-error/20 rounded-lg">
                <div className="flex items-center gap-2"><AlertCircle className="h-4 w-4 text-theme-error" /><span className="text-sm text-theme-error">Data source health check is critical</span></div>
              </div>
            )}
            {(dataSource.credential_count ?? 0) === 0 && dataSource.requires_auth && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2"><Key className="h-4 w-4 text-theme-warning" /><span className="text-sm text-theme-warning">No credentials configured. Add credentials to start using this data source.</span></div>
              </div>
            )}
          </div>
        )}

        {/* Main Content Tabs */}
        <Tabs defaultValue="overview" className="space-y-4">
          <TabsList className="w-full justify-start overflow-x-auto">
            <TabsTrigger value="overview" className="whitespace-nowrap">Overview</TabsTrigger>
            <TabsTrigger value="credentials" className="whitespace-nowrap">Credentials ({dataSource.credential_count ?? 0})</TabsTrigger>
            <TabsTrigger value="quota" className="whitespace-nowrap">Quota</TabsTrigger>
          </TabsList>

          <TabsContent value="overview"><DataSourceOverviewTab dataSource={dataSource} /></TabsContent>
          <TabsContent value="credentials">
            <DataSourceCredentialsTab
              credentials={dataSource.credentials || []}
              canManageDataSources={canManageDataSources}
              onEdit={handleEdit}
            />
          </TabsContent>
          <TabsContent value="quota">
            <DataSourceQuotaTab dataSource={dataSource} />
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};
