import { useState, useEffect, useRef } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Plus, Settings, CheckCircle, XCircle,
  AlertTriangle, MoreVertical,
  FolderGit2, Users, Activity, GitBranch, Loader2,
  Trash2, TestTube, ExternalLink, ChevronDown, ChevronRight,
  Key, Shield, Webhook, Cpu
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { gitProvidersApi } from '@/features/devops/git/services/gitProvidersApi';
import { GitProviderModal } from '@/features/devops/git/components/GitProviderModal';
import { CredentialModal } from '@/features/devops/git/components/CredentialModal';
import { GitProviderDetail, GitCredential, AvailableProvider } from '@/features/devops/git/types';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';

interface GitProvider {
  id: string;
  name: string;
  slug: string;
  type: 'github' | 'gitlab' | 'gitea' | 'bitbucket';
  apiUrl: string;
  webUrl?: string;
  status: 'connected' | 'error' | 'disconnected';
  isDefault: boolean;
  description?: string;
  capabilities: string[];
  supportsOAuth: boolean;
  supportsPAT: boolean;
  supportsWebhooks: boolean;
  supportsDevOps: boolean;
  stats: {
    repositories: number;
    organizations: number;
    webhooksActive: number;
  };
  lastSync?: string;
  error?: string;
  credentialsCount: number;
}

