import React from 'react';
import { X } from 'lucide-react';

interface TemplateVariable {
  name: string;
  default: string;
  description: string;
}

interface TriggerConfig {
  type: string;
  events: string[];
  cron: string;
  description: string;
  filters: Record<string, unknown>;
}

export interface TemplateFormData {
  name: string;
  description: string;
  category: string;
  template_type: string;
  status: string;
  visibility: string;
  version: string;
  trigger_config: TriggerConfig;
  variables: TemplateVariable[];
  secrets_required: string[];
  integrations_required: string[];
  tags: string[];
  input_schema: Record<string, unknown>;
  output_schema: Record<string, unknown>;
  workflow_definition: Record<string, unknown>;
  usage_guide: string;
}

const CATEGORIES = [
  { value: 'code_quality', label: 'Code Quality' },
  { value: 'deployment', label: 'Deployment' },
  { value: 'documentation', label: 'Documentation' },
  { value: 'testing', label: 'Testing' },
  { value: 'security', label: 'Security' },
  { value: 'monitoring', label: 'Monitoring' },
  { value: 'release', label: 'Release' },
  { value: 'custom', label: 'Custom' },
];

const TEMPLATE_TYPES = [
  { value: 'code_review', label: 'Code Review' },
  { value: 'security_scan', label: 'Security Scan' },
  { value: 'test_generation', label: 'Test Generation' },
  { value: 'deployment_validation', label: 'Deployment Validation' },
  { value: 'release_notes', label: 'Release Notes' },
  { value: 'changelog', label: 'Changelog' },
  { value: 'api_docs', label: 'API Docs' },
  { value: 'coverage_analysis', label: 'Coverage Analysis' },
  { value: 'performance_check', label: 'Performance Check' },
  { value: 'custom', label: 'Custom' },
];

const selectClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const inputClass = selectClass;
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

interface BasicInfoTabProps {
  form: TemplateFormData;
  mode: 'create' | 'edit';
  newTag: string;
  onNewTagChange: (value: string) => void;
  onUpdateForm: (updates: Partial<TemplateFormData>) => void;
  onAddTag: () => void;
  onRemoveTag: (index: number) => void;
}

export const BasicInfoTab: React.FC<BasicInfoTabProps> = ({
  form,
  mode,
  newTag,
  onNewTagChange,
  onUpdateForm,
  onAddTag,
  onRemoveTag,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className={labelClass}>Name *</label>
        <input
          type="text"
          value={form.name}
          onChange={(e) => onUpdateForm({ name: e.target.value })}
          placeholder="e.g. Automated Code Review Pipeline"
          className={inputClass}
        />
      </div>
      <div>
        <label className={labelClass}>Description</label>
        <textarea
          value={form.description}
          onChange={(e) => onUpdateForm({ description: e.target.value })}
          rows={3}
          placeholder="Describe what this template does..."
          className={inputClass}
        />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className={labelClass}>Category *</label>
          <select value={form.category} onChange={(e) => onUpdateForm({ category: e.target.value })} className={selectClass}>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div>
          <label className={labelClass}>Type *</label>
          <select value={form.template_type} onChange={(e) => onUpdateForm({ template_type: e.target.value })} className={selectClass}>
            {TEMPLATE_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
        </div>
      </div>
      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className={labelClass}>Version</label>
          <input
            type="text"
            value={form.version}
            onChange={(e) => onUpdateForm({ version: e.target.value })}
            placeholder="1.0.0"
            className={inputClass}
          />
        </div>
        {mode === 'edit' && (
          <>
            <div>
              <label className={labelClass}>Status</label>
              <select value={form.status} onChange={(e) => onUpdateForm({ status: e.target.value })} className={selectClass}>
                <option value="draft">Draft</option>
                <option value="pending_review">Pending Review</option>
                <option value="published">Published</option>
                <option value="archived">Archived</option>
                <option value="deprecated">Deprecated</option>
              </select>
            </div>
            <div>
              <label className={labelClass}>Visibility</label>
              <select value={form.visibility} onChange={(e) => onUpdateForm({ visibility: e.target.value })} className={selectClass}>
                <option value="private">Private</option>
                <option value="team">Team</option>
                <option value="public">Public</option>
                <option value="marketplace">Marketplace</option>
              </select>
            </div>
          </>
        )}
      </div>
      {/* Tags */}
      <div>
        <label className={labelClass}>Tags</label>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {form.tags.map((tag, i) => (
            <span key={i} className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-theme-accent/10 text-theme-accent">
              {tag}
              <button onClick={() => onRemoveTag(i)} className="hover:text-theme-danger">
                <X size={10} />
              </button>
            </span>
          ))}
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            value={newTag}
            onChange={(e) => onNewTagChange(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); onAddTag(); } }}
            placeholder="Add tag and press Enter"
            className={inputClass}
          />
          <button onClick={onAddTag} className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap">
            Add
          </button>
        </div>
      </div>
    </div>
  );
};
