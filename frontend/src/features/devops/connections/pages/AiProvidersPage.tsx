import { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Brain, Plus, Settings, CheckCircle, XCircle,
  AlertTriangle, MoreVertical, RefreshCw,
  Zap, DollarSign, Loader2
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { providersApi } from '@/shared/services/ai/ProvidersApiService';
import { EditProviderModal } from '@/features/ai/providers/components/EditProviderModal';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface AiProvider {
  id: string;
  name: string;
  slug: string;
  type: 'openai' | 'anthropic' | 'google' | 'azure' | 'custom';
  status: 'connected' | 'error' | 'disconnected';
  isDefault: boolean;
  models: string[];
  usage: {
    requests: number;
    tokens: number;
    cost: number;
  };
  lastUsed?: string;
  error?: string;
}

export function AiProvidersPage() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const { showNotification } = useNotifications();
  const [providers, setProviders] = useState<AiProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingProviderId, setEditingProviderId] = useState<string | null>(null);
  const [testing, setTesting] = useState<string | null>(null);

  const pageActions: PageAction[] = [
    {
      id: 'add-provider',
      label: 'Add Provider',
      onClick: () => navigate('/app/connections/ai/new'),
      variant: 'primary',
      icon: Plus
    }
  ];

  const fetchProviders = async () => {
    try {
      setLoading(true);
      const response = await providersApi.getProviders();
      const items = response.items || [];

      const mappedProviders: AiProvider[] = items.map((p: {
        id: string;
        name: string;
        provider_type: string;
        is_active?: boolean;
        is_default?: boolean;
        health_status?: string;
        available_models?: string[];
        total_requests?: number;
        total_tokens?: number;
        total_cost_usd?: number;
        last_used_at?: string;
        error_message?: string;
      }) => ({
        id: p.id,
        name: p.name,
        slug: p.provider_type,
        type: mapProviderType(p.provider_type),
        status: mapStatus(p.is_active, p.health_status),
        isDefault: p.is_default || false,
        models: p.available_models || [],
        usage: {
          requests: p.total_requests || 0,
          tokens: p.total_tokens || 0,
          cost: p.total_cost_usd || 0
        },
        lastUsed: p.last_used_at ? formatTimeAgo(p.last_used_at) : undefined,
        error: p.error_message
      }));

      setProviders(mappedProviders);
    } catch (error) {
      // Keep empty state on error
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProviders();
  }, []);

  // Handle URL parameter for editing
  useEffect(() => {
    if (id && id !== 'new') {
      setEditingProviderId(id);
      setIsModalOpen(true);
    }
  }, [id]);

  const handleModalClose = () => {
    setIsModalOpen(false);
    setEditingProviderId(null);
    if (id) {
      navigate('/app/ai/providers');
    }
  };

  const handleModalSuccess = () => {
    setIsModalOpen(false);
    setEditingProviderId(null);
    // Note: EditProviderModal already shows a success notification, so don't duplicate it here
    if (id) {
      navigate('/app/ai/providers');
    }
    // Reload providers without full page refresh
    fetchProviders();
  };

  const handleEditProvider = (providerId: string) => {
    navigate(`/app/ai/providers/${providerId}`);
  };

  const handleTestConnection = async (providerId: string) => {
    setTesting(providerId);
    try {
      const result = await providersApi.testConnection(providerId);
      if (result.success) {
        showNotification('Connection successful', 'success');
      } else {
        showNotification(result.error || 'Connection test failed', 'error');
      }
    } catch (error) {
      showNotification('Failed to test connection', 'error');
    } finally {
      setTesting(null);
    }
  };

  const mapProviderType = (type: string): AiProvider['type'] => {
    switch (type.toLowerCase()) {
      case 'openai': return 'openai';
      case 'anthropic': return 'anthropic';
      case 'google': case 'gemini': return 'google';
      case 'azure': case 'azure_openai': return 'azure';
      default: return 'custom';
    }
  };

  const mapStatus = (isActive?: boolean, healthStatus?: string): AiProvider['status'] => {
    if (!isActive) return 'disconnected';
    if (healthStatus === 'error' || healthStatus === 'unhealthy') return 'error';
    return 'connected';
  };

  const formatTimeAgo = (dateStr: string): string => {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  const getProviderLogo = (type: AiProvider['type']) => {
    switch (type) {
      case 'openai':
        return (
          <div className="w-10 h-10 bg-black rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-lg">⬡</span>
          </div>
        );
      case 'anthropic':
        return (
          <div className="w-10 h-10 bg-theme-warning/10 rounded-lg flex items-center justify-center">
            <span className="text-theme-warning font-bold text-lg">A</span>
          </div>
        );
      case 'google':
        return (
          <div className="w-10 h-10 bg-theme-info/10 rounded-lg flex items-center justify-center">
            <span className="text-theme-info font-bold text-lg">G</span>
          </div>
        );
      case 'azure':
        return (
          <div className="w-10 h-10 bg-theme-info rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-lg">⬡</span>
          </div>
        );
      default:
        return (
          <div className="w-10 h-10 bg-theme-bg-subtle rounded-lg flex items-center justify-center">
            <Brain className="w-5 h-5 text-theme-secondary" />
          </div>
        );
    }
  };

  const getStatusBadge = (status: AiProvider['status']) => {
    switch (status) {
      case 'connected':
        return (
          <span className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-success/10 text-theme-success">
            <CheckCircle className="w-3 h-3" />
            Connected
          </span>
        );
      case 'error':
        return (
          <span className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-danger/10 text-theme-danger">
            <XCircle className="w-3 h-3" />
            Error
          </span>
        );
      case 'disconnected':
        return (
          <span className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-bg-subtle text-theme-secondary">
            <AlertTriangle className="w-3 h-3" />
            Disconnected
          </span>
        );
    }
  };

  const formatNumber = (num: number) => {
    if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
    if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
    return num.toString();
  };

  if (loading) {
    return (
      <PageContainer
        title="AI Providers"
        description="Manage connections to AI providers like OpenAI, Anthropic, and more"
        actions={pageActions}
      >
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="AI Providers"
      description="Manage connections to AI providers like OpenAI, Anthropic, and more"
      actions={pageActions}
    >
      {/* Provider Cards */}
      <div className="space-y-4">
        {providers.length === 0 ? (
          <div className="bg-theme-surface border border-theme rounded-lg p-8 text-center">
            <Brain className="w-12 h-12 mx-auto mb-3 text-theme-secondary opacity-50" />
            <p className="text-theme-secondary">No AI providers configured</p>
            <p className="text-sm text-theme-tertiary mt-1">
              Add an AI provider to enable AI-powered features
            </p>
          </div>
        ) : (
          providers.map((provider) => (
          <div
            key={provider.id}
            className={`bg-theme-surface border rounded-lg p-5 ${
              provider.status === 'error' ? 'border-theme-danger' : 'border-theme'
            }`}
          >
            <div className="flex items-start justify-between">
              <div className="flex items-start gap-4">
                {getProviderLogo(provider.type)}
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="font-semibold text-theme-primary">{provider.name}</h3>
                    {provider.isDefault && (
                      <span className="px-2 py-0.5 text-xs rounded-full bg-theme-primary text-white">
                        Default
                      </span>
                    )}
                    {getStatusBadge(provider.status)}
                  </div>
                  <p className="text-sm text-theme-secondary mt-1">
                    {provider.models.join(', ')}
                  </p>
                  {provider.error && (
                    <p className="text-sm text-theme-danger mt-2 flex items-center gap-1">
                      <AlertTriangle className="w-4 h-4" />
                      {provider.error}
                    </p>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => handleTestConnection(provider.id)}
                  disabled={testing === provider.id}
                  className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary disabled:opacity-50"
                  title="Test connection"
                >
                  <RefreshCw className={`w-4 h-4 ${testing === provider.id ? 'animate-spin' : ''}`} />
                </button>
                <button
                  onClick={() => handleEditProvider(provider.id)}
                  className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
                  title="Settings"
                >
                  <Settings className="w-4 h-4" />
                </button>
                <button className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary">
                  <MoreVertical className="w-4 h-4" />
                </button>
              </div>
            </div>

            {provider.status === 'connected' && (
              <div className="grid grid-cols-3 gap-4 mt-4 pt-4 border-t border-theme">
                <div className="flex items-center gap-2">
                  <Zap className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Requests</p>
                    <p className="font-semibold text-theme-primary">{formatNumber(provider.usage.requests)}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Brain className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Tokens</p>
                    <p className="font-semibold text-theme-primary">{formatNumber(provider.usage.tokens)}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <DollarSign className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Cost (30d)</p>
                    <p className="font-semibold text-theme-primary">${provider.usage.cost.toFixed(2)}</p>
                  </div>
                </div>
              </div>
            )}

            {provider.lastUsed && (
              <p className="text-xs text-theme-secondary mt-3">
                Last used {provider.lastUsed}
              </p>
            )}
          </div>
          ))
        )}
      </div>

      {/* Add Provider Options */}
      <div className="mt-8">
        <h3 className="font-semibold text-theme-primary mb-4">Add More Providers</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { name: 'OpenAI', type: 'openai' as const },
            { name: 'Anthropic', type: 'anthropic' as const },
            { name: 'Google AI', type: 'google' as const },
            { name: 'Azure OpenAI', type: 'azure' as const }
          ].map((option) => (
            <button
              key={option.type}
              onClick={() => navigate(`/app/ai/providers/new?type=${option.type}`)}
              className="flex items-center gap-3 p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors group text-left"
            >
              {getProviderLogo(option.type)}
              <div className="flex-1">
                <p className="font-medium text-theme-primary">{option.name}</p>
                <p className="text-xs text-theme-secondary">Add provider</p>
              </div>
              <Plus className="w-4 h-4 text-theme-secondary opacity-0 group-hover:opacity-100 transition-opacity" />
            </button>
          ))}
        </div>
      </div>

      {/* Edit Provider Modal */}
      {editingProviderId && (
        <EditProviderModal
          isOpen={isModalOpen}
          onClose={handleModalClose}
          onSuccess={handleModalSuccess}
          providerId={editingProviderId}
        />
      )}
    </PageContainer>
  );
}

export default AiProvidersPage;
