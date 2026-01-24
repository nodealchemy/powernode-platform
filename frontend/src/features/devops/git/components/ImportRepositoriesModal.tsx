import { useState, useEffect } from 'react';
import {
  X,
  FolderGit2,
  Search,
  Lock,
  Unlock,
  Star,
  GitFork,
  Archive,
  Loader2,
  CheckCircle2,
  AlertCircle,
  Download,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { gitProvidersApi } from '../services/gitProvidersApi';
import type {
  GitProvider,
  GitCredential,
  AvailableRepository,
  RepositoryUsage,
} from '../types';

interface ImportRepositoriesModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const ImportRepositoriesModal: React.FC<ImportRepositoriesModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
}) => {
  // Provider/Credential selection
  const [providers, setProviders] = useState<GitProvider[]>([]);
  const [selectedProviderId, setSelectedProviderId] = useState<string>('');
  const [credentials, setCredentials] = useState<GitCredential[]>([]);
  const [selectedCredentialId, setSelectedCredentialId] = useState<string>('');

  // Repository list state
  const [repositories, setRepositories] = useState<AvailableRepository[]>([]);
  const [usage, setUsage] = useState<RepositoryUsage | null>(null);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState('');
  const [includeArchived, setIncludeArchived] = useState(false);
  const [includeForks, setIncludeForks] = useState(false);

  // Selection state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Import state
  const [importing, setImporting] = useState(false);
  const [importResult, setImportResult] = useState<{
    success: boolean;
    message: string;
    errors?: Array<{ external_id: string; error: string }>;
  } | null>(null);

  // Load providers on open
  useEffect(() => {
    if (isOpen) {
      loadProviders();
      // Reset state
      setSelectedProviderId('');
      setSelectedCredentialId('');
      setRepositories([]);
      setUsage(null);
      setSelectedIds(new Set());
      setImportResult(null);
      setSearch('');
    }
  }, [isOpen]);

  // Load credentials when provider changes
  useEffect(() => {
    if (selectedProviderId) {
      loadCredentials(selectedProviderId);
      setSelectedCredentialId('');
      setRepositories([]);
    }
  }, [selectedProviderId]);

  // Load repositories when credential changes
  useEffect(() => {
    if (selectedProviderId && selectedCredentialId) {
      loadRepositories();
    }
  }, [selectedCredentialId, includeArchived, includeForks]);

  const loadProviders = async () => {
    try {
      const data = await gitProvidersApi.getProviders();
      setProviders(data);
      if (data.length === 1) {
        setSelectedProviderId(data[0].id);
      }
    } catch {
      // Handle error silently
    }
  };

  const loadCredentials = async (providerId: string) => {
    try {
      const data = await gitProvidersApi.getCredentials(providerId);
      setCredentials(data);
      if (data.length === 1) {
        setSelectedCredentialId(data[0].id);
      }
    } catch {
      // Handle error silently
    }
  };

  const loadRepositories = async () => {
    if (!selectedProviderId || !selectedCredentialId) return;

    setLoading(true);
    try {
      const data = await gitProvidersApi.getAvailableRepositories(
        selectedProviderId,
        selectedCredentialId,
        {
          per_page: 100,
          include_archived: includeArchived,
          include_forks: includeForks,
        }
      );
      setRepositories(data.repositories);
      setUsage(data.usage);
    } catch {
      setRepositories([]);
      setUsage(null);
    } finally {
      setLoading(false);
    }
  };

  const handleToggleSelect = (externalId: string) => {
    const newSelected = new Set(selectedIds);
    if (newSelected.has(externalId)) {
      newSelected.delete(externalId);
    } else {
      newSelected.add(externalId);
    }
    setSelectedIds(newSelected);
  };

  const handleSelectAll = () => {
    const availableRepos = filteredRepositories.filter((r) => !r.already_imported);
    if (selectedIds.size === availableRepos.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(availableRepos.map((r) => r.external_id)));
    }
  };

  const handleImport = async () => {
    if (selectedIds.size === 0) return;

    setImporting(true);
    setImportResult(null);

    try {
      const result = await gitProvidersApi.importRepositories(
        selectedProviderId,
        selectedCredentialId,
        Array.from(selectedIds),
        { include_archived: includeArchived, include_forks: includeForks }
      );

      setImportResult({
        success: true,
        message: result.message,
        errors: result.errors.length > 0 ? result.errors : undefined,
      });

      // Update usage after import
      setUsage({
        current: result.usage.current,
        limit: result.usage.limit,
        available: result.usage.limit - result.usage.current,
      });

      // Mark imported repos
      setRepositories((prev) =>
        prev.map((repo) =>
          selectedIds.has(repo.external_id) ? { ...repo, already_imported: true } : repo
        )
      );

      setSelectedIds(new Set());

      // Notify parent to refresh
      if (result.imported_count > 0) {
        onSuccess();
      }
    } catch (error) {
      setImportResult({
        success: false,
        message: error instanceof Error ? error.message : 'Failed to import repositories',
      });
    } finally {
      setImporting(false);
    }
  };

  // Filter repositories by search
  const filteredRepositories = repositories.filter((repo) => {
    if (!search) return true;
    const searchLower = search.toLowerCase();
    return (
      repo.name.toLowerCase().includes(searchLower) ||
      repo.full_name.toLowerCase().includes(searchLower) ||
      repo.description?.toLowerCase().includes(searchLower)
    );
  });

  const canImport =
    selectedIds.size > 0 && usage && selectedIds.size <= usage.available && !importing;

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex min-h-full items-center justify-center p-4">
        {/* Backdrop */}
        <div className="fixed inset-0 bg-black/50" onClick={onClose} />

        {/* Modal */}
        <div className="relative bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-4xl max-h-[85vh] flex flex-col">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <FolderGit2 className="w-6 h-6 text-theme-primary" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  Import Repositories
                </h2>
                <p className="text-sm text-theme-secondary">
                  Select repositories to import from your connected providers
                </p>
              </div>
            </div>
            <button
              onClick={onClose}
              className="p-2 text-theme-secondary hover:text-theme-primary rounded-lg hover:bg-theme-hover transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Provider/Credential Selection */}
          <div className="px-6 py-4 border-b border-theme bg-theme-background/50">
            <div className="flex flex-wrap gap-4">
              <div className="flex-1 min-w-[200px]">
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Provider
                </label>
                <select
                  value={selectedProviderId}
                  onChange={(e) => setSelectedProviderId(e.target.value)}
                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
                >
                  <option value="">Select a provider...</option>
                  {providers.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex-1 min-w-[200px]">
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Credential
                </label>
                <select
                  value={selectedCredentialId}
                  onChange={(e) => setSelectedCredentialId(e.target.value)}
                  disabled={!selectedProviderId}
                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary disabled:opacity-50"
                >
                  <option value="">Select a credential...</option>
                  {credentials.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} ({c.external_username || c.auth_type})
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Usage indicator */}
            {usage && (
              <div className="mt-4 p-3 bg-theme-surface rounded-lg border border-theme">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-secondary">
                    Repository Usage
                  </span>
                  <span className="text-sm text-theme-primary">
                    {usage.current} / {usage.limit} used
                  </span>
                </div>
                <div className="w-full h-2 bg-theme-background rounded-full overflow-hidden">
                  <div
                    className={`h-full transition-all ${
                      usage.available === 0
                        ? 'bg-theme-error'
                        : usage.available <= 3
                        ? 'bg-theme-warning'
                        : 'bg-theme-success'
                    }`}
                    style={{ width: `${(usage.current / usage.limit) * 100}%` }}
                  />
                </div>
                <p className="text-xs text-theme-tertiary mt-1">
                  {usage.available} slots available on your current plan
                </p>
              </div>
            )}
          </div>

          {/* Search and Filters */}
          {selectedCredentialId && (
            <div className="px-6 py-3 border-b border-theme flex flex-wrap items-center gap-4">
              <div className="relative flex-1 min-w-[200px]">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
                <input
                  type="text"
                  placeholder="Search repositories..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="w-full pl-10 pr-4 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                />
              </div>

              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={includeForks}
                  onChange={(e) => setIncludeForks(e.target.checked)}
                  className="w-4 h-4 rounded border-theme text-theme-primary"
                />
                <GitFork className="w-4 h-4 text-theme-secondary" />
                <span className="text-sm text-theme-secondary">Include forks</span>
              </label>

              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={includeArchived}
                  onChange={(e) => setIncludeArchived(e.target.checked)}
                  className="w-4 h-4 rounded border-theme text-theme-primary"
                />
                <Archive className="w-4 h-4 text-theme-secondary" />
                <span className="text-sm text-theme-secondary">Include archived</span>
              </label>

              <button
                onClick={loadRepositories}
                disabled={loading}
                className="flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-hover rounded-lg transition-colors disabled:opacity-50"
              >
                <Loader2 className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
                Refresh
              </button>
            </div>
          )}

          {/* Repository List */}
          <div className="flex-1 overflow-y-auto px-6 py-4">
            {!selectedCredentialId ? (
              <div className="flex flex-col items-center justify-center h-64 text-center">
                <FolderGit2 className="w-12 h-12 text-theme-secondary opacity-50 mb-4" />
                <p className="text-theme-secondary">
                  Select a provider and credential to browse available repositories
                </p>
              </div>
            ) : loading ? (
              <div className="flex items-center justify-center h-64">
                <Loader2 className="w-8 h-8 animate-spin text-theme-primary" />
              </div>
            ) : filteredRepositories.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-64 text-center">
                <FolderGit2 className="w-12 h-12 text-theme-secondary opacity-50 mb-4" />
                <p className="text-theme-secondary">
                  {search
                    ? 'No repositories match your search'
                    : 'No repositories found in this account'}
                </p>
              </div>
            ) : (
              <>
                {/* Select All */}
                <div className="flex items-center justify-between mb-4">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={
                        selectedIds.size > 0 &&
                        selectedIds.size ===
                          filteredRepositories.filter((r) => !r.already_imported).length
                      }
                      onChange={handleSelectAll}
                      className="w-4 h-4 rounded border-theme text-theme-primary"
                    />
                    <span className="text-sm text-theme-secondary">
                      Select all ({filteredRepositories.filter((r) => !r.already_imported).length}{' '}
                      available)
                    </span>
                  </label>
                  <span className="text-sm text-theme-tertiary">
                    {selectedIds.size} selected
                  </span>
                </div>

                {/* Repository grid */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {filteredRepositories.map((repo) => (
                    <div
                      key={repo.external_id}
                      onClick={() =>
                        !repo.already_imported && handleToggleSelect(repo.external_id)
                      }
                      className={`p-4 rounded-lg border transition-all ${
                        repo.already_imported
                          ? 'border-theme bg-theme-background/50 opacity-60 cursor-not-allowed'
                          : selectedIds.has(repo.external_id)
                          ? 'border-theme-primary bg-theme-primary/5 cursor-pointer'
                          : 'border-theme bg-theme-surface hover:border-theme-primary/50 cursor-pointer'
                      }`}
                    >
                      <div className="flex items-start gap-3">
                        {/* Checkbox */}
                        <div className="mt-0.5">
                          {repo.already_imported ? (
                            <CheckCircle2 className="w-5 h-5 text-theme-success" />
                          ) : (
                            <input
                              type="checkbox"
                              checked={selectedIds.has(repo.external_id)}
                              onChange={() => handleToggleSelect(repo.external_id)}
                              onClick={(e) => e.stopPropagation()}
                              className="w-5 h-5 rounded border-theme text-theme-primary"
                            />
                          )}
                        </div>

                        {/* Content */}
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="font-medium text-theme-primary truncate">
                              {repo.name}
                            </span>
                            {repo.is_private ? (
                              <Lock className="w-3.5 h-3.5 text-theme-warning flex-shrink-0" />
                            ) : (
                              <Unlock className="w-3.5 h-3.5 text-theme-success flex-shrink-0" />
                            )}
                            {repo.is_fork && (
                              <GitFork className="w-3.5 h-3.5 text-theme-secondary flex-shrink-0" />
                            )}
                            {repo.is_archived && (
                              <Archive className="w-3.5 h-3.5 text-theme-tertiary flex-shrink-0" />
                            )}
                          </div>

                          {repo.description && (
                            <p className="text-sm text-theme-secondary line-clamp-2 mb-2">
                              {repo.description}
                            </p>
                          )}

                          <div className="flex items-center gap-3 text-xs text-theme-tertiary">
                            {repo.primary_language && (
                              <span className="flex items-center gap-1">
                                <span className="w-2 h-2 rounded-full bg-theme-info" />
                                {repo.primary_language}
                              </span>
                            )}
                            <span className="flex items-center gap-1">
                              <Star className="w-3 h-3" />
                              {repo.stars_count}
                            </span>
                            {repo.already_imported && (
                              <span className="text-theme-success">Already imported</span>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>

          {/* Import Result */}
          {importResult && (
            <div
              className={`mx-6 mb-4 p-4 rounded-lg flex items-start gap-3 ${
                importResult.success
                  ? 'bg-theme-success/10 border border-theme-success/30'
                  : 'bg-theme-error/10 border border-theme-error/30'
              }`}
            >
              {importResult.success ? (
                <CheckCircle2 className="w-5 h-5 text-theme-success flex-shrink-0 mt-0.5" />
              ) : (
                <AlertCircle className="w-5 h-5 text-theme-error flex-shrink-0 mt-0.5" />
              )}
              <div className="flex-1">
                <p
                  className={`font-medium ${
                    importResult.success ? 'text-theme-success' : 'text-theme-error'
                  }`}
                >
                  {importResult.message}
                </p>
                {importResult.errors && importResult.errors.length > 0 && (
                  <ul className="mt-2 text-sm text-theme-secondary">
                    {importResult.errors.map((err, idx) => (
                      <li key={idx}>• {err.error}</li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          )}

          {/* Footer */}
          <div className="px-6 py-4 border-t border-theme bg-theme-background/50 flex items-center justify-between">
            <div className="text-sm text-theme-secondary">
              {selectedIds.size > 0 && usage && selectedIds.size > usage.available && (
                <span className="text-theme-error">
                  Selected {selectedIds.size} but only {usage.available} slots available
                </span>
              )}
            </div>
            <div className="flex items-center gap-3">
              <Button variant="secondary" onClick={onClose}>
                {importResult?.success ? 'Close' : 'Cancel'}
              </Button>
              <Button
                variant="primary"
                onClick={handleImport}
                disabled={!canImport}
              >
                {importing ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Importing...
                  </>
                ) : (
                  <>
                    <Download className="w-4 h-4 mr-2" />
                    Import {selectedIds.size} {selectedIds.size === 1 ? 'Repository' : 'Repositories'}
                  </>
                )}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
