import { useState, useEffect, useRef } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Plus, Settings, CheckCircle, XCircle,
  AlertTriangle, MoreVertical, RefreshCw,
  FolderGit2, Users, Activity, GitBranch, Loader2,
  Trash2, TestTube, ExternalLink
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { GitProviderModal } from '@/features/git-providers/components/GitProviderModal';
import { GitProviderDetail } from '@/features/git-providers/types';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface GitProvider {
  id: string;
  name: string;
  type: 'github' | 'gitlab' | 'gitea' | 'bitbucket';
  apiUrl: string;
  status: 'connected' | 'error' | 'disconnected';
  isDefault: boolean;
  stats: {
    repositories: number;
    organizations: number;
    webhooksActive: number;
  };
  lastSync?: string;
  error?: string;
}

export function GitProvidersPage() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const { showNotification } = useNotifications();
  const [providers, setProviders] = useState<GitProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingProvider, setEditingProvider] = useState<GitProviderDetail | null>(null);
  const [syncing, setSyncing] = useState<string | null>(null);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [testing, setTesting] = useState<string | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setOpenMenuId(null);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const pageActions: PageAction[] = [
    {
      id: 'add-provider',
      label: 'Add Provider',
      onClick: () => {
        setEditingProvider(null);
        setIsModalOpen(true);
      },
      variant: 'primary',
      icon: Plus
    }
  ];

  const fetchProviders = async () => {
    try {
      setLoading(true);
      const gitProviders = await gitProvidersApi.getProviders();

      const mappedProviders: GitProvider[] = gitProviders.map((p: {
        id: string;
        name: string;
        provider_type?: string;
        base_url?: string;
        api_url?: string;
        status?: string;
        is_default?: boolean;
        repositories_count?: number;
        organizations_count?: number;
        webhooks_count?: number;
        last_synced_at?: string;
        error_message?: string;
      }) => ({
        id: p.id,
        name: p.name,
        type: mapProviderType(p.provider_type),
        apiUrl: p.base_url || p.api_url || '',
        status: mapStatus(p.status),
        isDefault: p.is_default || false,
        stats: {
          repositories: p.repositories_count || 0,
          organizations: p.organizations_count || 0,
          webhooksActive: p.webhooks_count || 0
        },
        lastSync: p.last_synced_at ? formatTimeAgo(p.last_synced_at) : undefined,
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

  // Handle URL parameter for editing (only for direct URL access, not button clicks)
  useEffect(() => {
    const loadProviderForEdit = async () => {
      // Skip if modal is already open (user clicked a button)
      if (isModalOpen) return;

      if (id && id !== 'new') {
        try {
          const provider = await gitProvidersApi.getProvider(id);
          setEditingProvider(provider);
          setIsModalOpen(true);
        } catch (error) {
          showNotification('Failed to load provider', 'error');
          navigate('/app/automation/git');
        }
      } else if (id === 'new') {
        setEditingProvider(null);
        setIsModalOpen(true);
      }
    };
    loadProviderForEdit();
  }, [id, navigate, showNotification, isModalOpen]);

  const handleModalClose = () => {
    setIsModalOpen(false);
    setEditingProvider(null);
    if (id) {
      navigate('/app/automation/git');
    }
  };

  const handleModalSuccess = () => {
    setIsModalOpen(false);
    setEditingProvider(null);
    showNotification(editingProvider ? 'Provider updated' : 'Provider created', 'success');
    if (id) {
      navigate('/app/automation/git');
    }
    // Reload providers without full page refresh
    fetchProviders();
  };

  const handleEditProvider = async (providerId: string) => {
    try {
      const provider = await gitProvidersApi.getProvider(providerId);
      setEditingProvider(provider);
      setIsModalOpen(true);
    } catch (error) {
      showNotification('Failed to load provider', 'error');
    }
  };

  const handleSyncProvider = async (providerId: string) => {
    setSyncing(providerId);
    try {
      // Find a credential for this provider to sync
      const credentials = await gitProvidersApi.getCredentials(providerId);
      if (credentials.length > 0) {
        await gitProvidersApi.syncRepositories(providerId, credentials[0].id);
        showNotification('Repositories synced successfully', 'success');
      } else {
        showNotification('No credentials found. Add credentials first.', 'warning');
      }
    } catch (error) {
      showNotification('Failed to sync repositories', 'error');
    } finally {
      setSyncing(null);
    }
  };

  const handleTestConnection = async (providerId: string) => {
    setTesting(providerId);
    setOpenMenuId(null);
    try {
      const credentials = await gitProvidersApi.getCredentials(providerId);
      if (credentials.length > 0) {
        const result = await gitProvidersApi.testCredential(providerId, credentials[0].id);
        if (result.success) {
          showNotification('Connection test successful', 'success');
        } else {
          showNotification(result.error || 'Connection test failed', 'error');
        }
      } else {
        showNotification('No credentials found. Add credentials first.', 'warning');
      }
    } catch (error) {
      showNotification('Failed to test connection', 'error');
    } finally {
      setTesting(null);
    }
  };

  const handleDeleteProvider = async (providerId: string) => {
    setOpenMenuId(null);
    if (!window.confirm('Are you sure you want to delete this provider? This will remove all associated credentials and repositories.')) {
      return;
    }
    try {
      await gitProvidersApi.deleteProvider(providerId);
      showNotification('Provider deleted successfully', 'success');
      setProviders(providers.filter(p => p.id !== providerId));
    } catch (error) {
      showNotification('Failed to delete provider', 'error');
    }
  };

  const handleViewRepositories = (providerId: string) => {
    setOpenMenuId(null);
    navigate(`/app/automation/repositories?provider=${providerId}`);
  };

  const mapProviderType = (type?: string): GitProvider['type'] => {
    switch (type?.toLowerCase()) {
      case 'github': return 'github';
      case 'gitlab': return 'gitlab';
      case 'gitea': return 'gitea';
      case 'bitbucket': return 'bitbucket';
      default: return 'github';
    }
  };

  const mapStatus = (status?: string): GitProvider['status'] => {
    switch (status?.toLowerCase()) {
      case 'active': case 'connected': return 'connected';
      case 'error': return 'error';
      default: return 'disconnected';
    }
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

  const getProviderLogo = (type: GitProvider['type']) => {
    switch (type) {
      case 'github':
        return (
          <div className="w-10 h-10 bg-black dark:bg-white rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white dark:text-theme-primary" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
            </svg>
          </div>
        );
      case 'gitlab':
        return (
          <div className="w-10 h-10 bg-theme-warning rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
              <path d="M22.65 14.39L12 22.13 1.35 14.39a.84.84 0 0 1-.3-.94l1.22-3.78 2.44-7.51A.42.42 0 0 1 4.82 2a.43.43 0 0 1 .58 0 .42.42 0 0 1 .11.18l2.44 7.49h8.1l2.44-7.51A.42.42 0 0 1 18.6 2a.43.43 0 0 1 .58 0 .42.42 0 0 1 .11.18l2.44 7.51L23 13.45a.84.84 0 0 1-.35.94z"/>
            </svg>
          </div>
        );
      case 'gitea':
        return (
          <div className="w-10 h-10 bg-theme-success rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-lg">G</span>
          </div>
        );
      case 'bitbucket':
        return (
          <div className="w-10 h-10 bg-theme-info rounded-lg flex items-center justify-center">
            <span className="text-white font-bold text-lg">B</span>
          </div>
        );
    }
  };

  const getStatusBadge = (status: GitProvider['status']) => {
    switch (status) {
      case 'connected':
        return (
          <span className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-success/10 text-theme-success ">
            <CheckCircle className="w-3 h-3" />
            Connected
          </span>
        );
      case 'error':
        return (
          <span className="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-danger/10 text-theme-danger ">
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

  if (loading) {
    return (
      <PageContainer
        title="Git Providers"
        description="Manage connections to GitHub, GitLab, Gitea, and other git providers"
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
      title="Git Providers"
      description="Manage connections to GitHub, GitLab, Gitea, and other git providers"
      actions={pageActions}
    >
      {/* Provider Cards */}
      <div className="space-y-4">
        {providers.length === 0 ? (
          <div className="bg-theme-surface border border-theme rounded-lg p-8 text-center">
            <GitBranch className="w-12 h-12 mx-auto mb-3 text-theme-secondary opacity-50" />
            <p className="text-theme-secondary">No git providers configured</p>
            <p className="text-sm text-theme-tertiary mt-1">
              Add a git provider to connect your repositories
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
                    {provider.apiUrl}
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
                  onClick={() => handleSyncProvider(provider.id)}
                  disabled={syncing === provider.id}
                  className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary disabled:opacity-50"
                  title="Sync repositories"
                >
                  <RefreshCw className={`w-4 h-4 ${syncing === provider.id ? 'animate-spin' : ''}`} />
                </button>
                <button
                  onClick={() => handleEditProvider(provider.id)}
                  className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
                  title="Settings"
                >
                  <Settings className="w-4 h-4" />
                </button>
                <div className="relative" ref={openMenuId === provider.id ? menuRef : null}>
                  <button
                    onClick={() => setOpenMenuId(openMenuId === provider.id ? null : provider.id)}
                    className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
                  >
                    <MoreVertical className="w-4 h-4" />
                  </button>
                  {openMenuId === provider.id && (
                    <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10 py-1">
                      <button
                        onClick={() => handleTestConnection(provider.id)}
                        disabled={testing === provider.id}
                        className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle disabled:opacity-50"
                      >
                        <TestTube className={`w-4 h-4 ${testing === provider.id ? 'animate-pulse' : ''}`} />
                        {testing === provider.id ? 'Testing...' : 'Test Connection'}
                      </button>
                      <button
                        onClick={() => handleViewRepositories(provider.id)}
                        className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
                      >
                        <FolderGit2 className="w-4 h-4" />
                        View Repositories
                      </button>
                      {provider.apiUrl && (
                        <a
                          href={provider.apiUrl.replace('/api/v1', '').replace('/api', '')}
                          target="_blank"
                          rel="noopener noreferrer"
                          onClick={() => setOpenMenuId(null)}
                          className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
                        >
                          <ExternalLink className="w-4 h-4" />
                          Open Provider
                        </a>
                      )}
                      <div className="border-t border-theme my-1" />
                      <button
                        onClick={() => handleDeleteProvider(provider.id)}
                        className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-danger hover:bg-theme-danger/10"
                      >
                        <Trash2 className="w-4 h-4" />
                        Delete Provider
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>

            {provider.status === 'connected' && (
              <div className="grid grid-cols-3 gap-4 mt-4 pt-4 border-t border-theme">
                <div className="flex items-center gap-2">
                  <FolderGit2 className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Repositories</p>
                    <p className="font-semibold text-theme-primary">{provider.stats.repositories}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Users className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Organizations</p>
                    <p className="font-semibold text-theme-primary">{provider.stats.organizations}</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Activity className="w-4 h-4 text-theme-secondary" />
                  <div>
                    <p className="text-sm text-theme-secondary">Active Webhooks</p>
                    <p className="font-semibold text-theme-primary">{provider.stats.webhooksActive}</p>
                  </div>
                </div>
              </div>
            )}

            {provider.lastSync && (
              <p className="text-xs text-theme-secondary mt-3">
                Last synced {provider.lastSync}
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
            { name: 'GitHub', type: 'github' as const },
            { name: 'GitLab', type: 'gitlab' as const },
            { name: 'Gitea', type: 'gitea' as const },
            { name: 'Bitbucket', type: 'bitbucket' as const }
          ].map((option) => (
            <button
              key={option.type}
              onClick={() => {
                setEditingProvider(null);
                setIsModalOpen(true);
              }}
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

      {/* Edit/Create Modal */}
      <GitProviderModal
        isOpen={isModalOpen}
        onClose={handleModalClose}
        onSuccess={handleModalSuccess}
        provider={editingProvider}
      />
    </PageContainer>
  );
}

export default GitProvidersPage;
