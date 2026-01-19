import React, { useState, useCallback, useRef } from 'react';
import { Upload, FileText, AlertCircle, CheckCircle, ArrowLeft, Download } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { workflowsApi } from '@/shared/services/ai';

interface WorkflowImportData {
  workflow: {
    name: string;
    description: string;
    status: string;
    visibility: string;
    tags?: string[];
    execution_mode?: string;
    configuration?: Record<string, unknown>;
  };
  nodes: Array<{
    node_id: string;
    node_type: string;
    name: string;
    position_x: number;
    position_y: number;
    configuration?: Record<string, unknown>;
  }>;
  edges: Array<{
    edge_id: string;
    source_node_id: string;
    target_node_id: string;
    edge_type?: string;
  }>;
  metadata?: {
    exported_at: string;
    exported_by: string;
    platform_version: string;
  };
}

// Type for raw import data that needs validation
interface RawImportData {
  workflow?: {
    name?: string;
    [key: string]: unknown;
  };
  nodes?: Array<{
    node_id?: string;
    node_type?: string;
    name?: string;
    [key: string]: unknown;
  }>;
  edges?: Array<{
    source_node_id?: string;
    target_node_id?: string;
    [key: string]: unknown;
  }>;
  export_data?: RawImportData;
  [key: string]: unknown;
}

interface ValidationError {
  field: string;
  message: string;
}

