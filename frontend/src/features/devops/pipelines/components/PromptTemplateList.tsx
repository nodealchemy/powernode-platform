import React from 'react';
import { FileText, Copy, Trash2, MoreVertical, Eye, Tag } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { DevopsPromptTemplate, DevopsPromptCategory } from '@/types/devops-pipelines';

interface PromptTemplateListProps {
  templates: DevopsPromptTemplate[];
  loading: boolean;
  onEdit: (template: DevopsPromptTemplate) => void;
  onPreview: (template: DevopsPromptTemplate) => void;
  onDuplicate: (id: string) => void;
  onDelete: (id: string) => void;
}

const getCategoryConfig = (category: DevopsPromptCategory) => {
  const configs: Record<DevopsPromptCategory, { bg: string; text: string; label: string }> = {
    review: { bg: 'bg-theme-info/10', text: 'text-theme-info', label: 'Review' },
    implement: { bg: 'bg-theme-success/10', text: 'text-theme-success', label: 'Implement' },
    security: { bg: 'bg-theme-error/10', text: 'text-theme-error', label: 'Security' },
    deploy: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', label: 'Deploy' },
    docs: { bg: 'bg-theme-primary/10', text: 'text-theme-primary', label: 'Docs' },
    custom: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: 'Custom' },
    general: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', label: 'General' },
    agent: { bg: 'bg-theme-primary/10', text: 'text-theme-primary', label: 'Agent' },
    workflow: { bg: 'bg-theme-info/10', text: 'text-theme-info', label: 'Workflow' },
  };
  return configs[category] || configs.custom;
};

const CategoryBadge: React.FC<{ category: DevopsPromptCategory }> = ({ category }) => {
  const config = getCategoryConfig(category);
  return (
    <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text}`}>
      {config.label}
    </span>
  );
};

const TemplateCard: React.FC<{
  template: DevopsPromptTemplate;
  onEdit: () => void;
  onPreview: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
}> = ({ template, onEdit, onPreview, onDuplicate, onDelete }) => {
  const [showMenu, setShowMenu] = React.useState(false);

  return (
    <div className="bg-theme-surface rounded-lg border border-theme hover:border-theme-primary transition-colors">
      <button
        onClick={onEdit}
        className="w-full p-4 text-left"
      >
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-primary/10 rounded-lg">
              <FileText className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <h3 className="font-medium text-theme-primary">{template.name}</h3>
              <p className="text-sm text-theme-tertiary">{template.slug}</p>
            </div>
          </div>
          <CategoryBadge category={template.category} />
        </div>

        {template.description && (
          <p className="mt-3 text-sm text-theme-secondary line-clamp-2">
            {template.description}
          </p>
        )}

        <div className="mt-4 flex items-center gap-4 text-xs text-theme-tertiary">
          <span className="flex items-center gap-1">
            <Tag className="w-3 h-3" />
            {template.variable_names.length} variables
          </span>
          <span>{template.usage_count} uses</span>
          {!template.is_active && (
            <span className="text-theme-warning">Inactive</span>
          )}
        </div>
      </button>

      <div className="px-4 pb-4 flex items-center justify-between border-t border-theme pt-3 mt-3">
        <div className="flex items-center gap-2">
          <Button
            onClick={(e) => {
              e.stopPropagation();
              onPreview();
            }}
            variant="secondary"
            size="sm"
          >
            <Eye className="w-4 h-4 mr-1" />
            Preview
          </Button>
        </div>

        <div className="relative">
          <Button
            onClick={(e) => {
              e.stopPropagation();
              setShowMenu(!showMenu);
            }}
            variant="ghost"
            size="sm"
          >
            <MoreVertical className="w-4 h-4" />
          </Button>

          {showMenu && (
            <>
              <div
                className="fixed inset-0 z-10"
                onClick={() => setShowMenu(false)}
              />
              <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface rounded-lg shadow-lg border border-theme z-20">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDuplicate();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                >
                  <Copy className="w-4 h-4" />
                  Duplicate
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDelete();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-error hover:bg-theme-error/10 flex items-center gap-2"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export const PromptTemplateList: React.FC<PromptTemplateListProps> = ({
  templates,
  loading,
  onEdit,
  onPreview,
  onDuplicate,
  onDelete,
}) => {
  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (templates.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
        <FileText className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          No Prompt Templates Yet
        </h3>
        <p className="text-theme-secondary mb-4">
          Create your first prompt template to use in AI-powered pipelines.
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {templates.map((template) => (
        <TemplateCard
          key={template.id}
          template={template}
          onEdit={() => onEdit(template)}
          onPreview={() => onPreview(template)}
          onDuplicate={() => onDuplicate(template.id)}
          onDelete={() => onDelete(template.id)}
        />
      ))}
    </div>
  );
};

export default PromptTemplateList;
