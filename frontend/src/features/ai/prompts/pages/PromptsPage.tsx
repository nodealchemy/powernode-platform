import React, { useState, useEffect, useCallback } from 'react';
import { Plus, LayoutGrid, Globe, Bot, GitBranch, Search, Code, Shield, Rocket, FileText, Puzzle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePromptTemplates } from '../hooks/usePromptTemplates';
import { TemplateEditor } from '../components/TemplateEditor';
import { PreviewModal } from '../components/PreviewModal';
import { TemplateCard } from '../components/TemplateCard';
import {
  ScopeFilter,
  UpdateFromSourceModal,
  useScopeParam,
  isGlobal,
  isClone,
} from '@/features/content/scoped';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import type {
  PromptTemplate,
  PromptCategory,
  PromptTemplateFormData,
  PromptPreviewResponse,
} from '../types';

interface PromptsContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const PromptsContent: React.FC<PromptsContentProps> = ({ onActionsReady }) => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const { hasPermission } = usePermissions();
  const canWrite = hasPermission('ai.prompt_templates.write');
  const [scope, setScope] = useScopeParam();
  const {
    templates,
    loading,
    refresh,
    createTemplate,
    updateTemplate,
    deleteTemplate,
    duplicateTemplate,
    previewTemplate,
    cloneTemplate,
    previewUpdateFromSource,
    applyUpdateFromSource,
  } = usePromptTemplates({ scope });

  const { refreshAction } = useRefreshAction({
    onRefresh: refresh,
    loading,
  });

  useEffect(() => {
    if (onActionsReady) {
      onActionsReady([refreshAction]);
    }
  }, [onActionsReady, refreshAction]);

  const [categoryFilter, setCategoryFilter] = useState<PromptCategory | 'all'>('all');
  const [showEditor, setShowEditor] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<PromptTemplate | null>(null);
  const [previewingTemplate, setPreviewingTemplate] = useState<PromptTemplate | null>(null);
  const [preview, setPreview] = useState<PromptPreviewResponse | null>(null);
  // id -> true when an account clone diverged from its origin (preview not synced)
  const [updateAvailable, setUpdateAvailable] = useState<Record<string, boolean>>({});
  const [updateTemplateTarget, setUpdateTemplateTarget] = useState<PromptTemplate | null>(null);

  const filteredTemplates = templates.filter((t) => {
    if (categoryFilter === 'all') return true;
    return t.category === categoryFilter;
  });

  // For visible account clones, fetch the 3-way preview to learn whether the
  // baseline diverged, so the "Update available" badge only shows when not synced.
  useEffect(() => {
    let cancelled = false;
    const clones = templates.filter((t) => isClone(t));
    if (clones.length === 0) {
      setUpdateAvailable({});
      return;
    }
    (async () => {
      const entries = await Promise.all(
        clones.map(async (t) => {
          try {
            const result = await previewUpdateFromSource(t.id);
            return [t.id, !result.error && !result.synced] as const;
          } catch {
            return [t.id, false] as const;
          }
        }),
      );
      if (!cancelled) setUpdateAvailable(Object.fromEntries(entries));
    })();
    return () => {
      cancelled = true;
    };
  }, [templates, previewUpdateFromSource]);

  // Clicking a global (read-only) template opens Preview; account-owned opens the editor.
  const handleCardOpen = useCallback((template: PromptTemplate) => {
    if (isGlobal(template)) {
      setPreviewingTemplate(template);
      setPreview(null);
    } else {
      setEditingTemplate(template);
    }
  }, []);

  const handleCloned = useCallback((copy: PromptTemplate) => {
    setEditingTemplate(copy);
  }, []);

  const handleSubmit = async (data: PromptTemplateFormData) => {
    if (editingTemplate) {
      await updateTemplate(editingTemplate.id, data);
    } else {
      await createTemplate(data);
    }
    setShowEditor(false);
    setEditingTemplate(null);
  };

  const handleDelete = (id: string) => {
    confirm({
      title: 'Delete Prompt Template',
      message: 'Are you sure you want to delete this prompt template?',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        await deleteTemplate(id);
      },
    });
  };

  const handlePreview = async (variables: Record<string, string>) => {
    if (previewingTemplate) {
      const result = await previewTemplate(previewingTemplate.id, variables);
      setPreview(result);
    }
  };

  return (
    <div className="space-y-6">
      {/* Editor */}
      {(showEditor || editingTemplate) && (
        <TemplateEditor
          template={editingTemplate || undefined}
          onSubmit={handleSubmit}
          onCancel={() => {
            setShowEditor(false);
            setEditingTemplate(null);
          }}
        />
      )}

      {/* Category Filter */}
      {!showEditor && !editingTemplate && (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
            <ScopeFilter value={scope} onChange={setScope} />
            {canWrite && (
              <Button
                onClick={() => {
                  setEditingTemplate(null);
                  setShowEditor(true);
                }}
                variant="primary"
                size="sm"
              >
                <Plus className="w-4 h-4 mr-1" /> Create Template
              </Button>
            )}
          </div>

          <TabContainer
            tabs={[
              { id: 'all', label: 'All', icon: <LayoutGrid className="w-4 h-4" /> },
              { id: 'general', label: 'General', icon: <Globe className="w-4 h-4" /> },
              { id: 'agent', label: 'Agent', icon: <Bot className="w-4 h-4" /> },
              { id: 'workflow', label: 'Workflow', icon: <GitBranch className="w-4 h-4" /> },
              { id: 'review', label: 'Review', icon: <Search className="w-4 h-4" /> },
              { id: 'implement', label: 'Implement', icon: <Code className="w-4 h-4" /> },
              { id: 'security', label: 'Security', icon: <Shield className="w-4 h-4" /> },
              { id: 'deploy', label: 'Deploy', icon: <Rocket className="w-4 h-4" /> },
              { id: 'docs', label: 'Docs', icon: <FileText className="w-4 h-4" /> },
              { id: 'custom', label: 'Custom', icon: <Puzzle className="w-4 h-4" /> },
            ]}
            activeTab={categoryFilter}
            onTabChange={(tabId) => setCategoryFilter(tabId as PromptCategory | 'all')}
            variant="underline"
            size="sm"
            compact
            className="mb-6"
          />

          {/* Template List */}
          {loading ? (
            <LoadingSpinner className="py-12" />
          ) : filteredTemplates.length === 0 ? (
            <div className="text-center py-12">
              <p className="text-theme-secondary">No prompt templates found.</p>
              {canWrite && (
                <Button
                  onClick={() => setShowEditor(true)}
                  variant="primary"
                  className="mt-4"
                >
                  Create your first template
                </Button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredTemplates.map((template) => (
                <TemplateCard
                  key={template.id}
                  template={template}
                  onEdit={() => handleCardOpen(template)}
                  onPreview={() => {
                    setPreviewingTemplate(template);
                    setPreview(null);
                  }}
                  onDuplicate={() => duplicateTemplate(template.id)}
                  onDelete={() => handleDelete(template.id)}
                  canClone={canWrite}
                  onCloneTemplate={cloneTemplate}
                  onCloned={handleCloned}
                  updateAvailable={!!updateAvailable[template.id]}
                  onUpdateFromSource={(id) =>
                    setUpdateTemplateTarget(templates.find((t) => t.id === id) ?? null)
                  }
                />
              ))}
            </div>
          )}
        </>
      )}

      {/* Preview Modal */}
      {previewingTemplate && (
        <PreviewModal
          template={previewingTemplate}
          preview={preview}
          onClose={() => {
            setPreviewingTemplate(null);
            setPreview(null);
          }}
          onPreview={handlePreview}
        />
      )}

      {/* Update-from-source Modal (account clones) */}
      <UpdateFromSourceModal
        isOpen={!!updateTemplateTarget}
        onClose={() => setUpdateTemplateTarget(null)}
        itemName={updateTemplateTarget?.name}
        fetchPreview={() => previewUpdateFromSource(updateTemplateTarget!.id)}
        applyUpdate={(resolutions) =>
          applyUpdateFromSource(updateTemplateTarget!.id, resolutions)
        }
        onApplied={refresh}
      />
      {ConfirmationDialog}
    </div>
  );
};

const PromptsPageContent: React.FC = () => {
  const {
    loading,
    refresh,
  } = usePromptTemplates();

  const { refreshAction } = useRefreshAction({
    onRefresh: refresh,
    loading,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Prompts' }
  ];

  const actions = [
    refreshAction,
  ];

  return (
    <PageContainer
      title="Prompt Templates"
      description="Manage reusable AI prompt templates for workflows and agents"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <PromptsContent />
    </PageContainer>
  );
};

export const PromptsPage: React.FC = () => (
  <PageErrorBoundary>
    <PromptsPageContent />
  </PageErrorBoundary>
);

export default PromptsPage;
