import React, { useState } from 'react';
import { Lock } from 'lucide-react';
import {
  isGlobal,
  isClone,
  CloneToCustomizeButton,
  UpdateAvailableBadge,
} from '@/features/content/scoped';
import type { PromptTemplate, PromptCategory } from '../types';

const getCategoryColor = (category: PromptCategory): string => {
  const colors: Record<PromptCategory, string> = {
    review: 'bg-theme-info-fg/10 text-theme-info-fg',
    implement: 'bg-theme-success-fg/10 text-theme-success-fg',
    security: 'bg-theme-warning-fg/10 text-theme-warning-fg',
    deploy: 'bg-theme-primary/10 text-theme-primary',
    docs: 'bg-theme-background-secondary/10 text-theme-tertiary',
    custom: 'bg-theme-surface/10 text-theme-secondary',
    general: 'bg-theme-surface text-theme-secondary',
    agent: 'bg-theme-info-fg/10 text-theme-info-fg',
    workflow: 'bg-theme-success-fg/10 text-theme-success-fg',
  };
  return colors[category] || colors.custom;
};

interface TemplateCardProps {
  template: PromptTemplate;
  onEdit: () => void;
  onPreview: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
  /** Whether the current user may create templates (shows the clone CTA on globals). */
  canClone?: boolean;
  /** Fork this global template into the account (the clone API call). */
  onCloneTemplate?: (id: string) => Promise<PromptTemplate>;
  /** Called with the new editable copy after a successful clone. */
  onCloned?: (copy: PromptTemplate) => void;
  /** Show the "update available" badge (clone whose origin diverged). */
  updateAvailable?: boolean;
  /** Open the update-from-source flow for this clone. */
  onUpdateFromSource?: (id: string) => void;
}

export const TemplateCard: React.FC<TemplateCardProps> = ({
  template,
  onEdit,
  onPreview,
  onDuplicate,
  onDelete,
  canClone = false,
  onCloneTemplate,
  onCloned,
  updateAvailable = false,
  onUpdateFromSource,
}) => {
  const [showMenu, setShowMenu] = useState(false);
  const global = isGlobal(template);
  const clone = isClone(template);

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
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {global && (
            <span
              className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-theme-surface-secondary text-theme-tertiary"
              title="Platform-provided and read-only — clone to customize"
            >
              <Lock className="w-3 h-3" />
              Global
            </span>
          )}
          <span className={`text-xs px-2 py-1 rounded-full ${getCategoryColor(template.category)}`}>
            {template.category}
          </span>
        </div>
      </div>

      {template.description && (
        <p className="text-sm text-theme-secondary line-clamp-2 mb-3">{template.description}</p>
      )}

      <div className="flex items-center justify-between text-xs text-theme-tertiary">
        <div className="flex items-center gap-3">
          <span>{template.variable_names.length} variables</span>
          <span>{template.usage_count} uses</span>
          <span className={template.is_active ? 'text-theme-success-fg' : 'text-theme-error-fg'}>
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
          {/* Global items are read-only: no edit/delete menu, clone instead. */}
          {!global && (
            <>
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
                      className="w-full text-left px-3 py-2 text-sm text-theme-error-fg hover:bg-theme-surface-hover"
                    >
                      Delete
                    </button>
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </div>

      {/* Scope treatment: clone CTA on globals, update badge on clones */}
      {(global || (clone && updateAvailable)) && (
        <div className="mt-3 flex items-center gap-2 flex-wrap" onClick={(e) => e.stopPropagation()}>
          {global && onCloneTemplate && (
            <CloneToCustomizeButton
              canClone={canClone}
              onClone={() => onCloneTemplate(template.id)}
              onCloned={(copy) => onCloned?.(copy as PromptTemplate)}
            />
          )}
          {clone && updateAvailable && (
            <UpdateAvailableBadge onClick={() => onUpdateFromSource?.(template.id)} />
          )}
        </div>
      )}
    </div>
  );
};
