import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const TransformNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const transformType = config.configuration.transform_type || 'javascript';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="Input Variable"
        value={config.configuration.input_variable || ''}
        onChange={(e) => handleConfigChange('input_variable', e.target.value)}
        placeholder="{{previous_node.output}} or {{data}}"
        description="Variable containing data to transform"
      />

      <EnhancedSelect
        label="Transform Type"
        value={transformType}
        onChange={(value) => handleConfigChange('transform_type', value)}
        options={[
          { value: 'javascript', label: 'JavaScript Expression' },
          { value: 'jmespath', label: 'JMESPath Query' },
          { value: 'template', label: 'Template String' },
          { value: 'mapping', label: 'Field Mapping' },
          { value: 'pick', label: 'Pick Fields' },
          { value: 'omit', label: 'Omit Fields' }
        ]}
      />

      {/* JavaScript Expression */}
      {transformType === 'javascript' && (
        <div className="space-y-3">
          <Textarea
            label="Transform Expression"
            value={config.configuration.expression || ''}
            onChange={(e) => handleConfigChange('expression', e.target.value)}
            placeholder={'// Access input via `input` variable\n{\n  id: input.user_id,\n  fullName: `${input.first_name} ${input.last_name}`,\n  createdAt: new Date().toISOString()\n}'}
            rows={6}
            description="JavaScript expression to transform data"
          />
          <p className="text-xs text-theme-muted">
            Access input via <code className="text-theme-accent">input</code> variable. Return transformed value.
          </p>
        </div>
      )}

      {/* JMESPath Query */}
      {transformType === 'jmespath' && (
        <div className="space-y-3">
          <Textarea
            label="JMESPath Expression"
            value={config.configuration.jmespath || ''}
            onChange={(e) => handleConfigChange('jmespath', e.target.value)}
            placeholder="people[?age > `20`].{name: name, email: email}"
            rows={3}
            description="JMESPath query to extract/transform data"
          />
          <div className="p-2 bg-theme-surface rounded border border-theme">
            <p className="text-xs text-theme-muted">
              Examples: <code className="text-theme-accent">users[*].name</code> (get all names),{' '}
              <code className="text-theme-accent">data.items | [0]</code> (first item)
            </p>
          </div>
        </div>
      )}

      {/* Template String */}
      {transformType === 'template' && (
        <div className="space-y-3">
          <Textarea
            label="Template"
            value={config.configuration.template || ''}
            onChange={(e) => handleConfigChange('template', e.target.value)}
            placeholder={'Hello {{name}},\n\nYour order #{{order_id}} has been confirmed.\nTotal: ${{total}}'}
            rows={5}
            description="Template with variable placeholders"
          />
          <p className="text-xs text-theme-muted">
            Use {'{{variable}}'} syntax for placeholders. Supports nested paths like {'{{user.profile.name}}'}.
          </p>
        </div>
      )}

      {/* Field Mapping */}
      {transformType === 'mapping' && (
        <div className="space-y-3">
          <Textarea
            label="Field Mappings (JSON)"
            value={
              typeof config.configuration.field_mapping === 'object'
                ? JSON.stringify(config.configuration.field_mapping, null, 2)
                : config.configuration.field_mapping || ''
            }
            onChange={(e) => {
              try {
                const parsed = JSON.parse(e.target.value);
                handleConfigChange('field_mapping', parsed);
              } catch (_error) {
                handleConfigChange('field_mapping', e.target.value);
              }
            }}
            placeholder={'{\n  "userId": "user_id",\n  "fullName": "{{first_name}} {{last_name}}",\n  "email": "contact.email",\n  "timestamp": "$NOW"\n}'}
            rows={6}
            description="Map source fields to target fields"
          />
          <div className="p-2 bg-theme-surface rounded border border-theme">
            <p className="text-xs text-theme-muted">
              Special values: <code className="text-theme-accent">$NOW</code> (timestamp),{' '}
              <code className="text-theme-accent">$UUID</code> (generate ID)
            </p>
          </div>
        </div>
      )}

      {/* Pick Fields */}
      {transformType === 'pick' && (
        <div className="space-y-3">
          <Input
            label="Fields to Include"
            value={config.configuration.pick_fields || ''}
            onChange={(e) => handleConfigChange('pick_fields', e.target.value)}
            placeholder="id, name, email, profile.avatar"
            description="Comma-separated list of fields to keep"
          />
          <Checkbox
            label="Deep Pick"
            description="Support nested paths (e.g., profile.name)"
            checked={config.configuration.deep_pick !== false}
            onCheckedChange={(checked) => handleConfigChange('deep_pick', checked)}
          />
        </div>
      )}

      {/* Omit Fields */}
      {transformType === 'omit' && (
        <div className="space-y-3">
          <Input
            label="Fields to Exclude"
            value={config.configuration.omit_fields || ''}
            onChange={(e) => handleConfigChange('omit_fields', e.target.value)}
            placeholder="password, internal_id, __metadata"
            description="Comma-separated list of fields to remove"
          />
          <Checkbox
            label="Deep Omit"
            description="Remove nested paths (e.g., profile.internal)"
            checked={config.configuration.deep_omit === true}
            onCheckedChange={(checked) => handleConfigChange('deep_omit', checked)}
          />
        </div>
      )}

      {/* Output Configuration */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Output Configuration</p>

        <div className="space-y-3">
          <Input
            label="Output Variable"
            value={config.configuration.output_variable || 'transformed'}
            onChange={(e) => handleConfigChange('output_variable', e.target.value)}
            placeholder="transformed"
            description="Variable name to store result"
          />

          <Checkbox
            label="Preserve Original"
            description="Keep original input alongside transformed output"
            checked={config.configuration.preserve_original === true}
            onCheckedChange={(checked) => handleConfigChange('preserve_original', checked)}
          />
        </div>
      </div>

      {/* Error Handling */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Error Handling</p>

        <div className="space-y-3">
          <EnhancedSelect
            label="On Transform Error"
            value={config.configuration.on_error || 'fail'}
            onChange={(value) => handleConfigChange('on_error', value)}
            options={[
              { value: 'fail', label: 'Fail Node' },
              { value: 'null', label: 'Return Null' },
              { value: 'original', label: 'Return Original Input' },
              { value: 'default', label: 'Return Default Value' }
            ]}
          />

          {config.configuration.on_error === 'default' && (
            <Textarea
              label="Default Value (JSON)"
              value={
                typeof config.configuration.default_value === 'object'
                  ? JSON.stringify(config.configuration.default_value, null, 2)
                  : config.configuration.default_value || ''
              }
              onChange={(e) => {
                try {
                  const parsed = JSON.parse(e.target.value);
                  handleConfigChange('default_value', parsed);
                } catch (_error) {
                  handleConfigChange('default_value', e.target.value);
                }
              }}
              placeholder='{"status": "error", "data": null}'
              rows={3}
            />
          )}
        </div>
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">transformed</code> - Transformed result (or custom name)</li>
          <li><code className="text-theme-accent">original</code> - Original input (if preserved)</li>
          <li><code className="text-theme-accent">success</code> - Transform success status</li>
        </ul>
      </div>
    </div>
  );
};
