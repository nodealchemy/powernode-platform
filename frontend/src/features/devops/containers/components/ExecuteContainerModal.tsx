import React, { useState, useEffect, useCallback } from 'react';
import { Play, FileCode, Globe, Shield, Cpu, HardDrive } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Input } from '@/shared/components/ui/Input';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Loading } from '@/shared/components/ui/Loading';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { containerExecutionApi } from '@/shared/services/ai';
import type { ContainerTemplateSummary, ContainerTemplate } from '@/shared/services/ai';

interface ExecuteContainerModalProps {
  isOpen: boolean;
  onClose: () => void;
  template: ContainerTemplateSummary | null;
  onExecutionStarted?: () => void;
}

export const ExecuteContainerModal: React.FC<ExecuteContainerModalProps> = ({
  isOpen,
  onClose,
  template,
  onExecutionStarted,
}) => {
  const { addNotification } = useNotifications();
  const [inputParameters, setInputParameters] = useState('{}');
  const [timeoutOverride, setTimeoutOverride] = useState('');
  const [isExecuting, setIsExecuting] = useState(false);
  const [templateDetails, setTemplateDetails] = useState<ContainerTemplate | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [paramError, setParamError] = useState('');

  const resetForm = useCallback(() => {
    setInputParameters('{}');
    setTimeoutOverride('');
    setIsExecuting(false);
    setTemplateDetails(null);
    setIsLoading(false);
    setParamError('');
  }, []);

  useEffect(() => {
    if (!isOpen || !template) {
      resetForm();
      return;
    }

    setIsLoading(true);
    containerExecutionApi
      .getTemplate(template.id)
      .then((response) => {
        const tmpl = response.template;
        setTemplateDetails(tmpl);
        // Pre-populate input parameters from input_schema if available
        if (tmpl.input_schema && Object.keys(tmpl.input_schema).length > 0) {
          const scaffolded: Record<string, string> = {};
          Object.keys(tmpl.input_schema).forEach((key) => {
            scaffolded[key] = '';
          });
          setInputParameters(JSON.stringify(scaffolded, null, 2));
        }
      })
      .catch((err) => {
        addNotification({
          type: 'error',
          title: 'Load Failed',
          message: err instanceof Error ? err.message : 'Failed to load template details',
        });
      })
      .finally(() => setIsLoading(false));
  }, [isOpen, template, resetForm, addNotification]);

  const handleExecute = async () => {
    // Validate JSON
    let parsedParams: Record<string, unknown> = {};
    try {
      parsedParams = JSON.parse(inputParameters);
      setParamError('');
    } catch {
      setParamError('Invalid JSON');
      return;
    }

    if (!template) return;

    setIsExecuting(true);
    try {
      const request: {
        template_id: string;
        input_parameters?: Record<string, unknown>;
        timeout_seconds?: number;
      } = {
        template_id: template.id,
        input_parameters: parsedParams,
      };

      if (timeoutOverride && parseInt(timeoutOverride) > 0) {
        request.timeout_seconds = parseInt(timeoutOverride);
      }

      await containerExecutionApi.executeContainer(request);

      addNotification({
        type: 'success',
        title: 'Execution Started',
        message: `Container "${template.name}" is now running.`,
      });

      onExecutionStarted?.();
      onClose();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to start container execution';
      addNotification({ type: 'error', title: 'Execution Failed', message });
    } finally {
      setIsExecuting(false);
    }
  };

  const footer = (
    <div className="flex items-center justify-end gap-2">
      <Button variant="outline" onClick={onClose} disabled={isExecuting}>
        Cancel
      </Button>
      <Button variant="primary" onClick={handleExecute} disabled={isExecuting || isLoading}>
        {isExecuting ? (
          <>Executing...</>
        ) : (
          <>
            <Play className="w-4 h-4 mr-1" />
            Execute
          </>
        )}
      </Button>
    </div>
  );

  if (!template) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Execute Container"
      subtitle={`Run "${template.name}"`}
      icon={<Play className="w-5 h-5" />}
      footer={footer}
      maxWidth="2xl"
    >
      {isLoading ? (
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : (
        <div className="space-y-6">
          {/* Template Info Header */}
          <div className="bg-theme-bg-secondary rounded-lg p-4 space-y-3">
            <div className="flex items-center gap-3">
              <FileCode className="w-5 h-5 text-theme-brand-primary flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <h3 className="font-medium text-theme-text-primary">{template.name}</h3>
                {template.description && (
                  <p className="text-sm text-theme-text-secondary mt-0.5">{template.description}</p>
                )}
              </div>
            </div>

            <div className="flex items-center gap-2 text-xs text-theme-text-secondary font-mono bg-theme-bg-primary px-2 py-1 rounded">
              {template.image_name}
            </div>

            {templateDetails && (
              <div className="flex flex-wrap items-center gap-3 text-xs text-theme-text-secondary">
                <span className="flex items-center gap-1">
                  <HardDrive className="w-3 h-3" />
                  {templateDetails.memory_mb} MB
                </span>
                <span className="flex items-center gap-1">
                  <Cpu className="w-3 h-3" />
                  {templateDetails.cpu_millicores}m CPU
                </span>
                {templateDetails.network_access && (
                  <Badge variant="outline" size="sm">
                    <Globe className="w-3 h-3 mr-1" />
                    Network
                  </Badge>
                )}
                {templateDetails.sandbox_mode && (
                  <Badge variant="outline" size="sm">
                    <Shield className="w-3 h-3 mr-1" />
                    Sandbox
                  </Badge>
                )}
              </div>
            )}
          </div>

          {/* Input Schema Reference */}
          {templateDetails?.input_schema && Object.keys(templateDetails.input_schema).length > 0 && (
            <div className="space-y-2">
              <h4 className="text-sm font-medium text-theme-text-primary">Expected Parameters</h4>
              <div className="bg-theme-bg-secondary rounded-lg p-3 text-xs font-mono text-theme-text-secondary overflow-auto max-h-32">
                <pre>{JSON.stringify(templateDetails.input_schema, null, 2)}</pre>
              </div>
            </div>
          )}

          {/* Input Parameters */}
          <Textarea
            label="Input Parameters (JSON)"
            placeholder='{}'
            value={inputParameters}
            onChange={(e) => {
              setInputParameters(e.target.value);
              if (paramError) setParamError('');
            }}
            error={paramError}
            rows={8}
            className="font-mono text-sm"
          />

          {/* Timeout Override */}
          <Input
            label="Timeout Override (seconds)"
            type="number"
            placeholder={templateDetails ? String(templateDetails.timeout_seconds) : '3600'}
            value={timeoutOverride}
            onChange={(e) => setTimeoutOverride(e.target.value)}
            description="Leave empty to use template default"
            min={1}
            max={86400}
          />
        </div>
      )}
    </Modal>
  );
};

export default ExecuteContainerModal;
