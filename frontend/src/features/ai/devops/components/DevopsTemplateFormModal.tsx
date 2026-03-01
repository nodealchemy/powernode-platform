import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { DevopsTemplate } from '@/shared/services/ai/DevopsApiService';
import { BasicInfoTab } from './BasicInfoTab';
import { TriggerConfigTab } from './TriggerConfigTab';
import { VariablesTab } from './VariablesTab';
import { RequirementsTab } from './RequirementsTab';
import { SchemasTab } from './SchemasTab';
import { WorkflowTab } from './WorkflowTab';
import type { TemplateFormData } from './BasicInfoTab';

export type { TemplateFormData };

type FormTab = 'basic' | 'trigger' | 'variables' | 'requirements' | 'schemas' | 'workflow' | 'guide';

interface TriggerConfig {
  type: string;
  events: string[];
  cron: string;
  description: string;
  filters: Record<string, unknown>;
}

interface TemplateVariable {
  name: string;
  default: string;
  description: string;
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

const inputClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

function safeJsonStringify(obj: unknown): string {
  try { return JSON.stringify(obj, null, 2); } catch { return '{}'; }
}

function safeJsonParse(str: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(str);
    if (typeof parsed === 'object' && parsed !== null) return parsed as Record<string, unknown>;
    return null;
  } catch { return null; }
}

const DevopsTemplateFormModal: React.FC<DevopsTemplateFormModalProps> = ({
  isOpen, onClose, onSave, template, mode, saving,
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
        name: template.name || '', description: template.description || '',
        category: template.category || 'code_quality', template_type: template.template_type || 'code_review',
        status: template.status || 'draft', visibility: template.visibility || 'private',
        version: template.version || '1.0.0',
        trigger_config: {
          type: triggerConfig.type || 'manual', events: triggerConfig.events || [],
          cron: triggerConfig.cron || '', description: triggerConfig.description || '',
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

  const updateForm = (updates: Partial<TemplateFormData>) => setForm(prev => ({ ...prev, ...updates }));

  const updateTrigger = (updates: Partial<TriggerConfig>) =>
    setForm(prev => ({ ...prev, trigger_config: { ...prev.trigger_config, ...updates } }));

  const addToList = (field: 'tags' | 'secrets_required' | 'integrations_required', value: string, setter: (v: string) => void) => {
    const trimmed = value.trim();
    if (!trimmed || form[field].includes(trimmed)) return;
    updateForm({ [field]: [...form[field], trimmed] });
    setter('');
  };

  const removeFromList = (field: 'tags' | 'secrets_required' | 'integrations_required', index: number) =>
    updateForm({ [field]: form[field].filter((_, i) => i !== index) });

  const handleJsonChange = (field: 'input_schema' | 'output_schema' | 'workflow_definition', text: string, setText: (v: string) => void) => {
    setText(text);
    const parsed = safeJsonParse(text);
    if (parsed) {
      updateForm({ [field]: parsed });
      setJsonErrors(prev => { const next = { ...prev }; delete next[field]; return next; });
    } else {
      setJsonErrors(prev => ({ ...prev, [field]: 'Invalid JSON' }));
    }
  };

  const handleSubmit = () => {
    if (Object.keys(jsonErrors).length > 0) return;
    onSave(form);
  };

  const formTabs: { id: FormTab; label: string }[] = [
    { id: 'basic', label: 'Basic Info' }, { id: 'trigger', label: 'Trigger' },
    { id: 'variables', label: 'Variables' }, { id: 'requirements', label: 'Requirements' },
    { id: 'schemas', label: 'Schemas' }, { id: 'workflow', label: 'Workflow' },
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
            <button onClick={onClose} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
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
      {/* Tab Navigation */}
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

      {activeFormTab === 'basic' && (
        <BasicInfoTab
          form={form}
          mode={mode}
          newTag={newTag}
          onNewTagChange={setNewTag}
          onUpdateForm={updateForm}
          onAddTag={() => addToList('tags', newTag, setNewTag)}
          onRemoveTag={(i) => removeFromList('tags', i)}
        />
      )}

      {activeFormTab === 'trigger' && (
        <TriggerConfigTab
          triggerConfig={form.trigger_config}
          onUpdateTrigger={updateTrigger}
        />
      )}

      {activeFormTab === 'variables' && (
        <VariablesTab
          variables={form.variables}
          onAddVariable={() => updateForm({ variables: [...form.variables, { name: '', default: '', description: '' }] })}
          onUpdateVariable={(i, updates) => {
            const newVars = [...form.variables];
            newVars[i] = { ...newVars[i], ...updates };
            updateForm({ variables: newVars });
          }}
          onRemoveVariable={(i) => updateForm({ variables: form.variables.filter((_, idx) => idx !== i) })}
        />
      )}

      {activeFormTab === 'requirements' && (
        <RequirementsTab
          secretsRequired={form.secrets_required}
          integrationsRequired={form.integrations_required}
          newSecret={newSecret}
          newIntegration={newIntegration}
          onNewSecretChange={setNewSecret}
          onNewIntegrationChange={setNewIntegration}
          onAddSecret={() => addToList('secrets_required', newSecret, setNewSecret)}
          onAddIntegration={() => addToList('integrations_required', newIntegration, setNewIntegration)}
          onRemoveSecret={(i) => removeFromList('secrets_required', i)}
          onRemoveIntegration={(i) => removeFromList('integrations_required', i)}
        />
      )}

      {activeFormTab === 'schemas' && (
        <SchemasTab
          inputSchemaText={inputSchemaText}
          outputSchemaText={outputSchemaText}
          jsonErrors={jsonErrors}
          onInputSchemaChange={(text) => handleJsonChange('input_schema', text, setInputSchemaText)}
          onOutputSchemaChange={(text) => handleJsonChange('output_schema', text, setOutputSchemaText)}
        />
      )}

      {activeFormTab === 'workflow' && (
        <WorkflowTab
          workflowText={workflowText}
          workflowDefinition={form.workflow_definition}
          jsonErrors={jsonErrors}
          onWorkflowChange={(text) => handleJsonChange('workflow_definition', text, setWorkflowText)}
        />
      )}

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
              placeholder={`## Template Name\n\n### Setup\n1. Connect your Git provider\n2. Configure the trigger settings\n3. Set variables as needed\n\n### How It Works\nDescribe the pipeline flow...\n\n### Output\nWhat the template produces...`}
            />
          </div>
        </div>
      )}
    </Modal>
  );
};

export default DevopsTemplateFormModal;
