import React, { useState, useEffect, useRef } from 'react';
import { Settings, AlertCircle, Key, Activity, Star, TestTube } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { Avatar } from '@/shared/components/ui/Avatar';
import { providersApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ProviderOverviewTab } from './ProviderOverviewTab';
import { ProviderCredentialsTab } from './ProviderCredentialsTab';
import { ProviderMetricsTab } from './ProviderMetricsTab';
import { ProviderModelsTab } from './ProviderModelsTab';
import { ProviderActionsBar } from './ProviderActionsBar';
import type { AiProvider } from '@/shared/types/ai';

export interface ProviderDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  providerId: string;
  onUpdate?: () => void;
  onEdit?: (providerId: string) => void;
  onDelete?: (providerId: string) => void;
}

export const ProviderDetailModal: React.FC<ProviderDetailModalProps> = ({
  isOpen, onClose, providerId, onUpdate, onEdit, onDelete
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [provider, setProvider] = useState<AiProvider | null>(null);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const testingRef = useRef(false);

  const canManageProviders = currentUser?.permissions?.includes('ai.providers.update') || false;
  const canDeleteProviders = currentUser?.permissions?.includes('ai.providers.delete') || false;
  const canTestCredentials = currentUser?.permissions?.includes('ai.providers.test') || false;

  const loadProvider = async () => {
    if (!providerId || !isOpen) return;
    try {
      setLoading(true); setError(null);
      const response = await providersApi.getProvider(providerId);
      setProvider(response);
    } catch (_error) {
      setError('Failed to load provider details. Please try again.');
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load provider details' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen && providerId) { setProvider(null); setLoading(true); setError(null); loadProvider(); }
  }, [isOpen, providerId]);

  const handleTestConnection = async () => {
    if (!provider || !canTestCredentials || testingRef.current) return;
    testingRef.current = true;
    try {
      setTesting(true);
      const response = await providersApi.testConnection(provider.id);
      const timeDisplay = response.response_time_ms != null ? `${response.response_time_ms}ms` : 'N/A';
      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Connection Test',
        message: response.success ? `Connection successful (${timeDisplay})` : `Connection failed: ${response.error || 'Unknown error'}`,
      });
      if (response.success) { loadProvider(); onUpdate?.(); }
    } catch (_error) {
      addNotification({ type: 'error', title: 'Test Failed', message: 'Failed to test provider connection' });
    } finally {
      setTesting(false); testingRef.current = false;
    }
  };

  const handleSyncModels = async () => {
    if (!provider || !canManageProviders) return;
    try {
      setSyncing(true);
      await providersApi.syncModels(provider.id);
      addNotification({ type: 'success', title: 'Models Synced', message: 'Provider models updated successfully' });
      loadProvider(); onUpdate?.();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Sync Failed', message: 'Failed to sync provider models' });
    } finally {
      setSyncing(false);
    }
  };

  const handleEdit = () => { if (provider) { onEdit?.(provider.id); onClose(); } };
  const handleDelete = async () => {
    if (!provider) return;
    if (confirm(`Are you sure you want to delete the provider "${provider.name}"? This action cannot be undone.`)) {
      await onDelete?.(provider.id); onClose();
    }
  };

  const getProviderIcon = (slug: string) => {
    const iconMap: Record<string, string> = {
      'ollama': '🦙', 'openai': '🤖', 'anthropic': '🧠', 'stability-ai': '🎨',
      'mistral': '🌪️', 'cohere': '💫', 'huggingface': '🤗', 'replicate': '🔄', 'together': '🤝'
    };
    return iconMap[slug] || '⚙️';
  };

  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy': return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'unhealthy': return <Badge variant="danger" size="sm">Unhealthy</Badge>;
      case 'inactive': return <Badge variant="secondary" size="sm">Inactive</Badge>;
      default: return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getProviderTypeBadge = (type: string) => {
    const typeMap: Record<string, { label: string; variant: 'default' | 'secondary' | 'outline' }> = {
      'text_generation': { label: 'Text', variant: 'default' }, 'image_generation': { label: 'Image', variant: 'secondary' },
      'code_execution': { label: 'Code', variant: 'outline' }, 'embedding': { label: 'Embedding', variant: 'outline' },
      'multimodal': { label: 'Multimodal', variant: 'default' }
    };
    const config = typeMap[type] || { label: type, variant: 'outline' as const };
    return <Badge variant={config.variant} size="sm">{config.label}</Badge>;
  };

  if (loading || !provider) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Loading Provider..." maxWidth="3xl" icon={<Settings />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <LoadingSpinner className="py-12" />
      </Modal>
    );
  }

  if (error) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Error Loading Provider" maxWidth="md" icon={<Settings />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <div className="text-center py-8">
          <p className="text-theme-error">{error}</p>
          <Button variant="outline" onClick={loadProvider} className="mt-4">Try Again</Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen} onClose={onClose}
      title={
        <div className="flex items-center gap-3">
          <Avatar className="h-8 w-8"><span className="text-lg">{getProviderIcon(provider.slug)}</span></Avatar>
          {provider.name}
        </div>
      }
      subtitle={provider.description} maxWidth="3xl" variant="centered" icon={<Settings />}
      footer={
        <ProviderActionsBar
          provider={provider} canManageProviders={canManageProviders}
          canDeleteProviders={canDeleteProviders} canTestCredentials={canTestCredentials}
          testing={testing} syncing={syncing} onClose={onClose}
          onTestConnection={handleTestConnection} onSyncModels={handleSyncModels}
          onEdit={handleEdit} onDelete={handleDelete}
        />
      }
    >
      <div className="space-y-4 overflow-hidden">
        {/* Header Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-muted">Status</p>{getHealthStatusBadge(provider.health_status)}</div><Activity className="h-5 w-5 text-theme-muted" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-muted">Type</p>{getProviderTypeBadge(provider.provider_type)}</div><Settings className="h-5 w-5 text-theme-muted" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-muted">Priority</p><div className="flex items-center gap-1"><p className="text-lg font-semibold text-theme-primary">#{provider.priority_order}</p>{provider.priority_order <= 3 && <Star className="h-4 w-4 text-theme-warning fill-current" />}</div></div><Star className="h-5 w-5 text-theme-muted" /></div></CardContent></Card>
          <Card><CardContent className="p-4"><div className="flex items-center justify-between"><div><p className="text-sm text-theme-muted">Models</p><p className="text-lg font-semibold text-theme-primary">{provider.model_count}</p></div><TestTube className="h-5 w-5 text-theme-muted" /></div></CardContent></Card>
        </div>

        {/* Warning Messages */}
        {(!provider.is_active || provider.health_status === 'unhealthy' || (provider.credential_count ?? 0) === 0) && (
          <div className="space-y-3">
            {!provider.is_active && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2"><AlertCircle className="h-4 w-4 text-theme-warning" /><span className="text-sm text-theme-warning">Provider is currently inactive</span></div>
              </div>
            )}
            {provider.health_status === 'unhealthy' && (
              <div className="p-4 bg-theme-error/10 border border-theme-error/20 rounded-lg">
                <div className="flex items-center gap-2"><AlertCircle className="h-4 w-4 text-theme-error" /><span className="text-sm text-theme-error">Provider health check failed</span></div>
              </div>
            )}
            {(provider.credential_count ?? 0) === 0 && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2"><Key className="h-4 w-4 text-theme-warning" /><span className="text-sm text-theme-warning">No credentials configured. Add credentials to start using this provider.</span></div>
              </div>
            )}
          </div>
        )}

        {/* Main Content Tabs */}
        <Tabs defaultValue="overview" className="space-y-4">
          <TabsList className="w-full justify-start overflow-x-auto">
            <TabsTrigger value="overview" className="whitespace-nowrap">Overview</TabsTrigger>
            <TabsTrigger value="capabilities" className="whitespace-nowrap">Capabilities</TabsTrigger>
            <TabsTrigger value="credentials" className="whitespace-nowrap">Credentials ({provider.credential_count ?? 0})</TabsTrigger>
            <TabsTrigger value="models" className="whitespace-nowrap">Models ({provider.model_count ?? 0})</TabsTrigger>
          </TabsList>

          <TabsContent value="overview"><ProviderOverviewTab provider={provider} /></TabsContent>
          <TabsContent value="capabilities"><ProviderMetricsTab provider={provider} /></TabsContent>
          <TabsContent value="credentials">
            <ProviderCredentialsTab
              credentials={provider.credentials || []}
              canManageProviders={canManageProviders}
              onEdit={handleEdit}
            />
          </TabsContent>
          <TabsContent value="models">
            <ProviderModelsTab
              provider={provider}
              canManageProviders={canManageProviders}
              syncing={syncing}
              onSyncModels={handleSyncModels}
            />
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};
