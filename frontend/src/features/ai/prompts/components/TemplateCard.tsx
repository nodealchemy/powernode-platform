import React, { useState } from 'react';
import type { PromptTemplate, PromptCategory } from '../types';

const getCategoryColor = (category: PromptCategory): string => {
  const colors: Record<PromptCategory, string> = {
    review: 'bg-theme-info/10 text-theme-info',
    implement: 'bg-theme-success/10 text-theme-success',
    security: 'bg-theme-warning/10 text-theme-warning',
    deploy: 'bg-theme-primary/10 text-theme-primary',
    docs: 'bg-theme-tertiary/10 text-theme-tertiary',
    custom: 'bg-theme-secondary/10 text-theme-secondary',
    general: 'bg-theme-surface text-theme-secondary',
    agent: 'bg-theme-info/10 text-theme-info',
    workflow: 'bg-theme-success/10 text-theme-success',
  };
  return colors[category] || colors.custom;
};

interface TemplateCardProps {
  template: PromptTemplate;
  onEdit: () => void;
  onPreview: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
}

export const TemplateCard: React.FC<TemplateCardProps> = ({
  template,
  onEdit,
  onPreview,
  onDuplicate,
  onDelete,
}) => {
  const [showMenu, setShowMenu] = useState(false);

  return (
    <div
      className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-primary transition-colors"
      onClick={onEdit}
    >
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <h4 className="font-medium text-theme-primary truncate">{template.name}</h4>
          <p className="text-xs text-theme-tertiary">/{template.slug}</p>
        </div>
        <span className={`text-xs px-2 py-1 rounded-full ${getCategoryColor(template.category)}`}>
          {template.category}
        </span>
      </div>

      {template.description && (
        <p className="text-sm text-theme-secondary line-clamp-2 mb-3">{template.description}</p>
      )}

      <div className="flex items-center justify-between text-xs text-theme-tertiary">
        <div className="flex items-center gap-3">
          <span>{template.variable_names.length} variables</span>
          <span>{template.usage_count} uses</span>
          <span className={template.is_active ? 'text-theme-success' : 'text-theme-error'}>
            {template.is_active ? 'Active' : 'Inactive'}
          </span>
        </div>

        <div className="relative" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onPreview();
            }}
            className="text-theme-secondary hover:text-theme-primary mr-2"
          >
            Preview
          </button>
          <button
            onClick={() => setShowMenu(!showMenu)}
            className="text-theme-secondary hover:text-theme-primary"
          >
            •••
          </button>
          {showMenu && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setShowMenu(false)} />
              <div className="absolute right-0 top-full mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-20 py-1 min-w-[120px]">
                <button
                  onClick={() => {
                    setShowMenu(false);
                    onDuplicate();
                  }}
                  className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                >
                  Duplicate
                </button>
                <button
                  onClick={() => {
                    setShowMenu(false);
                    onDelete();
                  }}
                  className="w-full text-left px-3 py-2 text-sm text-theme-error hover:bg-theme-surface-hover"
                >
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
