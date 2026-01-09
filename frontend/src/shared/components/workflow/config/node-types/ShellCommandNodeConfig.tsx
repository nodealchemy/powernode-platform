import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const ShellCommandNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <Textarea
        label="Command"
        value={config.configuration.command || ''}
        onChange={(e) => handleConfigChange('command', e.target.value)}
        placeholder="npm run build&#10;# or multi-line commands&#10;echo 'Starting build...'&#10;npm ci&#10;npm run build"
        rows={4}
        description="Shell command(s) to execute"
        required
      />

      <EnhancedSelect
        label="Shell"
        value={config.configuration.shell || 'bash'}
        onChange={(value) => handleConfigChange('shell', value)}
        options={[
          { value: 'bash', label: 'Bash' },
          { value: 'sh', label: 'POSIX Shell (sh)' },
          { value: 'zsh', label: 'Zsh' },
          { value: 'powershell', label: 'PowerShell' }
        ]}
      />

      <Input
        label="Working Directory"
        value={config.configuration.working_directory || ''}
        onChange={(e) => handleConfigChange('working_directory', e.target.value)}
        placeholder="{{checkout_path}} or /path/to/directory"
        description="Directory to run the command from"
      />

      <Input
        label="Command Timeout (seconds)"
        type="number"
        value={config.configuration.timeout_seconds || 300}
        onChange={(e) => handleConfigChange('timeout_seconds', parseInt(e.target.value) || 300)}
        min={1}
        max={3600}
        description="Max time for command to complete"
      />

      <div className="space-y-3 pt-2">
        <Checkbox
          label="Capture Output"
          description="Capture stdout and stderr for use in subsequent nodes"
          checked={config.configuration.capture_output !== false}
          onCheckedChange={(checked) => handleConfigChange('capture_output', checked)}
        />

        <Checkbox
          label="Fail on Error"
          description="Mark node as failed if command returns non-zero exit code"
          checked={config.configuration.fail_on_error !== false}
          onCheckedChange={(checked) => handleConfigChange('fail_on_error', checked)}
        />
      </div>

      <p className="text-xs text-theme-muted italic">
        Use the Advanced tab for workflow control settings like &quot;Continue on Error&quot;.
      </p>

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
        placeholder='{"NODE_ENV": "production", "CI": "true"}'
        rows={3}
        description="Additional environment variables for the command"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">stdout</code> - Command standard output</li>
          <li><code className="text-theme-accent">stderr</code> - Command error output</li>
          <li><code className="text-theme-accent">exit_code</code> - Exit code (0 = success)</li>
          <li><code className="text-theme-accent">duration_ms</code> - Execution time in milliseconds</li>
        </ul>
      </div>

      <div className="p-3 bg-theme-warning/10 rounded-lg border border-theme-warning/30">
        <p className="text-xs text-theme-warning font-medium">
          Security Note
        </p>
        <p className="text-xs text-theme-muted mt-1">
          Certain dangerous commands (rm -rf /, mkfs, etc.) are blocked for safety.
          Commands run in an isolated environment with limited permissions.
        </p>
      </div>
    </div>
  );
};