export const WorkflowImportPage: React.FC = () => {
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [dragActive, setDragActive] = useState(false);
  const [importData, setImportData] = useState<WorkflowImportData | null>(null);
  const [fileName, setFileName] = useState<string>('');
  const [validationErrors, setValidationErrors] = useState<ValidationError[]>([]);
  const [importing, setImporting] = useState(false);
  const [workflowName, setWorkflowName] = useState('');

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const canImportWorkflows = hasPermission('ai.workflows.create');

  const validateImportData = useCallback((data: RawImportData): ValidationError[] => {
    const errors: ValidationError[] = [];

    // Check if data has the expected structure
    if (!data.workflow) {
      errors.push({ field: 'workflow', message: 'Missing workflow data' });
    } else {
      if (!data.workflow.name) {
        errors.push({ field: 'workflow.name', message: 'Workflow name is required' });
      }
    }

    if (!data.nodes || !Array.isArray(data.nodes)) {
      errors.push({ field: 'nodes', message: 'Nodes array is required' });
    } else if (data.nodes.length === 0) {
      errors.push({ field: 'nodes', message: 'Workflow must have at least one node' });
    }

    if (!data.edges || !Array.isArray(data.edges)) {
      errors.push({ field: 'edges', message: 'Edges array is required' });
    }

    // Validate node structure
    if (data.nodes && Array.isArray(data.nodes)) {
      data.nodes.forEach((node, index: number) => {
        if (!node.node_id) {
          errors.push({ field: `nodes[${index}].node_id`, message: 'Node ID is required' });
        }
        if (!node.node_type) {
          errors.push({ field: `nodes[${index}].node_type`, message: 'Node type is required' });
        }
        if (!node.name) {
          errors.push({ field: `nodes[${index}].name`, message: 'Node name is required' });
        }
      });
    }

    // Validate edge structure
    if (data.edges && Array.isArray(data.edges)) {
      data.edges.forEach((edge, index: number) => {
        if (!edge.source_node_id) {
          errors.push({ field: `edges[${index}].source_node_id`, message: 'Source node ID is required' });
        }
        if (!edge.target_node_id) {
          errors.push({ field: `edges[${index}].target_node_id`, message: 'Target node ID is required' });
        }
      });
    }

    return errors;
  }, []);

  const handleFileSelect = useCallback((file: File) => {
    if (!file) return;

    setFileName(file.name);
    setValidationErrors([]);
    setImportData(null);

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const content = e.target?.result as string;
        let parsedData: RawImportData;

        // Try JSON first
        if (file.name.endsWith('.json')) {
          parsedData = JSON.parse(content) as RawImportData;
        }
        // Try YAML if json-like doesn't work
        else if (file.name.endsWith('.yaml') || file.name.endsWith('.yml')) {
          // For now, we'll just try JSON parsing
          // In production, you'd want to add a YAML parser library
          try {
            parsedData = JSON.parse(content) as RawImportData;
          } catch {
            setValidationErrors([{ field: 'file', message: 'YAML support requires additional library. Please convert to JSON.' }]);
            return;
          }
        } else {
          // Try JSON anyway
          parsedData = JSON.parse(content) as RawImportData;
        }

        // Handle both direct export format and wrapped format
        const dataToValidate = parsedData.export_data || parsedData;

        const errors = validateImportData(dataToValidate);
        setValidationErrors(errors);

        if (errors.length === 0) {
          // After validation passes, we can safely cast to WorkflowImportData
          setImportData(dataToValidate as unknown as WorkflowImportData);
          setWorkflowName(dataToValidate.workflow?.name || '');
          addNotification({
            type: 'success',
            title: 'File Loaded',
            message: 'Workflow file validated successfully'
          });
        } else {
          addNotification({
            type: 'error',
            title: 'Validation Failed',
            message: `Found ${errors.length} validation error(s)`
          });
        }
      } catch (error) {
        setValidationErrors([{
          field: 'file',
          message: error instanceof Error ? error.message : 'Invalid file format'
        }]);
        addNotification({
          type: 'error',
          title: 'Parse Error',
          message: 'Failed to parse workflow file. Please ensure it is valid JSON.'
        });
      }
    };

    reader.onerror = () => {
      setValidationErrors([{ field: 'file', message: 'Failed to read file' }]);
      addNotification({
        type: 'error',
        title: 'Read Error',
        message: 'Failed to read the file'
      });
    };

    reader.readAsText(file);
  }, [validateImportData, addNotification]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);

    const file = e.dataTransfer.files[0];
    if (file) {
      handleFileSelect(file);
    }
  }, [handleFileSelect]);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
  }, []);

  const handleFileInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      handleFileSelect(file);
    }
  }, [handleFileSelect]);

  const handleImport = useCallback(async () => {
    if (!importData || !canImportWorkflows) return;

    setImporting(true);
    try {
      const result = await workflowsApi.importWorkflow(
        importData,
        workflowName !== importData.workflow.name ? workflowName : undefined
      );

      addNotification({
        type: 'success',
        title: 'Import Successful',
        message: `Workflow "${result.name}" imported successfully`
      });

      // Navigate to the new workflow
      navigate(`/app/ai/workflows/${result.id}`);
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Import Failed',
        message: error instanceof Error ? error.message : 'Failed to import workflow'
      });
    } finally {
      setImporting(false);
    }
  }, [importData, workflowName, canImportWorkflows, addNotification, navigate]);

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '<�' },
    { label: 'AI Orchestration', href: '/app/ai', icon: '>' },
    { label: 'Workflows', href: '/app/ai', icon: '�' },
    { label: 'Import', icon: '=�' }
  ];

  const getPageActions = () => [
    {
      id: 'back',
      label: 'Back to Workflows',
      onClick: () => navigate('/app/ai'),
      variant: 'secondary' as const,
      icon: ArrowLeft
    }
  ];

  if (!canImportWorkflows) {
    return (
      <PageContainer
        title="Import Workflow"
        description="Import workflows from JSON files"
        breadcrumbs={getBreadcrumbs()}
      >
        <Card className="p-8 text-center">
          <AlertCircle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">
            Permission Required
          </h3>
          <p className="text-theme-secondary">
            You don't have permission to import workflows
          </p>
        </Card>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Import Workflow"
      description="Import workflows from JSON or YAML files"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Upload Section */}
        <div className="space-y-6">
          {/* File Upload Zone */}
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">
              1. Upload Workflow File
            </h3>

            <div
              className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors ${
                dragActive
                  ? 'border-theme-interactive-primary bg-theme-interactive-primary bg-opacity-5'
                  : 'border-theme hover:border-theme-interactive-primary'
              }`}
              onDrop={handleDrop}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
            >
              <Upload className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
              <p className="text-theme-primary font-medium mb-2">
                Drag and drop your workflow file here
              </p>
              <p className="text-sm text-theme-secondary mb-4">
                or click to browse
              </p>
              <Button
                variant="outline"
                onClick={() => fileInputRef.current?.click()}
              >
                <FileText className="h-4 w-4 mr-2" />
                Choose File
              </Button>
              <input
                ref={fileInputRef}
                type="file"
                accept=".json,.yaml,.yml"
                onChange={handleFileInputChange}
                className="hidden"
              />
              <p className="text-xs text-theme-tertiary mt-4">
                Supported formats: JSON, YAML
              </p>
            </div>

            {fileName && (
              <div className="mt-4 p-3 bg-theme-surface rounded-lg">
                <div className="flex items-center gap-2">
                  <FileText className="h-4 w-4 text-theme-interactive-primary" />
                  <span className="text-sm text-theme-primary font-medium">{fileName}</span>
                </div>
              </div>
            )}
          </Card>

          {/* Validation Results */}
          {(validationErrors.length > 0 || importData) && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">
                2. Validation Results
              </h3>

              {validationErrors.length > 0 ? (
                <div className="space-y-2">
                  {validationErrors.map((error, index) => (
                    <div
                      key={index}
                      className="flex items-start gap-2 p-3 bg-theme-error bg-opacity-10 border border-theme-error rounded-lg"
                    >
                      <AlertCircle className="h-4 w-4 text-theme-error mt-0.5 flex-shrink-0" />
                      <div>
                        <p className="text-sm font-medium text-theme-error">{error.field}</p>
                        <p className="text-sm text-theme-secondary">{error.message}</p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="flex items-start gap-2 p-3 bg-theme-success bg-opacity-10 border border-theme-success rounded-lg">
                  <CheckCircle className="h-4 w-4 text-theme-success mt-0.5" />
                  <div>
                    <p className="text-sm font-medium text-theme-success">Validation Passed</p>
                    <p className="text-sm text-theme-secondary">
                      Workflow structure is valid and ready to import
                    </p>
                  </div>
                </div>
              )}
            </Card>
          )}

          {/* Import Options */}
          {importData && validationErrors.length === 0 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">
                3. Import Options
              </h3>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Workflow Name
                  </label>
                  <Input
                    value={workflowName}
                    onChange={(e) => setWorkflowName(e.target.value)}
                    placeholder="Enter workflow name"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">
                    Leave empty to use the original name
                  </p>
                </div>

                <Button
                  onClick={handleImport}
                  disabled={importing}
                  className="w-full"
                >
                  {importing ? 'Importing...' : 'Import Workflow'}
                </Button>
              </div>
            </Card>
          )}
        </div>

        {/* Preview Section */}
        <div>
          {importData && (
            <Card className="p-6 sticky top-4">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">
                Preview
              </h3>

              <div className="space-y-6">
                {/* Workflow Info */}
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-2">Workflow Details</h4>
                  <div className="space-y-2 text-sm">
                    <div className="flex justify-between">
                      <span className="text-theme-tertiary">Name:</span>
                      <span className="text-theme-primary font-medium">{importData.workflow.name}</span>
                    </div>
                    {importData.workflow.description && (
                      <div className="flex justify-between">
                        <span className="text-theme-tertiary">Description:</span>
                        <span className="text-theme-secondary">{importData.workflow.description}</span>
                      </div>
                    )}
                    <div className="flex justify-between">
                      <span className="text-theme-tertiary">Status:</span>
                      <span className="text-theme-secondary">{importData.workflow.status}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-tertiary">Visibility:</span>
                      <span className="text-theme-secondary">{importData.workflow.visibility}</span>
                    </div>
                    {importData.workflow.execution_mode && (
                      <div className="flex justify-between">
                        <span className="text-theme-tertiary">Execution Mode:</span>
                        <span className="text-theme-secondary">{importData.workflow.execution_mode}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Structure Info */}
                <div className="pt-4 border-t border-theme">
                  <h4 className="text-sm font-medium text-theme-primary mb-2">Workflow Structure</h4>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="p-3 bg-theme-surface rounded-lg">
                      <p className="text-2xl font-semibold text-theme-primary">{importData.nodes.length}</p>
                      <p className="text-xs text-theme-tertiary">Nodes</p>
                    </div>
                    <div className="p-3 bg-theme-surface rounded-lg">
                      <p className="text-2xl font-semibold text-theme-primary">{importData.edges.length}</p>
                      <p className="text-xs text-theme-tertiary">Connections</p>
                    </div>
                  </div>
                </div>

                {/* Node Types Summary */}
                <div className="pt-4 border-t border-theme">
                  <h4 className="text-sm font-medium text-theme-primary mb-2">Node Types</h4>
                  <div className="space-y-1">
                    {Object.entries(
                      importData.nodes.reduce((acc, node) => {
                        acc[node.node_type] = (acc[node.node_type] || 0) + 1;
                        return acc;
                      }, {} as Record<string, number>)
                    ).map(([type, count]) => (
                      <div key={type} className="flex justify-between text-sm">
                        <span className="text-theme-secondary">{type}:</span>
                        <span className="text-theme-primary font-medium">{count}</span>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Export Metadata */}
                {importData.metadata && (
                  <div className="pt-4 border-t border-theme">
                    <h4 className="text-sm font-medium text-theme-primary mb-2">Export Metadata</h4>
                    <div className="space-y-1 text-xs text-theme-tertiary">
                      <p>Exported: {new Date(importData.metadata.exported_at).toLocaleString()}</p>
                      <p>Exported by: {importData.metadata.exported_by}</p>
                      <p>Platform version: {importData.metadata.platform_version}</p>
                    </div>
                  </div>
                )}
              </div>
            </Card>
          )}

          {!importData && (
            <Card className="p-8 text-center">
              <Download className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">
                No File Selected
              </h3>
              <p className="text-sm text-theme-secondary">
                Upload a workflow file to see the preview
              </p>
            </Card>
          )}
        </div>
      </div>
    </PageContainer>
  );
};