export function GitProvidersPage() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [providers, setProviders] = useState<GitProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingProvider, setEditingProvider] = useState<GitProviderDetail | null>(null);
  const [selectedProviderType, setSelectedProviderType] = useState<'github' | 'gitlab' | 'gitea' | 'bitbucket' | undefined>(undefined);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [testing, setTesting] = useState<string | null>(null);
  const [expandedProviderId, setExpandedProviderId] = useState<string | null>(null);
  const [providerCredentials, setProviderCredentials] = useState<Record<string, GitCredential[]>>({});
  const [loadingCredentials, setLoadingCredentials] = useState<string | null>(null);
  const [credentialModalOpen, setCredentialModalOpen] = useState(false);
  const [credentialModalProvider, setCredentialModalProvider] = useState<AvailableProvider | null>(null);
  const [editingCredential, setEditingCredential] = useState<GitCredential | null>(null);
  const [credentialActionLoading, setCredentialActionLoading] = useState<string | null>(null);
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

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Git Providers' }
  ];

  const { refreshAction } = useRefreshAction({
    onRefresh: async () => {
      await fetchProviders();
      showNotification('Providers refreshed', 'success');
    },
    loading,
  });

  const pageActions: PageAction[] = [
    refreshAction,
    {
      id: 'add-provider',
      label: 'Add Provider',
      onClick: () => {
        setEditingProvider(null);
        setSelectedProviderType(undefined);
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
        slug?: string;
        provider_type?: string;
        base_url?: string;
        api_url?: string;
        api_base_url?: string;
        web_url?: string;
        web_base_url?: string;
        status?: string;
        is_default?: boolean;
        description?: string;
        capabilities?: string[];
        supports_oauth?: boolean;
        supports_pat?: boolean;
        supports_webhooks?: boolean;
        supports_devops?: boolean;
        repositories_count?: number;
        organizations_count?: number;
        webhooks_count?: number;
        last_synced_at?: string;
        error_message?: string;
        credentials_count?: number;
      }) => ({
        id: p.id,
        name: p.name,
        slug: p.slug || '',
        type: mapProviderType(p.provider_type),
        apiUrl: p.base_url || p.api_url || p.api_base_url || '',
        webUrl: p.web_url || p.web_base_url || '',
        status: mapStatus(p.status),
        isDefault: p.is_default || false,
        description: p.description || '',
        capabilities: p.capabilities || [],
        supportsOAuth: p.supports_oauth ?? true,
        supportsPAT: p.supports_pat ?? true,
        supportsWebhooks: p.supports_webhooks ?? true,
        supportsDevOps: p.supports_devops ?? false,
        stats: {
          repositories: p.repositories_count || 0,
          organizations: p.organizations_count || 0,
          webhooksActive: p.webhooks_count || 0
        },
        lastSync: p.last_synced_at ? formatTimeAgo(p.last_synced_at) : undefined,
        error: p.error_message,
        credentialsCount: p.credentials_count || 0
      }));

      setProviders(mappedProviders);
    } catch (_error) {
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
        } catch (_error) {
          showNotification('Failed to load provider', 'error');
          navigate('/app/devops/source-control');
        }
      } else if (id === 'new') {
        setEditingProvider(null);
        setIsModalOpen(true);
      }
    };
    loadProviderForEdit();
  }, [id, navigate, showNotification, isModalOpen]);

  const fetchCredentialsForProvider = async (providerId: string) => {
    setLoadingCredentials(providerId);
    try {
      const credentials = await gitProvidersApi.getCredentials(providerId);
      setProviderCredentials(prev => ({ ...prev, [providerId]: credentials }));
    } catch (_error) {
      showNotification('Failed to load credentials', 'error');
    } finally {
      setLoadingCredentials(null);
    }
  };

  const handleToggleExpand = async (providerId: string) => {
    if (expandedProviderId === providerId) {
      setExpandedProviderId(null);
    } else {
      setExpandedProviderId(providerId);
      // Fetch credentials if not already loaded
      if (!providerCredentials[providerId]) {
        await fetchCredentialsForProvider(providerId);
      }
    }
  };

  const handleModalClose = () => {
    setIsModalOpen(false);
    setEditingProvider(null);
    setSelectedProviderType(undefined);
    if (id) {
      navigate('/app/devops/source-control');
    }
  };

  const handleModalSuccess = () => {
    setIsModalOpen(false);
    setEditingProvider(null);
    setSelectedProviderType(undefined);
    showNotification(editingProvider ? 'Provider updated' : 'Provider created', 'success');
    if (id) {
      navigate('/app/devops/source-control');
    }
    // Reload providers without full page refresh
    fetchProviders();
  };

  const handleEditProvider = async (providerId: string) => {
    try {
      const provider = await gitProvidersApi.getProvider(providerId);
      setEditingProvider(provider);
      setIsModalOpen(true);
    } catch (_error) {
      showNotification('Failed to load provider', 'error');
    }
  };

  const handleTestConnection = async (providerId: string) => {
    setTesting(providerId);
    setOpenMenuId(null);
    try {
      const credentials = providerCredentials[providerId] || await gitProvidersApi.getCredentials(providerId);
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
    } catch (_error) {
      showNotification('Failed to test connection', 'error');
    } finally {
      setTesting(null);
    }
  };

  const handleDeleteProvider = (providerId: string) => {
    setOpenMenuId(null);
    confirm({
      title: 'Delete Git Provider',
      message: 'Are you sure you want to delete this provider? This will remove all associated credentials and repositories.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await gitProvidersApi.deleteProvider(providerId);
          showNotification('Provider deleted successfully', 'success');
          setProviders(providers.filter(p => p.id !== providerId));
          if (expandedProviderId === providerId) {
            setExpandedProviderId(null);
          }
        } catch (_error) {
          showNotification('Failed to delete provider', 'error');
        }
      },
    });
  };

  const handleViewRepositories = (providerId: string) => {
    setOpenMenuId(null);
    navigate(`/app/devops/source-control/repositories?provider=${providerId}`);
  };

  // Credential management handlers
  const handleAddCredential = (provider: GitProvider) => {
    const availableProvider: AvailableProvider = {
      id: provider.id,
      name: provider.name,
      slug: provider.slug,
      provider_type: provider.type,
      description: provider.description,
      supports_oauth: provider.supportsOAuth,
      supports_pat: provider.supportsPAT,
      supports_devops: provider.supportsDevOps,
      capabilities: provider.capabilities,
      configured: provider.credentialsCount > 0
    };
    setCredentialModalProvider(availableProvider);
    setEditingCredential(null);
    setCredentialModalOpen(true);
  };

  const handleEditCredential = (provider: GitProvider, credential: GitCredential) => {
    const availableProvider: AvailableProvider = {
      id: provider.id,
      name: provider.name,
      slug: provider.slug,
      provider_type: provider.type,
      description: provider.description,
      supports_oauth: provider.supportsOAuth,
      supports_pat: provider.supportsPAT,
      supports_devops: provider.supportsDevOps,
      capabilities: provider.capabilities,
      configured: true
    };
    setCredentialModalProvider(availableProvider);
    setEditingCredential(credential);
    setCredentialModalOpen(true);
  };

  const handleCredentialModalSuccess = async () => {
    setCredentialModalOpen(false);
    setCredentialModalProvider(null);
    setEditingCredential(null);
    showNotification(editingCredential ? 'Credential updated' : 'Credential added', 'success');
    // Refresh credentials for the provider
    if (expandedProviderId) {
      await fetchCredentialsForProvider(expandedProviderId);
    }
    await fetchProviders();
  };

  const handleTestCredential = async (providerId: string, credentialId: string) => {
    setCredentialActionLoading(`test-${credentialId}`);
    try {
      const result = await gitProvidersApi.testCredential(providerId, credentialId);
      if (result.success) {
        showNotification('Connection test successful', 'success');
      } else {
        showNotification(result.error || 'Connection test failed', 'error');
      }
    } catch (_error) {
      showNotification('Failed to test connection', 'error');
    } finally {
      setCredentialActionLoading(null);
    }
  };

  const handleMakeDefaultCredential = async (providerId: string, credentialId: string) => {
    setCredentialActionLoading(`default-${credentialId}`);
    try {
      await gitProvidersApi.makeDefaultCredential(providerId, credentialId);
      showNotification('Credential set as default', 'success');
      await fetchCredentialsForProvider(providerId);
    } catch (_error) {
      showNotification('Failed to set default credential', 'error');
    } finally {
      setCredentialActionLoading(null);
    }
  };

  const handleDeleteCredential = (providerId: string, credentialId: string, credentialName: string) => {
    confirm({
      title: 'Delete Credential',
      message: `Are you sure you want to delete "${credentialName}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        setCredentialActionLoading(`delete-${credentialId}`);
        try {
          await gitProvidersApi.deleteCredential(providerId, credentialId);
          showNotification('Credential deleted', 'success');
          await fetchCredentialsForProvider(providerId);
          await fetchProviders();
        } catch (_error) {
          showNotification('Failed to delete credential', 'error');
        } finally {
          setCredentialActionLoading(null);
        }
      },
    });
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
          <div className="w-10 h-10 bg-[#24292f] rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/>
            </svg>
          </div>
        );
      case 'gitlab':
        return (
          <div className="w-10 h-10 bg-[#FC6D26] rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
              <path d="m23.6004 9.5927-.0337-.0862L20.3.9814a.851.851 0 0 0-.3362-.405.8748.8748 0 0 0-.9997.0539.8748.8748 0 0 0-.29.4399l-2.2055 6.748H7.5375l-2.2057-6.748a.8573.8573 0 0 0-.29-.4412.8748.8748 0 0 0-.9997-.0537.8585.8585 0 0 0-.3362.4049L.4332 9.5015l-.0325.0862a6.0657 6.0657 0 0 0 2.0119 7.0105l.0113.0087.03.0213 4.976 3.7264 2.462 1.8633 1.4995 1.1321a1.0085 1.0085 0 0 0 1.2197 0l1.4995-1.1321 2.4619-1.8633 5.006-3.7489.0125-.01a6.0682 6.0682 0 0 0 2.0094-7.003z"/>
            </svg>
          </div>
        );
      case 'gitea':
        return (
          <div className="w-10 h-10 bg-[#609926] rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
              <path d="M4.209 4.603c-.247 0-.525.02-.84.088-.333.07-1.28.283-2.054 1.027C-.403 7.25.035 9.685.089 10.052c.065.446.263 1.687 1.21 2.768 1.749 2.141 5.513 2.092 5.513 2.092s.462 1.103 1.168 2.119c.955 1.263 1.936 2.248 2.89 2.367 2.406 0 7.212-.004 7.212-.004s.458.004 1.08-.394c.535-.324 1.013-.893 1.013-.893s.492-.527 1.18-1.73c.21-.37.385-.729.538-1.068 0 0 2.107-4.471 2.107-8.823-.042-1.318-.367-1.55-.443-1.627-.156-.156-.366-.153-.366-.153s-4.475.252-6.792.306c-.508.011-1.012.023-1.512.027v4.474l-.634-.301c0-1.39-.004-4.17-.004-4.17-1.107.016-3.405-.084-3.405-.084s-5.399-.27-5.987-.324c-.187-.011-.401-.032-.648-.032zm.354 1.832h.111s.271 2.269.6 3.597C5.549 11.147 6.22 13 6.22 13s-.996-.119-1.641-.348c-.99-.324-1.409-.714-1.409-.714s-.73-.511-1.096-1.52C1.444 8.73 2.021 7.7 2.021 7.7s.32-.859 1.47-1.145c.395-.106.863-.12 1.072-.12zm8.33 2.554c.26.003.509.127.509.127l.868.422-.529 1.075a.686.686 0 0 0-.614.359.685.685 0 0 0 .072.756l-.939 1.924a.69.69 0 0 0-.66.527.687.687 0 0 0 .347.763.686.686 0 0 0 .867-.206.688.688 0 0 0-.069-.882l.916-1.874a.667.667 0 0 0 .237-.02.657.657 0 0 0 .271-.137 8.826 8.826 0 0 1 1.016.512.761.761 0 0 1 .286.282c.073.21-.073.569-.073.569-.087.29-.702 1.55-.702 1.55a.692.692 0 0 0-.676.477.681.681 0 1 0 1.157-.252c.073-.141.141-.282.214-.431.19-.397.515-1.16.515-1.16.035-.066.218-.394.103-.814-.095-.435-.48-.638-.48-.638-.467-.301-1.116-.58-1.116-.58s0-.156-.042-.27a.688.688 0 0 0-.148-.241l.516-1.062 2.89 1.401s.48.218.583.619c.073.282-.019.534-.069.657-.24.587-2.1 4.317-2.1 4.317s-.232.554-.748.588a1.065 1.065 0 0 1-.393-.045l-.202-.08-4.31-2.1s-.417-.218-.49-.596c-.083-.31.104-.691.104-.691l2.073-4.272s.183-.37.466-.497a.855.855 0 0 1 .35-.077z"/>
            </svg>
          </div>
        );
      case 'bitbucket':
        return (
          <div className="w-10 h-10 bg-[#0052CC] rounded-lg flex items-center justify-center">
            <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="currentColor">
              <path d="M.778 1.213a.768.768 0 0 0-.768.892l3.263 19.81c.084.5.515.868 1.022.873H19.95a.772.772 0 0 0 .77-.646l3.27-20.03a.768.768 0 0 0-.768-.891zm13.742 14.317H9.522L8.17 8.466h7.561z"/>
            </svg>
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
        breadcrumbs={breadcrumbs}
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
      breadcrumbs={breadcrumbs}
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
          providers.map((provider) => {
            const isExpanded = expandedProviderId === provider.id;
            const credentials = providerCredentials[provider.id] || [];
            const isLoadingCreds = loadingCredentials === provider.id;

            return (
              <div
                key={provider.id}
                className={`bg-theme-surface border rounded-lg ${
                  provider.status === 'error' ? 'border-theme-danger' : 'border-theme'
                }`}
              >
                {/* Provider Header - Always visible */}
                <div
                  className="p-5 cursor-pointer"
                  onClick={() => handleToggleExpand(provider.id)}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex items-start gap-4">
                      <div className="flex items-center gap-2">
                        {isExpanded ? (
                          <ChevronDown className="w-4 h-4 text-theme-secondary" />
                        ) : (
                          <ChevronRight className="w-4 h-4 text-theme-secondary" />
                        )}
                        {getProviderLogo(provider.type)}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-semibold text-theme-primary">{provider.name}</h3>
                          {provider.isDefault && (
                            <span className="px-2 py-0.5 text-xs rounded-full bg-theme-interactive-primary text-theme-on-primary">
                              Default
                            </span>
                          )}
                          {getStatusBadge(provider.status)}
                          {provider.credentialsCount > 0 && (
                            <span className="px-2 py-0.5 text-xs rounded-full bg-theme-bg-subtle text-theme-secondary">
                              {provider.credentialsCount} credential{provider.credentialsCount !== 1 ? 's' : ''}
                            </span>
                          )}
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

                    <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
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
                                href={provider.webUrl || provider.apiUrl.replace('/api/v1', '').replace('/api', '')}
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

                  {/* Quick Stats - Always show when connected */}
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

                  {provider.lastSync && !isExpanded && (
                    <p className="text-xs text-theme-secondary mt-3">
                      Last synced {provider.lastSync}
                    </p>
                  )}
                </div>

                {/* Expanded Details */}
                {isExpanded && (
                  <div className="border-t border-theme">
                    {/* Capabilities */}
                    <div className="p-5 border-b border-theme">
                      <h4 className="text-sm font-medium text-theme-primary mb-3">Capabilities</h4>
                      <div className="flex flex-wrap gap-2">
                        {provider.supportsOAuth && (
                          <span className="flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-theme-bg-subtle text-theme-secondary">
                            <Shield className="w-3 h-3" />
                            OAuth
                          </span>
                        )}
                        {provider.supportsPAT && (
                          <span className="flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-theme-bg-subtle text-theme-secondary">
                            <Key className="w-3 h-3" />
                            Personal Access Tokens
                          </span>
                        )}
                        {provider.supportsWebhooks && (
                          <span className="flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-theme-bg-subtle text-theme-secondary">
                            <Webhook className="w-3 h-3" />
                            Webhooks
                          </span>
                        )}
                        {provider.supportsDevOps && (
                          <span className="flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-theme-bg-subtle text-theme-secondary">
                            <Cpu className="w-3 h-3" />
                            CI/CD
                          </span>
                        )}
                        {provider.capabilities.map((cap) => (
                          <span
                            key={cap}
                            className="px-2 py-1 text-xs rounded-md bg-theme-bg-subtle text-theme-tertiary"
                          >
                            {cap}
                          </span>
                        ))}
                      </div>
                      {provider.description && (
                        <p className="text-sm text-theme-secondary mt-3">{provider.description}</p>
                      )}
                    </div>

                    {/* Credentials Section */}
                    <div className="p-5">
                      <div className="flex items-center justify-between mb-3">
                        <h4 className="text-sm font-medium text-theme-primary">Credentials</h4>
                        <button
                          onClick={() => handleAddCredential(provider)}
                          className="flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-theme-interactive-primary text-theme-on-primary hover:bg-theme-interactive-primary-hover"
                        >
                          <Plus className="w-3 h-3" />
                          Add Credential
                        </button>
                      </div>

                      {isLoadingCreds ? (
                        <div className="flex items-center justify-center py-6">
                          <Loader2 className="w-5 h-5 animate-spin text-theme-primary" />
                        </div>
                      ) : credentials.length === 0 ? (
                        <div className="text-center py-6 bg-theme-bg rounded-lg border border-dashed border-theme">
                          <Key className="w-8 h-8 mx-auto text-theme-secondary mb-2" />
                          <p className="text-sm text-theme-secondary">No credentials configured</p>
                          <p className="text-xs text-theme-tertiary mt-1">
                            Add a credential to connect and sync repositories
                          </p>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          {credentials.map((credential) => (
                            <div
                              key={credential.id}
                              className="flex items-center justify-between p-3 bg-theme-bg rounded-lg border border-theme"
                            >
                              <div className="flex items-center gap-3">
                                <div className="p-2 rounded-lg bg-theme-primary/10">
                                  <Key className="w-4 h-4 text-theme-primary" />
                                </div>
                                <div>
                                  <div className="flex items-center gap-2">
                                    <span className="font-medium text-sm text-theme-primary">
                                      {credential.name}
                                    </span>
                                    {credential.is_default && (
                                      <span className="px-1.5 py-0.5 text-xs rounded bg-theme-primary/10 text-theme-primary">
                                        Default
                                      </span>
                                    )}
                                    {credential.is_active ? (
                                      <span className="flex items-center gap-0.5 text-xs text-theme-success">
                                        <CheckCircle className="w-3 h-3" />
                                        Active
                                      </span>
                                    ) : (
                                      <span className="flex items-center gap-0.5 text-xs text-theme-danger">
                                        <XCircle className="w-3 h-3" />
                                        Inactive
                                      </span>
                                    )}
                                  </div>
                                  <div className="flex items-center gap-3 mt-1 text-xs text-theme-secondary">
                                    <span className="capitalize">{credential.auth_type.replace('_', ' ')}</span>
                                    {credential.external_username && (
                                      <span>@{credential.external_username}</span>
                                    )}
                                    {credential.repository_count !== undefined && (
                                      <span>{credential.repository_count} repos</span>
                                    )}
                                  </div>
                                </div>
                              </div>

                              <div className="flex items-center gap-1">
                                <button
                                  onClick={() => handleTestCredential(provider.id, credential.id)}
                                  disabled={credentialActionLoading !== null}
                                  className="p-1.5 rounded-lg hover:bg-theme-hover text-theme-secondary hover:text-theme-primary"
                                  title="Test Connection"
                                >
                                  {credentialActionLoading === `test-${credential.id}` ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                  ) : (
                                    <TestTube className="w-4 h-4" />
                                  )}
                                </button>
                                <button
                                  onClick={() => handleEditCredential(provider, credential)}
                                  className="p-1.5 rounded-lg hover:bg-theme-hover text-theme-secondary hover:text-theme-primary"
                                  title="Edit"
                                >
                                  <Settings className="w-4 h-4" />
                                </button>
                                {!credential.is_default && (
                                  <button
                                    onClick={() => handleMakeDefaultCredential(provider.id, credential.id)}
                                    disabled={credentialActionLoading !== null}
                                    className="p-1.5 rounded-lg hover:bg-theme-hover text-theme-secondary hover:text-theme-primary"
                                    title="Make Default"
                                  >
                                    {credentialActionLoading === `default-${credential.id}` ? (
                                      <Loader2 className="w-4 h-4 animate-spin" />
                                    ) : (
                                      <CheckCircle className="w-4 h-4" />
                                    )}
                                  </button>
                                )}
                                <button
                                  onClick={() => handleDeleteCredential(provider.id, credential.id, credential.name)}
                                  disabled={credentialActionLoading !== null}
                                  className="p-1.5 rounded-lg hover:bg-theme-danger/10 text-theme-secondary hover:text-theme-danger"
                                  title="Delete"
                                >
                                  {credentialActionLoading === `delete-${credential.id}` ? (
                                    <Loader2 className="w-4 h-4 animate-spin" />
                                  ) : (
                                    <Trash2 className="w-4 h-4" />
                                  )}
                                </button>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    {/* Footer with last sync */}
                    {provider.lastSync && (
                      <div className="px-5 pb-4">
                        <p className="text-xs text-theme-tertiary">
                          Last synced {provider.lastSync}
                        </p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })
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
                setSelectedProviderType(option.type);
                setIsModalOpen(true);
              }}
              className="flex items-center gap-3 p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors group text-left cursor-pointer"
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

      {/* Edit/Create Provider Modal */}
      <GitProviderModal
        isOpen={isModalOpen}
        onClose={handleModalClose}
        onSuccess={handleModalSuccess}
        provider={editingProvider}
        initialProviderType={selectedProviderType}
      />

      {ConfirmationDialog}

      {/* Add/Edit Credential Modal */}
      {credentialModalProvider && (
        <CredentialModal
          isOpen={credentialModalOpen}
          onClose={() => {
            setCredentialModalOpen(false);
            setCredentialModalProvider(null);
            setEditingCredential(null);
          }}
          provider={credentialModalProvider}
          onSuccess={handleCredentialModalSuccess}
          credential={editingCredential}
        />
      )}
    </PageContainer>
  );
}

export default GitProvidersPage;
