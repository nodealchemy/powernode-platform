import React, { useState, useEffect } from 'react';
import { Plus, Trash2, X } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { DevopsTemplate } from '@/shared/services/ai/DevopsApiService';

type FormTab = 'basic' | 'trigger' | 'variables' | 'requirements' | 'schemas' | 'workflow' | 'guide';

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

interface DevopsTemplateFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (data: TemplateFormData) => Promise<void>;
  template?: DevopsTemplate | null;
  mode: 'create' | 'edit';
  saving: boolean;
}

const EMPTY_FORM: TemplateFormData = {
  name: '',
  description: '',
  category: 'code_quality',
  template_type: 'code_review',
  status: 'draft',
  visibility: 'private',
  version: '1.0.0',
  trigger_config: { type: 'manual', events: [], cron: '', description: '', filters: {} },
  variables: [],
  secrets_required: [],
  integrations_required: [],
  tags: [],
  input_schema: {},
  output_schema: {},
  workflow_definition: { nodes: [], edges: [] },
  usage_guide: '',
};

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

const TRIGGER_TYPES = [
  { value: 'manual', label: 'Manual' },
  { value: 'webhook', label: 'Webhook' },
  { value: 'schedule', label: 'Schedule (Cron)' },
];

const selectClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const inputClass = selectClass;
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

function safeJsonStringify(obj: unknown): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch {
    return '{}';
  }
}

function safeJsonParse(str: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(str);
    if (typeof parsed === 'object' && parsed !== null) return parsed as Record<string, unknown>;
    return null;
  } catch {
    return null;
  }
}

