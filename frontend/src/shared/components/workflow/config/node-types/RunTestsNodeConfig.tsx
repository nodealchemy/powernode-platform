import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const RunTestsNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const framework = config.configuration.test_framework || 'auto';

  // Default commands per framework
  const defaultCommands: Record<string, string> = {
    auto: '',
    jest: 'npm test',
    rspec: 'bundle exec rspec',
    pytest: 'pytest',
    mocha: 'npm test',
    cypress: 'npx cypress run',
    playwright: 'npx playwright test',
    custom: ''
  };

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Test Framework"
        value={framework}
        onChange={(value) => {
          handleConfigChange('test_framework', value);
          // Set default command when framework changes
          if (value !== 'custom' && !config.configuration.test_command) {
            handleConfigChange('test_command', defaultCommands[value] || '');
          }
        }}
        options={[
          { value: 'auto', label: 'Auto-detect' },
          { value: 'jest', label: 'Jest (JavaScript/TypeScript)' },
          { value: 'rspec', label: 'RSpec (Ruby)' },
          { value: 'pytest', label: 'pytest (Python)' },
          { value: 'mocha', label: 'Mocha (JavaScript)' },
          { value: 'cypress', label: 'Cypress (E2E)' },
          { value: 'playwright', label: 'Playwright (E2E)' },
          { value: 'custom', label: 'Custom Command' }
        ]}
      />

      <Input
        label="Test Command"
        value={config.configuration.test_command || defaultCommands[framework] || ''}
        onChange={(e) => handleConfigChange('test_command', e.target.value)}
        placeholder={defaultCommands[framework] || 'npm test'}
        description="Command to execute tests"
      />

      <Input
        label="Test Pattern"
        value={config.configuration.test_pattern || ''}
        onChange={(e) => handleConfigChange('test_pattern', e.target.value)}
        placeholder="**/*.test.ts, spec/**/*_spec.rb"
        description="Glob pattern for test files to include"
      />

      <Input
        label="Exclude Pattern"
        value={config.configuration.exclude_pattern || ''}
        onChange={(e) => handleConfigChange('exclude_pattern', e.target.value)}
        placeholder="**/node_modules/**, **/vendor/**"
        description="Glob pattern for files to exclude"
      />

      <Input
        label="Working Directory"
        value={config.configuration.working_directory || ''}
        onChange={(e) => handleConfigChange('working_directory', e.target.value)}
        placeholder="{{checkout_path}} or leave empty for default"
        description="Directory to run tests from"
      />

      <Input
        label="Test Timeout (seconds)"
        type="number"
        value={config.configuration.timeout_seconds || 300}
        onChange={(e) => handleConfigChange('timeout_seconds', parseInt(e.target.value) || 300)}
        min={30}
        max={3600}
        description="Max time for test suite to complete"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Run in Parallel"
          description="Execute tests in parallel for faster runs"
          checked={config.configuration.parallel === true}
          onCheckedChange={(checked) => handleConfigChange('parallel', checked)}
        />

        <Checkbox
          label="Generate Coverage Report"
          description="Collect code coverage information"
          checked={config.configuration.coverage === true}
          onCheckedChange={(checked) => handleConfigChange('coverage', checked)}
        />

        <Checkbox
          label="Fail Fast"
          description="Stop on first test failure"
          checked={config.configuration.fail_fast === true}
          onCheckedChange={(checked) => handleConfigChange('fail_fast', checked)}
        />
      </div>

      {config.configuration.coverage && (
        <Input
          label="Coverage Threshold (%)"
          type="number"
          value={config.configuration.coverage_threshold || 80}
          onChange={(e) => handleConfigChange('coverage_threshold', parseInt(e.target.value) || 80)}
          min={0}
          max={100}
          description="Minimum coverage percentage required"
        />
      )}

      <Input
        label="Retry Count"
        type="number"
        value={config.configuration.retry_count || 0}
        onChange={(e) => handleConfigChange('retry_count', parseInt(e.target.value) || 0)}
        min={0}
        max={5}
        description="Number of retries for flaky tests"
      />

      <Textarea
        label="Environment Variables (JSON)"
        value={
          typeof config.configuration.environment === 'object'
            ? JSON.stringify(config.configuration.environment, null, 2)
            : config.configuration.environment || ''
        }
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            handleConfigChange('environment', parsed);
          } catch {
            handleConfigChange('environment', e.target.value);
          }
        }}
        placeholder='{"CI": "true", "NODE_ENV": "test"}'
        rows={3}
      />
    </div>
  );
};
