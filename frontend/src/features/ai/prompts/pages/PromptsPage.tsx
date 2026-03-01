import React, { useState, useEffect } from 'react';
import { Plus, LayoutGrid, Globe, Bot, GitBranch, Search, Code, Shield, Rocket, FileText, Puzzle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePromptTemplates } from '../hooks/usePromptTemplates';
import { TemplateEditor } from '../components/TemplateEditor';
import { PreviewModal } from '../components/PreviewModal';
import { TemplateCard } from '../components/TemplateCard';
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
  const {
    templates,
    loading,
    refresh,
    createTemplate,
    updateTemplate,
    deleteTemplate,
    duplicateTemplate,
    previewTemplate,
  } = usePromptTemplates();

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

  const filteredTemplates = templates.filter((t) => {
    if (categoryFilter === 'all') return true;
    return t.category === categoryFilter;
  });

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
          <div className="flex justify-end mb-4">
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
              <Button
                onClick={() => setShowEditor(true)}
                variant="primary"
                className="mt-4"
              >
                Create your first template
              </Button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {filteredTemplates.map((template) => (
                <TemplateCard
                  key={template.id}
                  template={template}
                  onEdit={() => setEditingTemplate(template)}
                  onPreview={() => {
                    setPreviewingTemplate(template);
                    setPreview(null);
                  }}
                  onDuplicate={() => duplicateTemplate(template.id)}
                  onDelete={() => handleDelete(template.id)}
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
