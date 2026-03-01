import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const FileNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const operation = config.configuration.operation || 'read';
  const storageProvider = config.configuration.storage_provider || 's3';
  const showContent = operation === 'write' || operation === 'append';
  const showSourceDest = operation === 'copy' || operation === 'move';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      <EnhancedSelect
        label="Storage Provider"
        value={storageProvider}
        onChange={(value) => handleConfigChange('storage_provider', value)}
        options={[
          { value: 's3', label: 'Amazon S3' },
          { value: 'gcs', label: 'Google Cloud Storage' },
          { value: 'azure', label: 'Azure Blob Storage' },
          { value: 'local', label: 'Local Storage' }
        ]}
      />

      <EnhancedSelect
        label="Operation"
        value={operation}
        onChange={(value) => handleConfigChange('operation', value)}
        options={[
          { value: 'read', label: 'Read File' },
          { value: 'write', label: 'Write File' },
          { value: 'append', label: 'Append to File' },
          { value: 'delete', label: 'Delete File' },
          { value: 'list', label: 'List Files' },
          { value: 'copy', label: 'Copy File' },
          { value: 'move', label: 'Move File' },
          { value: 'exists', label: 'Check Exists' }
        ]}
      />

      {storageProvider !== 'local' && (
        <Input
          label="Bucket / Container"
          value={config.configuration.bucket || ''}
          onChange={(e) => handleConfigChange('bucket', e.target.value)}
          placeholder="my-bucket-name"
          description="Storage bucket or container name"
        />
      )}

      {operation !== 'list' && !showSourceDest && (
        <Input
          label="Object Key / Path"
          value={config.configuration.object_key || ''}
          onChange={(e) => handleConfigChange('object_key', e.target.value)}
          placeholder="path/to/file.json or {{variable}}"
          description="Full path to the file within the bucket"
        />
      )}

      {operation === 'list' && (
        <>
          <Input
            label="Prefix / Directory"
            value={config.configuration.prefix || ''}
            onChange={(e) => handleConfigChange('prefix', e.target.value)}
            placeholder="uploads/2024/"
            description="Filter objects by prefix"
          />
          <Input
            label="Max Results"
            type="number"
            value={config.configuration.max_results || 100}
            onChange={(e) => handleConfigChange('max_results', parseInt(e.target.value) || 100)}
            min={1}
            max={1000}
            description="Maximum number of files to list"
          />
        </>
      )}

      {showSourceDest && (
        <>
          <Input
            label="Source Path"
            value={config.configuration.source_path || ''}
            onChange={(e) => handleConfigChange('source_path', e.target.value)}
            placeholder="source/path/file.txt"
            description="Source file location"
          />
          <Input
            label="Destination Path"
            value={config.configuration.destination_path || ''}
            onChange={(e) => handleConfigChange('destination_path', e.target.value)}
            placeholder="destination/path/file.txt"
            description="Target file location"
          />
          <Input
            label="Destination Bucket"
            value={config.configuration.destination_bucket || ''}
            onChange={(e) => handleConfigChange('destination_bucket', e.target.value)}
            placeholder="Leave empty for same bucket"
            description="Optional: different destination bucket"
          />
        </>
      )}

      {showContent && (
        <>
          <Textarea
            label="Content"
            value={config.configuration.content || ''}
            onChange={(e) => handleConfigChange('content', e.target.value)}
            placeholder="File content or {{variable}}"
            rows={4}
            description="Content to write to the file"
          />

          <EnhancedSelect
            label="Content Type"
            value={config.configuration.content_type || 'auto'}
            onChange={(value) => handleConfigChange('content_type', value)}
            options={[
              { value: 'auto', label: 'Auto-detect' },
              { value: 'application/json', label: 'JSON' },
              { value: 'text/plain', label: 'Plain Text' },
              { value: 'text/csv', label: 'CSV' },
              { value: 'application/xml', label: 'XML' },
              { value: 'text/html', label: 'HTML' },
              { value: 'application/octet-stream', label: 'Binary' }
            ]}
          />
        </>
      )}

      <div className="space-y-3 pt-2">
        {operation === 'write' && (
          <Checkbox
            label="Overwrite Existing"
            description="Replace file if it already exists"
            checked={config.configuration.overwrite !== false}
            onCheckedChange={(checked) => handleConfigChange('overwrite', checked)}
          />
        )}

        {operation === 'read' && (
          <>
            <Checkbox
              label="Generate Presigned URL"
              description="Get a temporary signed URL instead of content"
              checked={config.configuration.presigned_url === true}
              onCheckedChange={(checked) => handleConfigChange('presigned_url', checked)}
            />

            {config.configuration.presigned_url && (
              <Input
                label="URL Expiration (seconds)"
                type="number"
                value={config.configuration.url_expiration || 3600}
                onChange={(e) => handleConfigChange('url_expiration', parseInt(e.target.value) || 3600)}
                min={60}
                max={604800}
                description="How long the URL remains valid"
              />
            )}
          </>
        )}
      </div>

      {/* Metadata */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Object Metadata</p>
        <Textarea
          label="Custom Metadata (JSON)"
          value={
            typeof config.configuration.metadata === 'object'
              ? JSON.stringify(config.configuration.metadata, null, 2)
              : config.configuration.metadata || ''
          }
          onChange={(e) => {
            try {
              const parsed = JSON.parse(e.target.value);
              handleConfigChange('metadata', parsed);
            } catch (_error) {
              handleConfigChange('metadata', e.target.value);
            }
          }}
          placeholder='{"created_by": "{{user_id}}", "workflow_id": "{{workflow.id}}"}'
          rows={3}
          description="Custom metadata to attach to the object"
        />
      </div>

      <Input
        label="Output Variable"
        value={config.configuration.output_variable || 'file_result'}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="file_result"
        description="Variable name to store the result"
      />

      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          {operation === 'read' && (
            <>
              <li><code className="text-theme-accent">content</code> - File content (or presigned URL)</li>
              <li><code className="text-theme-accent">size</code> - File size in bytes</li>
              <li><code className="text-theme-accent">content_type</code> - MIME type</li>
            </>
          )}
          {operation === 'list' && (
            <>
              <li><code className="text-theme-accent">files</code> - Array of file objects</li>
              <li><code className="text-theme-accent">count</code> - Number of files found</li>
            </>
          )}
          {(operation === 'write' || operation === 'copy' || operation === 'move') && (
            <>
              <li><code className="text-theme-accent">path</code> - Path to the created/modified file</li>
              <li><code className="text-theme-accent">etag</code> - Object ETag/checksum</li>
            </>
          )}
          {operation === 'exists' && (
            <li><code className="text-theme-accent">exists</code> - Boolean indicating if file exists</li>
          )}
          <li><code className="text-theme-accent">success</code> - Operation success status</li>
        </ul>
      </div>
    </div>
  );
};
