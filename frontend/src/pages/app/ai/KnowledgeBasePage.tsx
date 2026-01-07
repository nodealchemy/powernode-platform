import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ContextBrowser } from '@/features/ai-context/components/ContextBrowser';
import { SearchResults } from '@/features/ai-context/components/SearchResults';
import { contextApi } from '@/features/ai-context/services/contextApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { ContextFormData } from '@/features/ai-context/types';

export function KnowledgeBasePage() {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [activeTab, setActiveTab] = useState<'browse' | 'search' | 'create'>('browse');
  const [isCreating, setIsCreating] = useState(false);
  const [formData, setFormData] = useState<ContextFormData>({
    name: '',
    description: '',
    context_type: 'knowledge_base',
    scope: 'account',
  });
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [refreshKey, setRefreshKey] = useState(0);

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {};
    if (!formData.name.trim()) {
      errors.name = 'Name is required';
    }
    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleCreateContext = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;

    setIsCreating(true);
    const response = await contextApi.createContext(formData);

    if (response.success && response.data) {
      showNotification('Knowledge base created', 'success');
      setActiveTab('browse');
      setFormData({
        name: '',
        description: '',
        context_type: 'knowledge_base',
        scope: 'account',
      });
      setRefreshKey((k) => k + 1);
      navigate(`/app/ai/contexts/${response.data.context.id}`);
    } else {
      showNotification(response.error || 'Failed to create knowledge base', 'error');
    }
    setIsCreating(false);
  };

  return (
    <PageContainer
      title="Knowledge Base"
      description="Manage AI knowledge and context storage"
      actions={[
        {
          label: 'New Knowledge Base',
          onClick: () => setActiveTab('create'),
          variant: 'primary',
        },
      ]}
    >
      <div className="space-y-6">
        {/* Tabs */}
        <div className="border-b border-theme">
          <nav className="flex gap-6">
            {(['browse', 'search', 'create'] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`pb-3 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab
                    ? 'border-theme-primary text-theme-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                {tab === 'browse' && 'Browse'}
                {tab === 'search' && 'Search'}
                {tab === 'create' && 'Create New'}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        {activeTab === 'browse' && (
          <ContextBrowser
            key={refreshKey}
            filters={{ context_type: 'knowledge_base' }}
          />
        )}

        {activeTab === 'search' && <SearchResults />}

        {activeTab === 'create' && (
          <div className="max-w-2xl">
            <form onSubmit={handleCreateContext} className="space-y-6">
              <div className="bg-theme-surface border border-theme rounded-lg p-6">
                <h3 className="text-lg font-medium text-theme-primary mb-4">
                  Create Knowledge Base
                </h3>

                {/* Name */}
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Name <span className="text-theme-error">*</span>
                  </label>
                  <input
                    type="text"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    placeholder="e.g., Product Documentation, Company Policies"
                    className={`w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
                      formErrors.name ? 'border-theme-error' : 'border-theme'
                    }`}
                  />
                  {formErrors.name && (
                    <p className="text-xs text-theme-error mt-1">{formErrors.name}</p>
                  )}
                </div>

                {/* Description */}
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Description
                  </label>
                  <textarea
                    value={formData.description || ''}
                    onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                    placeholder="Describe what this knowledge base contains..."
                    rows={3}
                    className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                  />
                </div>

                {/* Scope */}
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Scope
                  </label>
                  <select
                    value={formData.scope}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        scope: e.target.value as ContextFormData['scope'],
                      })
                    }
                    className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                  >
                    <option value="account">Account-wide</option>
                    <option value="team">Team</option>
                    <option value="workflow">Workflow</option>
                  </select>
                  <p className="text-xs text-theme-tertiary mt-1">
                    Determines who can access this knowledge base
                  </p>
                </div>

                {/* Retention Policy */}
                <div className="p-4 bg-theme-surface rounded-lg">
                  <h4 className="text-sm font-medium text-theme-primary mb-3">
                    Retention Policy (Optional)
                  </h4>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs text-theme-secondary mb-1">
                        Max Entries
                      </label>
                      <input
                        type="number"
                        value={formData.retention_policy?.max_entries || ''}
                        onChange={(e) =>
                          setFormData({
                            ...formData,
                            retention_policy: {
                              ...formData.retention_policy,
                              max_entries: e.target.value ? parseInt(e.target.value) : undefined,
                            },
                          })
                        }
                        placeholder="Unlimited"
                        className="w-full px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded text-theme-primary"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-theme-secondary mb-1">
                        Max Age (days)
                      </label>
                      <input
                        type="number"
                        value={formData.retention_policy?.max_age_days || ''}
                        onChange={(e) =>
                          setFormData({
                            ...formData,
                            retention_policy: {
                              ...formData.retention_policy,
                              max_age_days: e.target.value ? parseInt(e.target.value) : undefined,
                            },
                          })
                        }
                        placeholder="Never expire"
                        className="w-full px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded text-theme-primary"
                      />
                    </div>
                  </div>
                </div>
              </div>

              {/* Actions */}
              <div className="flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setActiveTab('browse')}
                  className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isCreating}
                  className="px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover disabled:opacity-50 transition-colors"
                >
                  {isCreating ? 'Creating...' : 'Create Knowledge Base'}
                </button>
              </div>
            </form>
          </div>
        )}
      </div>
    </PageContainer>
  );
}
