import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { servicesApi, GeneratedConfig } from '../../services/servicesApi';
import { JobProgressModal } from './JobProgressModal';
import { 
  Download, 
  Copy,
  FileText,
  Server,
  Settings,
  Eye,
  EyeOff
} from 'lucide-react';

interface ExportConfigurationModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type ProxyType = 'nginx' | 'apache' | 'traefik';

const proxyTypes = [
  { value: 'nginx' as ProxyType, label: 'Nginx', description: 'Popular high-performance web server and load balancer' },
  { value: 'apache' as ProxyType, label: 'Apache HTTP Server', description: 'Widely used open-source web server' },
  { value: 'traefik' as ProxyType, label: 'Traefik', description: 'Modern load balancer and gateway for microservices' }
];

export const ExportConfigurationModal: React.FC<ExportConfigurationModalProps> = ({
  isOpen,
  onClose
}) => {
  const { showNotification } = useNotifications();
  const [selectedType, setSelectedType] = useState<ProxyType>('nginx');
  const [generatedConfig, setGeneratedConfig] = useState<GeneratedConfig | null>(null);
  const [generating, setGenerating] = useState(false);
  const [showConfig, setShowConfig] = useState(false);
  const [jobId, setJobId] = useState<string | null>(null);
  const [showJobProgress, setShowJobProgress] = useState(false);

  const generateConfig = async () => {
    try {
      setGenerating(true);
      const result = await servicesApi.generateConfig(selectedType);
      
      // Start job progress tracking
      setJobId(result.job_id);
      setShowJobProgress(true);
      showNotification('Configuration generation started', 'info');
      setGenerating(false);
    } catch (_error) {
      showNotification('Failed to start configuration generation', 'error');
      setGenerating(false);
    }
  };

  const handleJobComplete = (result: unknown) => {
    const generatedConfig = result as GeneratedConfig;
    setGeneratedConfig(generatedConfig);
    setShowJobProgress(false);
    showNotification('Configuration generated successfully', 'success');
  };

  const handleJobError = (error: string) => {
    setShowJobProgress(false);
    showNotification(error || 'Configuration generation failed', 'error');
  };

  const copyToClipboard = async () => {
    if (!generatedConfig?.config) return;

    try {
      await navigator.clipboard.writeText(generatedConfig.config);
      showNotification('Configuration copied to clipboard', 'success');
    } catch (_error) {
      showNotification('Failed to copy to clipboard', 'error');
    }
  };

  const downloadConfig = () => {
    if (!generatedConfig) return;

    const blob = new Blob([generatedConfig.config], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = generatedConfig.filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    showNotification('Configuration downloaded', 'success');
  };

  const handleClose = () => {
    setGeneratedConfig(null);
    setShowConfig(false);
    setJobId(null);
    setShowJobProgress(false);
    onClose();
  };

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={handleClose}
        title="Export Services Configuration"
        maxWidth="xl"
      >
        <div className="space-y-6">
          {/* Proxy Type Selection */}
          {!generatedConfig && (
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">
                Select Proxy Server Type
              </h3>
              <div className="grid grid-cols-1 gap-3">
                {proxyTypes.map((type) => (
                  <Card 
                    key={type.value}
                    className={`p-4 cursor-pointer border-2 transition-all ${
                      selectedType === type.value 
                        ? 'border-theme-primary bg-theme-primary/5' 
                        : 'border-theme hover:border-theme-primary/50'
                    }`}
                    onClick={() => setSelectedType(type.value)}
                  >
                    <FlexBetween>
                      <FlexItemsCenter>
                        <Server className="w-5 h-5 text-theme-primary mr-3" />
                        <div>
                          <h4 className="font-medium text-theme-primary">{type.label}</h4>
                          <p className="text-sm text-theme-secondary">{type.description}</p>
                        </div>
                      </FlexItemsCenter>
                      {selectedType === type.value && (
                        <Badge variant="primary">Selected</Badge>
                      )}
                    </FlexBetween>
                  </Card>
                ))}
              </div>

              <div className="mt-6">
                <Button
                  onClick={generateConfig}
                  disabled={generating}
                  variant="primary"
                  size="lg"
                  className="w-full"
                >
                  {generating ? (
                    <>
                      <LoadingSpinner size="sm" className="mr-2" />
                      Generating Configuration...
                    </>
                  ) : (
                    <>
                      <Settings className="w-5 h-5 mr-2" />
                      Generate {proxyTypes.find(t => t.value === selectedType)?.label} Configuration
                    </>
                  )}
                </Button>
              </div>
            </div>
          )}

          {/* Generated Configuration */}
          {generatedConfig && (
            <div className="space-y-4">
              {/* Config Header */}
              <FlexBetween>
                <div>
                  <h3 className="text-lg font-medium text-theme-primary">
                    {generatedConfig.proxy_type.charAt(0).toUpperCase() + generatedConfig.proxy_type.slice(1)} Configuration
                  </h3>
                  <p className="text-sm text-theme-secondary">
                    Generated configuration file: {generatedConfig.filename}
                  </p>
                </div>
                <div className="flex space-x-2">
                  <Button
                    onClick={() => setShowConfig(!showConfig)}
                    variant="secondary"
                    size="sm"
                  >
                    {showConfig ? (
                      <>
                        <EyeOff className="w-4 h-4 mr-2" />
                        Hide Config
                      </>
                    ) : (
                      <>
                        <Eye className="w-4 h-4 mr-2" />
                        Show Config
                      </>
                    )}
                  </Button>
                  <Button
                    onClick={copyToClipboard}
                    variant="secondary"
                    size="sm"
                  >
                    <Copy className="w-4 h-4 mr-2" />
                    Copy
                  </Button>
                  <Button
                    onClick={downloadConfig}
                    variant="primary"
                    size="sm"
                  >
                    <Download className="w-4 h-4 mr-2" />
                    Download
                  </Button>
                </div>
              </FlexBetween>

              {/* Configuration Preview */}
              {showConfig && (
                <Card className="p-0 overflow-hidden">
                  <div className="bg-theme-surface border-b border-theme p-3">
                    <FlexItemsCenter>
                      <FileText className="w-4 h-4 text-theme-primary mr-2" />
                      <span className="text-sm font-medium text-theme-primary">
                        {generatedConfig.filename}
                      </span>
                    </FlexItemsCenter>
                  </div>
                  <div className="p-4 bg-theme-background">
                    <pre className="text-sm text-theme-primary font-mono overflow-x-auto whitespace-pre-wrap bg-theme-surface border border-theme rounded-lg p-4 max-h-96">
                      {generatedConfig.config}
                    </pre>
                  </div>
                </Card>
              )}

              {/* Installation Instructions */}
              {generatedConfig.instructions && (
                <Card className="p-4">
                  <h4 className="font-medium text-theme-primary mb-3">Installation Instructions</h4>
                  <div className="text-sm text-theme-secondary space-y-2">
                    {generatedConfig.instructions.split('\n').map((line, index) => (
                      <div key={index} className="flex items-start">
                        <span className="w-6 h-6 bg-theme-primary text-white text-xs rounded-full flex items-center justify-center mr-2 mt-0.5 flex-shrink-0">
                          {index + 1}
                        </span>
                        <code className="bg-theme-surface px-2 py-1 rounded text-theme-primary font-mono text-xs">
                          {line}
                        </code>
                      </div>
                    ))}
                  </div>
                </Card>
              )}

              {/* Actions */}
              <div className="flex justify-between items-center pt-2">
                <Button
                  onClick={() => {
                    setGeneratedConfig(null);
                    setShowConfig(false);
                  }}
                  variant="secondary"
                >
                  Generate Another
                </Button>
                <div className="flex space-x-3">
                  <Button
                    onClick={copyToClipboard}
                    variant="secondary"
                  >
                    <Copy className="w-4 h-4 mr-2" />
                    Copy Configuration
                  </Button>
                  <Button
                    onClick={downloadConfig}
                    variant="primary"
                  >
                    <Download className="w-4 h-4 mr-2" />
                    Download File
                  </Button>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex justify-end pt-4 border-t border-theme">
          <Button
            onClick={handleClose}
            variant="secondary"
          >
            Close
          </Button>
        </div>
      </Modal>

      {/* Job Progress Modal */}
      {jobId && (
        <JobProgressModal
          isOpen={showJobProgress}
          onClose={() => setShowJobProgress(false)}
          jobId={jobId}
          jobType="services_generate_config"
          title={`Generating ${proxyTypes.find(t => t.value === selectedType)?.label} Configuration`}
          onComplete={handleJobComplete}
          onError={handleJobError}
        />
      )}
    </>
  );
};