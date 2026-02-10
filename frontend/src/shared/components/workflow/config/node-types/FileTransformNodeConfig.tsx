import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const FileTransformNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const sourceFormat = config.configuration.source_format || 'json';
  const targetFormat = config.configuration.target_format || 'csv';

  const formatOptions = [
    { value: 'json', label: 'JSON' },
    { value: 'csv', label: 'CSV' },
    { value: 'xml', label: 'XML' },
    { value: 'yaml', label: 'YAML' },
    { value: 'tsv', label: 'TSV (Tab-separated)' }
  ];

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Input
        label="Input Variable"
        value={config.configuration.input_variable || ''}
        onChange={(e) => handleConfigChange('input_variable', e.target.value)}
        placeholder="{{previous_node.output}} or {{file_content}}"
        description="Variable containing the data to transform"
        required
      />

      <div className="grid grid-cols-2 gap-3">
        <EnhancedSelect
          label="Source Format"
          value={sourceFormat}
          onChange={(value) => handleConfigChange('source_format', value)}
          options={formatOptions}
        />

        <EnhancedSelect
          label="Target Format"
          value={targetFormat}
          onChange={(value) => handleConfigChange('target_format', value)}
          options={formatOptions}
        />
      </div>

      <Input
        label="Output Variable"
        value={config.configuration.output_variable || 'transformed_data'}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="transformed_data"
        description="Variable name to store the result"
      />

      {/* CSV-specific options */}
      {(sourceFormat === 'csv' || targetFormat === 'csv' || sourceFormat === 'tsv' || targetFormat === 'tsv') && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
          <p className="text-sm font-medium text-theme-primary mb-3">CSV/TSV Options</p>
          <div className="space-y-3">
            <Input
              label="Delimiter"
              value={config.configuration.delimiter || (sourceFormat === 'tsv' || targetFormat === 'tsv' ? '\t' : ',')}
              onChange={(e) => handleConfigChange('delimiter', e.target.value)}
              placeholder=","
              description="Field separator character"
            />

            <Input
              label="Quote Character"
              value={config.configuration.quote_char || '"'}
              onChange={(e) => handleConfigChange('quote_char', e.target.value)}
              placeholder='"'
              description="Character used to quote fields"
            />

            <Checkbox
              label="Has Header Row"
              description="First row contains column names"
              checked={config.configuration.has_headers !== false}
              onCheckedChange={(checked) => handleConfigChange('has_headers', checked)}
            />

            {targetFormat === 'csv' && (
              <Checkbox
                label="Include Headers in Output"
                description="Add header row to CSV output"
                checked={config.configuration.include_headers !== false}
                onCheckedChange={(checked) => handleConfigChange('include_headers', checked)}
              />
            )}
          </div>
        </div>
      )}

      {/* JSON-specific options */}
      {targetFormat === 'json' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
          <p className="text-sm font-medium text-theme-primary mb-3">JSON Options</p>
          <div className="space-y-3">
            <Checkbox
              label="Pretty Print"
              description="Format JSON with indentation"
              checked={config.configuration.pretty_print === true}
              onCheckedChange={(checked) => handleConfigChange('pretty_print', checked)}
            />

            <EnhancedSelect
              label="Array Handling"
              value={config.configuration.array_handling || 'preserve'}
              onChange={(value) => handleConfigChange('array_handling', value)}
              options={[
                { value: 'preserve', label: 'Preserve Arrays' },
                { value: 'flatten', label: 'Flatten to Objects' },
                { value: 'first', label: 'Take First Element' }
              ]}
            />
          </div>
        </div>
      )}

      {/* XML-specific options */}
      {(sourceFormat === 'xml' || targetFormat === 'xml') && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
          <p className="text-sm font-medium text-theme-primary mb-3">XML Options</p>
          <div className="space-y-3">
            <Input
              label="Root Element"
              value={config.configuration.root_element || 'root'}
              onChange={(e) => handleConfigChange('root_element', e.target.value)}
              placeholder="root"
              description="Name of the root XML element"
            />

            <Input
              label="Item Element"
              value={config.configuration.item_element || 'item'}
              onChange={(e) => handleConfigChange('item_element', e.target.value)}
              placeholder="item"
              description="Name for array item elements"
            />

            <Checkbox
              label="Include XML Declaration"
              description='Add <?xml version="1.0"?> header'
              checked={config.configuration.include_declaration !== false}
              onCheckedChange={(checked) => handleConfigChange('include_declaration', checked)}
            />
          </div>
        </div>
      )}

      {/* Field Mapping */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Field Mapping (Optional)</p>
        <Textarea
          label="Column/Field Mapping (JSON)"
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
          placeholder={'{\n  "old_column_name": "new_column_name",\n  "user_id": "id",\n  "full_name": "name"\n}'}
          rows={4}
          description="Rename fields during transformation"
        />
      </div>

      {/* Filter Options */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Data Filtering (Optional)</p>
        <div className="space-y-3">
          <Input
            label="Include Fields"
            value={config.configuration.include_fields || ''}
            onChange={(e) => handleConfigChange('include_fields', e.target.value)}
            placeholder="field1, field2, field3"
            description="Only include these fields (comma-separated)"
          />

          <Input
            label="Exclude Fields"
            value={config.configuration.exclude_fields || ''}
            onChange={(e) => handleConfigChange('exclude_fields', e.target.value)}
            placeholder="internal_id, created_at"
            description="Remove these fields from output"
          />
        </div>
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">transformed_data</code> - The transformed data (or custom name)</li>
          <li><code className="text-theme-accent">row_count</code> - Number of rows/items processed</li>
          <li><code className="text-theme-accent">source_format</code> - Original format detected</li>
          <li><code className="text-theme-accent">target_format</code> - Output format used</li>
        </ul>
      </div>
    </div>
  );
};
