import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const ConditionNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const conditionType = config.configuration.condition_type || 'comparison';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Condition Type"
        value={conditionType}
        onChange={(value) => handleConfigChange('condition_type', value)}
        options={[
          { value: 'comparison', label: 'Simple Comparison' },
          { value: 'expression', label: 'JavaScript Expression' },
          { value: 'contains', label: 'Contains Check' },
          { value: 'regex', label: 'Regex Pattern Match' },
          { value: 'exists', label: 'Value Exists' },
          { value: 'type', label: 'Type Check' }
        ]}
      />

      {/* Simple Comparison Mode */}
      {conditionType === 'comparison' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme space-y-3">
          <Input
            label="Left Value"
            value={config.configuration.left_value || ''}
            onChange={(e) => handleConfigChange('left_value', e.target.value)}
            placeholder="{{variable}} or literal value"
            description="Value to compare (left side)"
          />

          <EnhancedSelect
            label="Operator"
            value={config.configuration.operator || 'equals'}
            onChange={(value) => handleConfigChange('operator', value)}
            options={[
              { value: 'equals', label: 'Equals (==)' },
              { value: 'not_equals', label: 'Not Equals (!=)' },
              { value: 'strict_equals', label: 'Strict Equals (===)' },
              { value: 'greater_than', label: 'Greater Than (>)' },
              { value: 'greater_than_or_equal', label: 'Greater or Equal (>=)' },
              { value: 'less_than', label: 'Less Than (<)' },
              { value: 'less_than_or_equal', label: 'Less or Equal (<=)' },
              { value: 'starts_with', label: 'Starts With' },
              { value: 'ends_with', label: 'Ends With' },
              { value: 'in', label: 'In Array' },
              { value: 'not_in', label: 'Not In Array' }
            ]}
          />

          <Input
            label="Right Value"
            value={config.configuration.right_value || ''}
            onChange={(e) => handleConfigChange('right_value', e.target.value)}
            placeholder="{{variable}} or literal value"
            description="Value to compare against (right side)"
          />
        </div>
      )}

      {/* JavaScript Expression Mode */}
      {conditionType === 'expression' && (
        <div className="space-y-3">
          <Textarea
            label="Condition Expression"
            value={config.configuration.expression || ''}
            onChange={(e) => handleConfigChange('expression', e.target.value)}
            placeholder="{{user.age}} >= 18 && {{user.status}} === 'active'"
            rows={3}
            description="JavaScript expression that evaluates to true/false"
          />
          <p className="text-xs text-theme-muted">
            Variables: Use {'{{variableName}}'} syntax. Supports standard JS operators.
          </p>
        </div>
      )}

      {/* Contains Check Mode */}
      {conditionType === 'contains' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme space-y-3">
          <Input
            label="Source Value"
            value={config.configuration.source_value || ''}
            onChange={(e) => handleConfigChange('source_value', e.target.value)}
            placeholder="{{array}} or {{string}}"
            description="Array or string to search in"
          />

          <Input
            label="Search Value"
            value={config.configuration.search_value || ''}
            onChange={(e) => handleConfigChange('search_value', e.target.value)}
            placeholder="value to find"
            description="Value to look for"
          />

          <Checkbox
            label="Case Insensitive"
            description="Ignore case when comparing strings"
            checked={config.configuration.case_insensitive === true}
            onCheckedChange={(checked) => handleConfigChange('case_insensitive', checked)}
          />
        </div>
      )}

      {/* Regex Pattern Mode */}
      {conditionType === 'regex' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme space-y-3">
          <Input
            label="Test Value"
            value={config.configuration.test_value || ''}
            onChange={(e) => handleConfigChange('test_value', e.target.value)}
            placeholder="{{variable}}"
            description="String to test against pattern"
          />

          <Input
            label="Pattern"
            value={config.configuration.pattern || ''}
            onChange={(e) => handleConfigChange('pattern', e.target.value)}
            placeholder="^[a-z]+@[a-z]+\\.[a-z]+$"
            description="Regular expression pattern"
          />

          <Input
            label="Flags"
            value={config.configuration.regex_flags || 'i'}
            onChange={(e) => handleConfigChange('regex_flags', e.target.value)}
            placeholder="i, g, m"
            description="Regex flags (i=ignore case, g=global, m=multiline)"
          />
        </div>
      )}

      {/* Value Exists Mode */}
      {conditionType === 'exists' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme space-y-3">
          <Input
            label="Variable Path"
            value={config.configuration.variable_path || ''}
            onChange={(e) => handleConfigChange('variable_path', e.target.value)}
            placeholder="{{user.profile.email}}"
            description="Variable path to check"
          />

          <EnhancedSelect
            label="Check Type"
            value={config.configuration.exists_check || 'not_null'}
            onChange={(value) => handleConfigChange('exists_check', value)}
            options={[
              { value: 'not_null', label: 'Not Null/Undefined' },
              { value: 'truthy', label: 'Truthy Value' },
              { value: 'not_empty', label: 'Not Empty (string/array)' },
              { value: 'defined', label: 'Property Defined' }
            ]}
          />
        </div>
      )}

      {/* Type Check Mode */}
      {conditionType === 'type' && (
        <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme space-y-3">
          <Input
            label="Variable"
            value={config.configuration.type_check_value || ''}
            onChange={(e) => handleConfigChange('type_check_value', e.target.value)}
            placeholder="{{variable}}"
            description="Variable to check type of"
          />

          <EnhancedSelect
            label="Expected Type"
            value={config.configuration.expected_type || 'string'}
            onChange={(value) => handleConfigChange('expected_type', value)}
            options={[
              { value: 'string', label: 'String' },
              { value: 'number', label: 'Number' },
              { value: 'boolean', label: 'Boolean' },
              { value: 'array', label: 'Array' },
              { value: 'object', label: 'Object' },
              { value: 'null', label: 'Null' },
              { value: 'undefined', label: 'Undefined' }
            ]}
          />
        </div>
      )}

      {/* Output Configuration */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Branch Outputs</p>

        <div className="space-y-3">
          <Input
            label="True Branch Label"
            value={config.configuration.true_label || 'Yes'}
            onChange={(e) => handleConfigChange('true_label', e.target.value)}
            placeholder="Yes"
            description="Label for the 'true' output"
          />

          <Input
            label="False Branch Label"
            value={config.configuration.false_label || 'No'}
            onChange={(e) => handleConfigChange('false_label', e.target.value)}
            placeholder="No"
            description="Label for the 'false' output"
          />
        </div>
      </div>

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Invert Result"
          description="Negate the condition result (NOT)"
          checked={config.configuration.invert_result === true}
          onCheckedChange={(checked) => handleConfigChange('invert_result', checked)}
        />

        <Checkbox
          label="Default to False"
          description="Return false if evaluation errors occur"
          checked={config.configuration.default_false !== false}
          onCheckedChange={(checked) => handleConfigChange('default_false', checked)}
        />
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">result</code> - Boolean condition result</li>
          <li><code className="text-theme-accent">branch</code> - Branch taken (&apos;true&apos; or &apos;false&apos;)</li>
          <li><code className="text-theme-accent">evaluated</code> - Values used in evaluation</li>
        </ul>
      </div>
    </div>
  );
};
