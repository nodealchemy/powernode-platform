import React, { useState, useEffect } from 'react';
import { 
  Settings, 
  Zap, 
  AlertCircle, 
  ExternalLink, 
  Edit, 
  Trash2,
  TestTube,
  RefreshCw,
  Star,
  Key,
  Activity
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { Avatar } from '@/shared/components/ui/Avatar';
import { providersApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { AiProvider, AiProviderCredential } from '@/shared/types/ai';

export interface ProviderDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  providerId: string;
  onUpdate?: () => void;
  onEdit?: (providerId: string) => void;
  onDelete?: (providerId: string) => void;
}

export const ProviderDetailModal: React.FC<ProviderDetailModalProps> = ({
  isOpen,
  onClose,
  providerId,
  onUpdate,
  onEdit,
  onDelete
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  
  const [provider, setProvider] = useState<AiProvider | null>(null);
  const [loading, setLoading] = useState(false);
  const [testing, setTesting] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Check permissions
  const canManageProviders = currentUser?.permissions?.includes('ai.providers.update') || false;
  const canDeleteProviders = currentUser?.permissions?.includes('ai.providers.delete') || false;
  const canTestCredentials = currentUser?.permissions?.includes('ai.providers.test') || false;

  // Load provider details
  const loadProvider = async () => {
    if (!providerId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);
      const response = await providersApi.getProvider(providerId);
      // Response is already unwrapped by BaseApiService
      setProvider(response as AiProvider);
    } catch (error) {
      console.error('Failed to load provider:', error);
      setError('Failed to load provider details. Please try again.');
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load provider details'
      });
    } finally {
      setLoading(false);
    }
  };

  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  useEffect(() => {
    if (isOpen && providerId) {
      loadProvider();
    }
  }, [isOpen, providerId]);

  // Handle test connection
  const handleTestConnection = async () => {
    if (!provider || !canTestCredentials) return;

    try {
      setTesting(true);
      const response = await providersApi.testConnection(provider.id);
      // Response is already unwrapped by BaseApiService

      const responseTime = response.response_time_ms;
      const timeDisplay = responseTime !== undefined && responseTime !== null
        ? `${responseTime}ms`
        : 'N/A';

      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Connection Test',
        message: response.success
          ? `Connection successful (${timeDisplay})`
          : `Connection failed: ${response.error || 'Unknown error'}`,
        details: response.success ? {
          responseTime: timeDisplay,
          providerInfo: response.provider_info,
          modelInfo: response.model_info
        } : {
          errorCode: response.error_code,
          responseTime: timeDisplay
        }
      });

      if (response.success) {
        loadProvider(); // Reload to get updated status
        onUpdate?.();
      }
    } catch (error) {
      console.error('Failed to test connection:', error);
      addNotification({
        type: 'error',
        title: 'Test Failed',
        message: 'Failed to test provider connection'
      });
    } finally {
      setTesting(false);
    }
  };

  // Handle sync models
  const handleSyncModels = async () => {
    if (!provider || !canManageProviders) return;

    try {
      setSyncing(true);
      await providersApi.syncModels(provider.id);
      
      addNotification({
        type: 'success',
        title: 'Models Synced',
        message: 'Provider models updated successfully'
      });
      
      loadProvider(); // Reload to get updated model count
      onUpdate?.();
    } catch (error) {
      console.error('Failed to sync models:', error);
      addNotification({
        type: 'error',
        title: 'Sync Failed',
        message: 'Failed to sync provider models'
      });
    } finally {
      setSyncing(false);
    }
  };

  // Handle edit
  const handleEdit = () => {
    if (!provider) return;
    onEdit?.(provider.id);
    onClose();
  };

  // Handle delete
  const handleDelete = () => {
    if (!provider) return;
    if (confirm(`Are you sure you want to delete the provider "${provider.name}"? This action cannot be undone.`)) {
      onDelete?.(provider.id);
      onClose();
    }
  };

  // Utility functions
  const getProviderIcon = (slug: string) => {
    const iconMap: Record<string, string> = {
      'ollama': '🦙',
      'openai': '🤖',
      'anthropic': '🧠',
      'stability-ai': '🎨',
      'mistral': '🌪️',
      'cohere': '💫',
      'huggingface': '🤗',
      'replicate': '🔄',
      'together': '🤝'
    };
    return iconMap[slug] || '⚙️';
  };

  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy':
        return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'unhealthy':
        return <Badge variant="danger" size="sm">Unhealthy</Badge>;
      case 'inactive':
        return <Badge variant="secondary" size="sm">Inactive</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getProviderTypeBadge = (type: string) => {
    const typeMap: Record<string, { label: string; variant: 'default' | 'secondary' | 'outline' }> = {
      'text_generation': { label: 'Text', variant: 'default' },
      'image_generation': { label: 'Image', variant: 'secondary' },
      'code_execution': { label: 'Code', variant: 'outline' },
      'embedding': { label: 'Embedding', variant: 'outline' },
      'multimodal': { label: 'Multimodal', variant: 'default' }
    };

    const config = typeMap[type] || { label: type, variant: 'outline' as const };
    return <Badge variant={config.variant} size="sm">{config.label}</Badge>;
  };

  const formatModelSize = (sizeBytes: number): string => {
    if (!sizeBytes) return 'Unknown';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let size = sizeBytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(1)} ${units[unitIndex]}`;
  };

  // Modal footer with actions
  const footer = (
    <div className="flex gap-3">
      <Button
        variant="outline"
        onClick={onClose}
      >
        Close
      </Button>
      {canTestCredentials && provider && (provider.credential_count ?? 0) > 0 && (
        <Button
          variant="outline"
          onClick={handleTestConnection}
          disabled={testing}
        >
          <Zap className={`h-4 w-4 mr-2 ${testing ? 'animate-pulse' : ''}`} />
          {testing ? 'Testing...' : 'Test Connection'}
        </Button>
      )}
      {canManageProviders && provider && (
        <>
          <Button
            variant="outline"
            onClick={handleSyncModels}
            disabled={syncing}
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${syncing ? 'animate-spin' : ''}`} />
            {syncing ? 'Syncing...' : 'Sync Models'}
          </Button>
          <Button
            variant="outline"
            onClick={handleEdit}
          >
            <Edit className="h-4 w-4 mr-2" />
            Edit Settings
          </Button>
        </>
      )}
      {canDeleteProviders && provider && (
        <Button
          variant="danger"
          onClick={handleDelete}
        >
          <Trash2 className="h-4 w-4 mr-2" />
          Delete
        </Button>
      )}
    </div>
  );

  // Loading state
  if (loading || !provider) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Loading Provider..."
        maxWidth="3xl"
        icon={<Settings />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Modal>
    );
  }

  // Error state
  if (error) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Error Loading Provider"
        maxWidth="md"
        icon={<Settings />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="text-center py-8">
          <p className="text-theme-error">{error}</p>
          <Button 
            variant="outline" 
            onClick={loadProvider}
            className="mt-4"
          >
            Try Again
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <div className="flex items-center gap-3">
          <Avatar className="h-8 w-8">
            <span className="text-lg">{getProviderIcon(provider.slug)}</span>
          </Avatar>
          {provider.name}
        </div>
      }
      subtitle={provider.description}
      maxWidth="3xl"
      variant="centered"
      icon={<Settings />}
      footer={footer}
    >
      <div className="space-y-4 overflow-hidden">
        {/* Header Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Status</p>
                  {getHealthStatusBadge(provider.health_status)}
                </div>
                <Activity className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Type</p>
                  {getProviderTypeBadge(provider.provider_type)}
                </div>
                <Settings className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Priority</p>
                  <div className="flex items-center gap-1">
                    <p className="text-lg font-semibold text-theme-primary">#{provider.priority_order}</p>
                    {provider.priority_order <= 3 && <Star className="h-4 w-4 text-theme-warning fill-current" />}
                  </div>
                </div>
                <Star className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Models</p>
                  <p className="text-lg font-semibold text-theme-primary">{provider.model_count}</p>
                </div>
                <TestTube className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Warning Messages */}
        {(!provider.is_active || provider.health_status === 'unhealthy' || (provider.credential_count ?? 0) === 0) && (
          <div className="space-y-3">
            {!provider.is_active && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2">
                  <AlertCircle className="h-4 w-4 text-theme-warning" />
                  <span className="text-sm text-theme-warning">Provider is currently inactive</span>
                </div>
              </div>
            )}

            {provider.health_status === 'unhealthy' && (
              <div className="p-4 bg-theme-error/10 border border-theme-error/20 rounded-lg">
                <div className="flex items-center gap-2">
                  <AlertCircle className="h-4 w-4 text-theme-error" />
                  <span className="text-sm text-theme-error">Provider health check failed</span>
                </div>
              </div>
            )}

            {(provider.credential_count ?? 0) === 0 && (
              <div className="p-4 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
                <div className="flex items-center gap-2">
                  <Key className="h-4 w-4 text-theme-warning" />
                  <span className="text-sm text-theme-warning">No credentials configured. Add credentials to start using this provider.</span>
                </div>
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

          <TabsContent value="overview" className="space-y-4">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <Card>
                <CardHeader title="Provider Information" />
                <CardContent className="space-y-4">
                  <div>
                    <label className="text-sm font-medium text-theme-muted">Name</label>
                    <p className="mt-1 text-theme-primary">{provider.name}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Slug</label>
                    <p className="mt-1 text-theme-primary">{provider.slug}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Description</label>
                    <p className="mt-1 text-theme-primary break-words">{provider.description}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Base URL</label>
                    <p className="mt-1 text-theme-primary font-mono text-xs break-all overflow-hidden">{provider.api_base_url}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Active</label>
                    <p className="mt-1 text-theme-primary">{provider.is_active ? 'Yes' : 'No'}</p>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader title="External Links" />
                <CardContent className="space-y-4">
                  {provider.documentation_url && (
                    <div>
                      <label className="text-sm font-medium text-theme-muted">Documentation</label>
                      <div className="mt-1">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => window.open(provider.documentation_url, '_blank')}
                          className="flex items-center gap-1"
                        >
                          <ExternalLink className="h-3 w-3" />
                          View Documentation
                        </Button>
                      </div>
                    </div>
                  )}

                  {provider.status_url && (
                    <div>
                      <label className="text-sm font-medium text-theme-muted">Status Page</label>
                      <div className="mt-1">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => window.open(provider.status_url, '_blank')}
                          className="flex items-center gap-1"
                        >
                          <ExternalLink className="h-3 w-3" />
                          View Status
                        </Button>
                      </div>
                    </div>
                  )}

                  {!provider.documentation_url && !provider.status_url && (
                    <p className="text-theme-muted">No external links available</p>
                  )}
                </CardContent>
              </Card>
            </div>
          </TabsContent>

          <TabsContent value="capabilities" className="space-y-4">
            <Card>
              <CardHeader title="Provider Capabilities" />
              <CardContent>
                {provider.capabilities && provider.capabilities.length > 0 ? (
                  <div className="flex flex-wrap gap-2">
                    {provider.capabilities.map(capability => (
                      <Badge key={capability} variant="outline">
                        {capability.replace('_', ' ')}
                      </Badge>
                    ))}
                  </div>
                ) : (
                  <p className="text-theme-muted">No capabilities defined for this provider.</p>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="credentials" className="space-y-4">
            <Card>
              <CardHeader
                title="API Credentials"
                action={canManageProviders ? (
                  <Button variant="outline" onClick={handleEdit}>
                    <Key className="h-4 w-4 mr-2" />
                    Manage Credentials
                  </Button>
                ) : undefined}
              />
              <CardContent>
                {provider.account_credentials && provider.account_credentials.length > 0 ? (
                  <div className="space-y-3">
                    {provider.account_credentials.map((credential: AiProviderCredential) => (
                      <div
                        key={credential.id}
                        className="flex items-center justify-between p-3 border border-theme-border rounded-lg"
                      >
                        <div className="flex items-center gap-3">
                          <div className={`h-3 w-3 rounded-full ${
                            credential.health_status === 'healthy'
                              ? 'bg-theme-success'
                              : 'bg-theme-error'
                          }`} />
                          <div>
                            <p className="text-sm font-medium text-theme-primary">
                              {credential.name}
                              {credential.is_default && (
                                <span className="ml-2 px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">
                                  Default
                                </span>
                              )}
                            </p>
                            <div className="flex items-center gap-4 text-xs text-theme-muted">
                              <span>Status: {credential.health_status}</span>
                              {credential.last_used_at && (
                                <span>Last used: {new Date(credential.last_used_at).toLocaleDateString()}</span>
                              )}
                              {credential.consecutive_failures > 0 && (
                                <span className="text-theme-error">
                                  {credential.consecutive_failures} recent failures
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          {credential.is_active ? (
                            <Badge variant="success" size="sm">Active</Badge>
                          ) : (
                            <Badge variant="secondary" size="sm">Inactive</Badge>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-8">
                    <Key className="h-8 w-8 mx-auto text-theme-muted mb-2" />
                    <p className="text-sm text-theme-muted">
                      No credentials configured for this provider
                    </p>
                    {canManageProviders && (
                      <p className="text-sm text-theme-muted mt-1">
                        Click "Manage Credentials" to add credentials
                      </p>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="models" className="space-y-4">
            <Card>
              <CardHeader
                title="Available Models"
                action={canManageProviders ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={handleSyncModels}
                    disabled={syncing}
                  >
                    <RefreshCw className={`h-4 w-4 mr-2 ${syncing ? 'animate-spin' : ''}`} />
                    {syncing ? 'Syncing...' : 'Sync Models'}
                  </Button>
                ) : undefined}
              />
              <CardContent>
                <div className="mb-4">
                  <p className="text-theme-primary font-medium">
                    {provider.model_count ?? 0} model{(provider.model_count ?? 0) !== 1 ? 's' : ''} available
                  </p>
                  <p className="text-sm text-theme-muted">
                    Models are synced from the provider API
                  </p>
                </div>

                {provider.supported_models && provider.supported_models.length > 0 ? (
                  <div className="space-y-3">
                    {provider.supported_models.map((model, index) => (
                      <div
                        key={model.id || index}
                        className="p-4 border border-theme-border rounded-lg hover:bg-theme-surface-hover transition-colors"
                      >
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-2">
                              <h4 className="font-medium text-theme-primary">{model.name}</h4>
                              <Badge variant="outline" size="sm">{model.id}</Badge>
                            </div>

                            {model.description && (
                              <p className="text-sm text-theme-muted mb-2">{model.description}</p>
                            )}

                            <div className="flex flex-wrap gap-2 text-xs text-theme-muted">
                              {model.context_length && (
                                <span className="px-2 py-1 bg-theme-surface rounded">
                                  Context: {typeof model.context_length === 'string' ? model.context_length : `${model.context_length} tokens`}
                                </span>
                              )}
                              {model.parameter_size && (
                                <span className="px-2 py-1 bg-theme-surface rounded">
                                  Parameters: {model.parameter_size}
                                </span>
                              )}
                              {model.family && (
                                <span className="px-2 py-1 bg-theme-surface rounded">
                                  Family: {model.family}
                                </span>
                              )}
                              {model.quantization_level && (
                                <span className="px-2 py-1 bg-theme-surface rounded">
                                  Quantization: {model.quantization_level}
                                </span>
                              )}
                              {model.size_bytes && (
                                <span className="px-2 py-1 bg-theme-surface rounded">
                                  Size: {formatModelSize(model.size_bytes)}
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="text-center py-8">
                    <TestTube className="h-8 w-8 text-theme-muted mx-auto mb-2" />
                    <p className="text-theme-muted">No models available</p>
                    <p className="text-sm text-theme-muted">
                      {canManageProviders ? 'Click "Sync Models" to fetch available models' : 'Contact an administrator to sync models'}
                    </p>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};