const DevopsTemplateFormModal: React.FC<DevopsTemplateFormModalProps> = ({
  isOpen,
  onClose,
  onSave,
  template,
  mode,
  saving,
}) => {
  const [form, setForm] = useState<TemplateFormData>(EMPTY_FORM);
  const [activeFormTab, setActiveFormTab] = useState<FormTab>('basic');
  const [newTag, setNewTag] = useState('');
  const [newSecret, setNewSecret] = useState('');
  const [newIntegration, setNewIntegration] = useState('');
  const [inputSchemaText, setInputSchemaText] = useState('{}');
  const [outputSchemaText, setOutputSchemaText] = useState('{}');
  const [workflowText, setWorkflowText] = useState('{"nodes": [], "edges": []}');
  const [jsonErrors, setJsonErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    if (!isOpen) return;
    setActiveFormTab('basic');
    setJsonErrors({});

    if (mode === 'edit' && template) {
      const triggerConfig = (template.trigger_config || {}) as Partial<TriggerConfig>;
      const newForm: TemplateFormData = {
        name: template.name || '',
        description: template.description || '',
        category: template.category || 'code_quality',
        template_type: template.template_type || 'code_review',
        status: template.status || 'draft',
        visibility: template.visibility || 'private',
        version: template.version || '1.0.0',
        trigger_config: {
          type: triggerConfig.type || 'manual',
          events: triggerConfig.events || [],
          cron: triggerConfig.cron || '',
          description: triggerConfig.description || '',
          filters: triggerConfig.filters || {},
        },
        variables: (template.variables || []) as TemplateVariable[],
        secrets_required: (template.secrets_required || []) as string[],
        integrations_required: (template.integrations_required || []) as string[],
        tags: (template.tags || []) as string[],
        input_schema: (template.input_schema || {}) as Record<string, unknown>,
        output_schema: (template.output_schema || {}) as Record<string, unknown>,
        workflow_definition: (template.workflow_definition || { nodes: [], edges: [] }) as Record<string, unknown>,
        usage_guide: (template.usage_guide || '') as string,
      };
      setForm(newForm);
      setInputSchemaText(safeJsonStringify(newForm.input_schema));
      setOutputSchemaText(safeJsonStringify(newForm.output_schema));
      setWorkflowText(safeJsonStringify(newForm.workflow_definition));
    } else {
      setForm(EMPTY_FORM);
      setInputSchemaText('{}');
      setOutputSchemaText('{}');
      setWorkflowText('{"nodes": [], "edges": []}');
    }
  }, [isOpen, mode, template]);

  const updateForm = (updates: Partial<TemplateFormData>) => {
    setForm(prev => ({ ...prev, ...updates }));
  };

  const updateTrigger = (updates: Partial<TriggerConfig>) => {
    setForm(prev => ({
      ...prev,
      trigger_config: { ...prev.trigger_config, ...updates },
    }));
  };

  // Variable management
  const addVariable = () => {
    updateForm({ variables: [...form.variables, { name: '', default: '', description: '' }] });
  };

  const updateVariable = (index: number, updates: Partial<TemplateVariable>) => {
    const newVars = [...form.variables];
    newVars[index] = { ...newVars[index], ...updates };
    updateForm({ variables: newVars });
  };

  const removeVariable = (index: number) => {
    updateForm({ variables: form.variables.filter((_, i) => i !== index) });
  };

  // Tag-like list helpers
  const addToList = (field: 'tags' | 'secrets_required' | 'integrations_required', value: string, setter: (v: string) => void) => {
    const trimmed = value.trim();
    if (!trimmed || form[field].includes(trimmed)) return;
    updateForm({ [field]: [...form[field], trimmed] });
    setter('');
  };

  const removeFromList = (field: 'tags' | 'secrets_required' | 'integrations_required', index: number) => {
    updateForm({ [field]: form[field].filter((_, i) => i !== index) });
  };

  // JSON field handlers
  const handleJsonChange = (field: 'input_schema' | 'output_schema' | 'workflow_definition', text: string, setText: (v: string) => void) => {
    setText(text);
    const parsed = safeJsonParse(text);
    if (parsed) {
      updateForm({ [field]: parsed });
      setJsonErrors(prev => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    } else {
      setJsonErrors(prev => ({ ...prev, [field]: 'Invalid JSON' }));
    }
  };

  const handleSubmit = () => {
    if (Object.keys(jsonErrors).length > 0) return;
    onSave(form);
  };

  const formTabs: { id: FormTab; label: string }[] = [
    { id: 'basic', label: 'Basic Info' },
    { id: 'trigger', label: 'Trigger' },
    { id: 'variables', label: 'Variables' },
    { id: 'requirements', label: 'Requirements' },
    { id: 'schemas', label: 'Schemas' },
    { id: 'workflow', label: 'Workflow' },
    { id: 'guide', label: 'Usage Guide' },
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={mode === 'create' ? 'Create Template' : 'Edit Template'}
      maxWidth="3xl"
      footer={
        <div className="flex justify-between w-full">
          <div className="text-xs text-theme-secondary">
            {Object.keys(jsonErrors).length > 0 && (
              <span className="text-theme-danger">Fix JSON errors before saving</span>
            )}
          </div>
          <div className="flex gap-3">
            <button onClick={onClose} className="btn-theme btn-theme-secondary btn-theme-sm">
              Cancel
            </button>
            <button
              onClick={handleSubmit}
              disabled={saving || !form.name.trim() || Object.keys(jsonErrors).length > 0}
              className="btn-theme btn-theme-primary btn-theme-sm"
            >
              {saving ? 'Saving...' : mode === 'create' ? 'Create Template' : 'Save Changes'}
            </button>
          </div>
        </div>
      }
    >
      {/* Form Tab Navigation */}
      <div className="border-b border-theme mb-4 -mx-1">
        <nav className="flex gap-1 overflow-x-auto px-1">
          {formTabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveFormTab(tab.id)}
              className={`px-3 py-1.5 text-xs font-medium border-b-2 whitespace-nowrap transition-colors ${
                activeFormTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Basic Info Tab */}
      {activeFormTab === 'basic' && (
        <div className="space-y-4">
          <div>
            <label className={labelClass}>Name *</label>
            <input
              type="text"
              value={form.name}
              onChange={(e) => updateForm({ name: e.target.value })}
              placeholder="e.g. Automated Code Review Pipeline"
              className={inputClass}
            />
          </div>
          <div>
            <label className={labelClass}>Description</label>
            <textarea
              value={form.description}
              onChange={(e) => updateForm({ description: e.target.value })}
              rows={3}
              placeholder="Describe what this template does..."
              className={inputClass}
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>Category *</label>
              <select value={form.category} onChange={(e) => updateForm({ category: e.target.value })} className={selectClass}>
                {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}>Type *</label>
              <select value={form.template_type} onChange={(e) => updateForm({ template_type: e.target.value })} className={selectClass}>
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
                onChange={(e) => updateForm({ version: e.target.value })}
                placeholder="1.0.0"
                className={inputClass}
              />
            </div>
            {mode === 'edit' && (
              <>
                <div>
                  <label className={labelClass}>Status</label>
                  <select value={form.status} onChange={(e) => updateForm({ status: e.target.value })} className={selectClass}>
                    <option value="draft">Draft</option>
                    <option value="pending_review">Pending Review</option>
                    <option value="published">Published</option>
                    <option value="archived">Archived</option>
                    <option value="deprecated">Deprecated</option>
                  </select>
                </div>
                <div>
                  <label className={labelClass}>Visibility</label>
                  <select value={form.visibility} onChange={(e) => updateForm({ visibility: e.target.value })} className={selectClass}>
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
                  <button onClick={() => removeFromList('tags', i)} className="hover:text-theme-danger">
                    <X size={10} />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addToList('tags', newTag, setNewTag); } }}
                placeholder="Add tag and press Enter"
                className={inputClass}
              />
              <button
                onClick={() => addToList('tags', newTag, setNewTag)}
                className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap"
              >
                Add
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Trigger Tab */}
      {activeFormTab === 'trigger' && (
        <div className="space-y-4">
          <div>
            <label className={labelClass}>Trigger Type</label>
            <select value={form.trigger_config.type} onChange={(e) => updateTrigger({ type: e.target.value })} className={selectClass}>
              {TRIGGER_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div>
            <label className={labelClass}>Description</label>
            <input
              type="text"
              value={form.trigger_config.description}
              onChange={(e) => updateTrigger({ description: e.target.value })}
              placeholder="e.g. Triggered on pull request events"
              className={inputClass}
            />
          </div>
          {form.trigger_config.type === 'schedule' && (
            <div>
              <label className={labelClass}>Cron Expression</label>
              <input
                type="text"
                value={form.trigger_config.cron}
                onChange={(e) => updateTrigger({ cron: e.target.value })}
                placeholder="0 2 * * 1 (Every Monday at 2 AM)"
                className={inputClass}
              />
              <p className="text-xs text-theme-secondary mt-1">Standard cron format: minute hour day-of-month month day-of-week</p>
            </div>
          )}
          {form.trigger_config.type === 'webhook' && (
            <div>
              <label className={labelClass}>Webhook Events</label>
              <div className="flex flex-wrap gap-1.5 mb-2">
                {form.trigger_config.events.map((evt, i) => (
                  <span key={i} className="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded bg-theme-info/10 text-theme-info">
                    {evt}
                    <button onClick={() => updateTrigger({ events: form.trigger_config.events.filter((_, idx) => idx !== i) })} className="hover:text-theme-danger">
                      <X size={10} />
                    </button>
                  </span>
                ))}
              </div>
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="e.g. pull_request.opened"
                  className={inputClass}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      const val = (e.target as HTMLInputElement).value.trim();
                      if (val && !form.trigger_config.events.includes(val)) {
                        updateTrigger({ events: [...form.trigger_config.events, val] });
                        (e.target as HTMLInputElement).value = '';
                      }
                    }
                  }}
                />
              </div>
              <p className="text-xs text-theme-secondary mt-1">Press Enter to add each event</p>
            </div>
          )}
          <div>
            <label className={labelClass}>Trigger Filters (JSON)</label>
            <textarea
              value={safeJsonStringify(form.trigger_config.filters)}
              onChange={(e) => {
                const parsed = safeJsonParse(e.target.value);
                if (parsed) updateTrigger({ filters: parsed });
              }}
              rows={4}
              className={`${inputClass} font-mono text-xs`}
              placeholder='{"base_branch": ["main", "develop"]}'
            />
          </div>
        </div>
      )}

      {/* Variables Tab */}
      {activeFormTab === 'variables' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-sm text-theme-secondary">Template variables that users can configure when installing.</p>
            <button onClick={addVariable} className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1">
              <Plus size={14} /> Add Variable
            </button>
          </div>
          {form.variables.length === 0 ? (
            <div className="text-center py-8 text-theme-secondary text-sm border border-dashed border-theme rounded-lg">
              No variables defined. Click "Add Variable" to create one.
            </div>
          ) : (
            <div className="space-y-3">
              {form.variables.map((variable, i) => (
                <div key={i} className="bg-theme-bg border border-theme rounded-lg p-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 grid grid-cols-3 gap-3">
                      <div>
                        <label className="block text-xs text-theme-secondary mb-1">Name *</label>
                        <input
                          type="text"
                          value={variable.name}
                          onChange={(e) => updateVariable(i, { name: e.target.value })}
                          placeholder="variable_name"
                          className={`${inputClass} font-mono`}
                        />
                      </div>
                      <div>
                        <label className="block text-xs text-theme-secondary mb-1">Default Value</label>
                        <input
                          type="text"
                          value={variable.default}
                          onChange={(e) => updateVariable(i, { default: e.target.value })}
                          placeholder="default"
                          className={inputClass}
                        />
                      </div>
                      <div>
                        <label className="block text-xs text-theme-secondary mb-1">Description</label>
                        <input
                          type="text"
                          value={variable.description}
                          onChange={(e) => updateVariable(i, { description: e.target.value })}
                          placeholder="What this variable controls"
                          className={inputClass}
                        />
                      </div>
                    </div>
                    <button onClick={() => removeVariable(i)} className="mt-5 p-1.5 text-theme-secondary hover:text-theme-danger rounded transition-colors">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Requirements Tab */}
      {activeFormTab === 'requirements' && (
        <div className="space-y-6">
          <div>
            <label className={labelClass}>Required Secrets</label>
            <p className="text-xs text-theme-secondary mb-2">Secret keys that must be configured before using this template.</p>
            <div className="flex flex-wrap gap-1.5 mb-2">
              {form.secrets_required.map((secret, i) => (
                <span key={i} className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-warning/10 text-theme-warning font-mono">
                  {secret}
                  <button onClick={() => removeFromList('secrets_required', i)} className="hover:text-theme-danger">
                    <X size={10} />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                value={newSecret}
                onChange={(e) => setNewSecret(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addToList('secrets_required', newSecret, setNewSecret); } }}
                placeholder="e.g. git_provider_token"
                className={`${inputClass} font-mono`}
              />
              <button onClick={() => addToList('secrets_required', newSecret, setNewSecret)} className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap">
                Add
              </button>
            </div>
          </div>
          <div>
            <label className={labelClass}>Required Integrations</label>
            <p className="text-xs text-theme-secondary mb-2">Integration types that must be connected.</p>
            <div className="flex flex-wrap gap-1.5 mb-2">
              {form.integrations_required.map((integration, i) => (
                <span key={i} className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-info/10 text-theme-info">
                  {integration}
                  <button onClick={() => removeFromList('integrations_required', i)} className="hover:text-theme-danger">
                    <X size={10} />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex gap-2">
              <input
                type="text"
                value={newIntegration}
                onChange={(e) => setNewIntegration(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addToList('integrations_required', newIntegration, setNewIntegration); } }}
                placeholder="e.g. git_provider"
                className={inputClass}
              />
              <button onClick={() => addToList('integrations_required', newIntegration, setNewIntegration)} className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap">
                Add
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Schemas Tab */}
      {activeFormTab === 'schemas' && (
        <div className="space-y-4">
          <div>
            <label className={labelClass}>
              Input Schema
              {jsonErrors.input_schema && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.input_schema}</span>}
            </label>
            <p className="text-xs text-theme-secondary mb-2">Define the expected input parameters for this template.</p>
            <textarea
              value={inputSchemaText}
              onChange={(e) => handleJsonChange('input_schema', e.target.value, setInputSchemaText)}
              rows={10}
              className={`${inputClass} font-mono text-xs ${jsonErrors.input_schema ? 'border-theme-danger' : ''}`}
              placeholder='{"param_name": {"type": "string", "required": true, "description": "..."}}'
            />
          </div>
          <div>
            <label className={labelClass}>
              Output Schema
              {jsonErrors.output_schema && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.output_schema}</span>}
            </label>
            <p className="text-xs text-theme-secondary mb-2">Define the expected output structure from this template.</p>
            <textarea
              value={outputSchemaText}
              onChange={(e) => handleJsonChange('output_schema', e.target.value, setOutputSchemaText)}
              rows={10}
              className={`${inputClass} font-mono text-xs ${jsonErrors.output_schema ? 'border-theme-danger' : ''}`}
              placeholder='{"result": {"type": "string"}, "findings": {"type": "array"}}'
            />
          </div>
        </div>
      )}

      {/* Workflow Tab */}
      {activeFormTab === 'workflow' && (
        <div className="space-y-4">
          <div>
            <label className={labelClass}>
              Workflow Definition
              {jsonErrors.workflow_definition && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.workflow_definition}</span>}
            </label>
            <p className="text-xs text-theme-secondary mb-2">
              Define the workflow pipeline with nodes and edges. Each node has an id, type (trigger, action, ai, condition), label, and config.
            </p>
            <textarea
              value={workflowText}
              onChange={(e) => handleJsonChange('workflow_definition', e.target.value, setWorkflowText)}
              rows={20}
              className={`${inputClass} font-mono text-xs ${jsonErrors.workflow_definition ? 'border-theme-danger' : ''}`}
              placeholder={`{
  "nodes": [
    {"id": "trigger", "type": "trigger", "label": "Event", "config": {}},
    {"id": "process", "type": "ai", "label": "Process", "config": {"model": "claude-sonnet-4-5-20250929"}},
    {"id": "output", "type": "action", "label": "Output", "config": {}}
  ],
  "edges": [
    {"source": "trigger", "target": "process"},
    {"source": "process", "target": "output"}
  ]
}`}
            />
          </div>
          {/* Preview */}
          {!jsonErrors.workflow_definition && form.workflow_definition && (
            <div>
              <label className="block text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Pipeline Preview</label>
              <div className="bg-theme-bg border border-theme rounded-lg p-4">
                {(form.workflow_definition as { nodes?: Array<{ id: string; type: string; label: string }> }).nodes?.length ? (
                  <div className="flex flex-wrap items-center gap-2">
                    {((form.workflow_definition as { nodes: Array<{ id: string; type: string; label: string }> }).nodes).map((node, i, arr) => {
                      const nodeColors: Record<string, { bg: string; text: string; border: string; dot: string }> = {
                        trigger: { bg: 'bg-theme-info/15', text: 'text-theme-info', border: 'border-theme-info/30', dot: 'bg-current' },
                        ai: { bg: 'bg-theme-primary/10', text: 'text-theme-primary', border: 'border-theme-primary/25', dot: 'bg-current' },
                        action: { bg: 'bg-theme-success/15', text: 'text-theme-success', border: 'border-theme-success/30', dot: 'bg-current' },
                        condition: { bg: 'bg-theme-warning/15', text: 'text-theme-warning', border: 'border-theme-warning/30', dot: 'bg-current' },
                      };
                      const colors = nodeColors[node.type] || { bg: 'bg-theme-danger/15', text: 'text-theme-danger', border: 'border-theme-danger/30', dot: 'bg-current' };
                      return (
                        <React.Fragment key={node.id || i}>
                          <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs rounded-md font-medium border ${colors.bg} ${colors.text} ${colors.border}`}>
                            <span className={`w-2 h-2 rounded-full ${colors.dot}`} />
                            {node.label || node.id}
                          </div>
                          {i < arr.length - 1 && (
                            <span className="text-theme-secondary/60 text-sm">&rarr;</span>
                          )}
                        </React.Fragment>
                      );
                    })}
                  </div>
                ) : (
                  <p className="text-xs text-theme-secondary">No workflow nodes defined yet.</p>
                )}
              </div>
              {/* Legend */}
              <div className="flex flex-wrap gap-3 mt-2 text-[10px] text-theme-secondary">
                <span className="flex items-center gap-1 text-theme-info"><span className="w-2 h-2 rounded-full bg-current" /> Trigger</span>
                <span className="flex items-center gap-1 text-theme-success"><span className="w-2 h-2 rounded-full bg-current" /> Action</span>
                <span className="flex items-center gap-1 text-theme-primary"><span className="w-2 h-2 rounded-full bg-current" /> AI</span>
                <span className="flex items-center gap-1 text-theme-warning"><span className="w-2 h-2 rounded-full bg-current" /> Condition</span>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Usage Guide Tab */}
      {activeFormTab === 'guide' && (
        <div className="space-y-4">
          <div>
            <label className={labelClass}>Usage Guide</label>
            <p className="text-xs text-theme-secondary mb-2">Write a guide explaining how to set up and use this template. Supports markdown formatting.</p>
            <textarea
              value={form.usage_guide}
              onChange={(e) => updateForm({ usage_guide: e.target.value })}
              rows={18}
              className={inputClass}
              placeholder={`## Template Name

### Setup
1. Connect your Git provider
2. Configure the trigger settings
3. Set variables as needed

### How It Works
Describe the pipeline flow...

### Output
What the template produces...`}
            />
          </div>
        </div>
      )}
    </Modal>
  );
};

export default DevopsTemplateFormModal;
