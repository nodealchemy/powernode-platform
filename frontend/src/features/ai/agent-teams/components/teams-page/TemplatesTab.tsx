import React from 'react';
import { Copy } from 'lucide-react';
import { TeamTemplate } from '@/shared/services/ai/TeamsApiService';

interface TemplatesTabProps {
  templates: TeamTemplate[];
  onPublishTemplate: (templateId: string) => void;
}

export const TemplatesTab: React.FC<TemplatesTabProps> = ({ templates, onPublishTemplate }) => {
  if (templates.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Copy size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No templates</h3>
        <p className="text-theme-secondary mb-6">Create team templates for reuse</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {templates.map(template => (
        <div key={template.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <h3 className="font-medium text-theme-primary">{template.name}</h3>
              {template.is_public && <span className="px-2 py-1 text-xs rounded text-theme-success bg-theme-success/10">Published</span>}
              {template.is_system && <span className="px-2 py-1 text-xs rounded text-theme-info bg-theme-info/10">System</span>}
            </div>
            {!template.published_at && (
              <button
                onClick={() => onPublishTemplate(template.id)}
                className="btn-theme btn-theme-success btn-theme-sm"
              >
                Publish
              </button>
            )}
          </div>
          <p className="text-sm text-theme-secondary">{template.description || 'No description'}</p>
          <div className="flex gap-3 text-xs text-theme-secondary mt-2">
            <span>{template.team_topology}</span>
            <span>{template.usage_count} uses</span>
            {template.tags.length > 0 && <span>{template.tags.join(', ')}</span>}
          </div>
        </div>
      ))}
    </div>
  );
};
