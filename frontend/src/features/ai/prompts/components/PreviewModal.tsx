import React, { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { PromptTemplate, PromptPreviewResponse } from '../types';

interface PreviewModalProps {
  template: PromptTemplate;
  preview: PromptPreviewResponse | null;
  onClose: () => void;
  onPreview: (variables: Record<string, string>) => void;
}

export const PreviewModal: React.FC<PreviewModalProps> = ({ template, preview, onClose, onPreview }) => {
  const [variables, setVariables] = useState<Record<string, string>>(
    template.variable_names.reduce((acc, name) => ({ ...acc, [name]: '' }), {})
  );

  return (
    <div className="fixed inset-0 bg-theme-bg/80 flex items-center justify-center z-50 p-4">
      <div className="bg-theme-surface rounded-lg border border-theme w-full max-w-4xl max-h-[90vh] overflow-hidden flex flex-col">
        <div className="p-4 border-b border-theme flex items-center justify-between">
          <h3 className="font-medium text-theme-primary">Preview: {template.name}</h3>
          <Button onClick={onClose} variant="ghost" size="sm">
            <X className="w-4 h-4" />
          </Button>
        </div>

        <div className="flex-1 overflow-auto p-4 space-y-4">
          {template.variable_names.length > 0 && (
            <div className="space-y-3">
              <h4 className="text-sm font-medium text-theme-secondary">Variables</h4>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {template.variable_names.map((name) => (
                  <div key={name}>
                    <label className="block text-xs text-theme-tertiary mb-1">{name}</label>
                    <input
                      type="text"
                      value={variables[name] || ''}
                      onChange={(e) => setVariables({ ...variables, [name]: e.target.value })}
                      className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    />
                  </div>
                ))}
              </div>
              <Button onClick={() => onPreview(variables)} variant="secondary" size="sm">
                Render Preview
              </Button>
            </div>
          )}

          <div>
            <h4 className="text-sm font-medium text-theme-secondary mb-2">
              {preview ? 'Rendered Content' : 'Raw Content'}
            </h4>
            <pre className="bg-theme-surface border border-theme rounded-lg p-4 text-sm text-theme-primary font-mono whitespace-pre-wrap overflow-x-auto">
              {preview ? preview.rendered_content : template.content}
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
};
