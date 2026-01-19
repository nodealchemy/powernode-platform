import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const LoopNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const loopType = config.configuration.loop_type || 'for_each';
  const executionMode = config.configuration.execution_mode || 'sequential';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Loop Type"
        value={loopType}
        onChange={(value) => handleConfigChange('loop_type', value)}
        options={[
          { value: 'for_each', label: 'For Each Item' },
          { value: 'while', label: 'While Condition' },
          { value: 'count', label: 'Fixed Count' },
          { value: 'until', label: 'Until Condition' }
        ]}
      />

      {/* For Each Configuration */}
      {loopType === 'for_each' && (
        <div className="space-y-3">
          <Input
            label="Collection Variable"
            value={config.configuration.collection || ''}
            onChange={(e) => handleConfigChange('collection', e.target.value)}
            placeholder="{{items}} or {{data.records}}"
            description="Array to iterate over"
            required
          />

          <Input
            label="Item Variable Name"
            value={config.configuration.item_variable || 'item'}
            onChange={(e) => handleConfigChange('item_variable', e.target.value)}
            placeholder="item"
            description="Name for current item in each iteration"
          />

          <Input
            label="Index Variable Name"
            value={config.configuration.index_variable || 'index'}
            onChange={(e) => handleConfigChange('index_variable', e.target.value)}
            placeholder="index"
            description="Name for current index (0-based)"
          />
        </div>
      )}

      {/* While Loop Configuration */}
      {loopType === 'while' && (
        <div className="space-y-3">
          <Input
            label="Condition Expression"
            value={config.configuration.condition || ''}
            onChange={(e) => handleConfigChange('condition', e.target.value)}
            placeholder="{{counter}} < 10"
            description="Continue while this is true"
          />

          <Checkbox
            label="Check Before Iteration"
            description="Check condition before each iteration (vs. after)"
            checked={config.configuration.check_before !== false}
            onCheckedChange={(checked) => handleConfigChange('check_before', checked)}
          />
        </div>
      )}

      {/* Until Loop Configuration */}
      {loopType === 'until' && (
        <Input
          label="Termination Condition"
          value={config.configuration.until_condition || ''}
          onChange={(e) => handleConfigChange('until_condition', e.target.value)}
          placeholder="{{result.status}} === 'complete'"
          description="Stop when this becomes true"
        />
      )}

      {/* Count Loop Configuration */}
      {loopType === 'count' && (
        <div className="space-y-3">
          <Input
            label="Iteration Count"
            type="number"
            value={config.configuration.count || 10}
            onChange={(e) => handleConfigChange('count', parseInt(e.target.value) || 10)}
            min={1}
            max={10000}
            description="Number of iterations to execute"
          />

          <Input
            label="Counter Variable Name"
            value={config.configuration.counter_variable || 'i'}
            onChange={(e) => handleConfigChange('counter_variable', e.target.value)}
            placeholder="i"
            description="Variable name for iteration counter"
          />
        </div>
      )}

      {/* Execution Mode */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Execution Mode</p>

        <div className="space-y-3">
          <EnhancedSelect
            label="Mode"
            value={executionMode}
            onChange={(value) => handleConfigChange('execution_mode', value)}
            options={[
              { value: 'sequential', label: 'Sequential (one at a time)' },
              { value: 'parallel', label: 'Parallel (concurrent)' },
              { value: 'batch', label: 'Batch (parallel in groups)' }
            ]}
          />

          {executionMode === 'parallel' && (
            <Input
              label="Parallel Limit"
              type="number"
              value={config.configuration.parallel_limit || 5}
              onChange={(e) => handleConfigChange('parallel_limit', parseInt(e.target.value) || 5)}
              min={1}
              max={100}
              description="Max concurrent iterations"
            />
          )}

          {executionMode === 'batch' && (
            <Input
              label="Batch Size"
              type="number"
              value={config.configuration.batch_size || 10}
              onChange={(e) => handleConfigChange('batch_size', parseInt(e.target.value) || 10)}
              min={1}
              max={1000}
              description="Items per batch"
            />
          )}
        </div>
      </div>

      {/* Loop Controls */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Loop Controls</p>

        <div className="space-y-3">
          <Input
            label="Max Iterations"
            type="number"
            value={config.configuration.max_iterations || 100}
            onChange={(e) => handleConfigChange('max_iterations', parseInt(e.target.value) || 100)}
            min={1}
            max={100000}
            description="Safety limit to prevent infinite loops"
          />

          <Input
            label="Timeout Per Item (seconds)"
            type="number"
            value={config.configuration.timeout_per_item || 60}
            onChange={(e) => handleConfigChange('timeout_per_item', parseInt(e.target.value) || 60)}
            min={1}
            max={3600}
            description="Max time for each iteration"
          />

          <Input
            label="Break Condition"
            value={config.configuration.break_condition || ''}
            onChange={(e) => handleConfigChange('break_condition', e.target.value)}
            placeholder="{{item.status}} === 'stop'"
            description="Exit loop early when this is true"
          />
        </div>
      </div>

      {/* Error Handling */}
      <div className="space-y-3 pt-2">
        <Checkbox
          label="Break on Error"
          description="Stop loop if any iteration fails"
          checked={config.configuration.break_on_error === true}
          onCheckedChange={(checked) => handleConfigChange('break_on_error', checked)}
        />

        <Checkbox
          label="Continue on Item Error"
          description="Skip failed items and continue processing"
          checked={config.configuration.continue_on_item_error === true}
          onCheckedChange={(checked) => handleConfigChange('continue_on_item_error', checked)}
        />

        <Checkbox
          label="Collect Errors"
          description="Gather all errors in a separate output"
          checked={config.configuration.collect_errors === true}
          onCheckedChange={(checked) => handleConfigChange('collect_errors', checked)}
        />
      </div>

      {/* Output Configuration */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Output Configuration</p>

        <div className="space-y-3">
          <EnhancedSelect
            label="Output Mode"
            value={config.configuration.output_mode || 'collect_all'}
            onChange={(value) => handleConfigChange('output_mode', value)}
            options={[
              { value: 'collect_all', label: 'Collect All Results' },
              { value: 'last_only', label: 'Last Result Only' },
              { value: 'first_success', label: 'First Successful Result' },
              { value: 'filter', label: 'Filter by Condition' }
            ]}
          />

          {config.configuration.output_mode === 'filter' && (
            <Input
              label="Filter Condition"
              value={config.configuration.filter_condition || ''}
              onChange={(e) => handleConfigChange('filter_condition', e.target.value)}
              placeholder="{{result.valid}} === true"
              description="Only include results matching this"
            />
          )}

          <Input
            label="Results Variable Name"
            value={config.configuration.results_variable || 'results'}
            onChange={(e) => handleConfigChange('results_variable', e.target.value)}
            placeholder="results"
            description="Variable name for collected results"
          />
        </div>
      </div>

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">results</code> - Array of all iteration outputs</li>
          <li><code className="text-theme-accent">iteration_count</code> - Total iterations executed</li>
          <li><code className="text-theme-accent">success_count</code> - Successful iterations</li>
          <li><code className="text-theme-accent">error_count</code> - Failed iterations</li>
          <li><code className="text-theme-accent">errors</code> - Array of errors (if collected)</li>
        </ul>
      </div>
    </div>
  );
};
