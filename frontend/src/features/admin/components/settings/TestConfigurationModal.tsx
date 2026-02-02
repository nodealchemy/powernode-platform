import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { servicesApi, ServiceConfig } from '../../services/servicesApi';
import { JobProgressModal } from './JobProgressModal';
import { TestTube } from 'lucide-react';

interface TestConfigurationModalProps {
  isOpen: boolean;
  onClose: () => void;
  config: ServiceConfig;
}

export const TestConfigurationModal: React.FC<TestConfigurationModalProps> = ({
  isOpen,
  onClose,
  config
}) => {
  const { showNotification } = useNotifications();
  const [jobId, setJobId] = useState<string | null>(null);
  const [showProgress, setShowProgress] = useState(false);

  const runConfigurationTest = async () => {
    try {
      const result = await servicesApi.testConfiguration(config);
      setJobId(result.job_id);
      setShowProgress(true);
      showNotification('Configuration test started', 'info');
    } catch {
      showNotification('Failed to start configuration test', 'error');
    }
  };

  const handleJobComplete = (result: unknown) => {
    const testResult = result as { validation?: { valid?: boolean }; connectivity?: Record<string, { status?: string }> };
    if (testResult.validation?.valid && 
        testResult.connectivity && 
        Object.values(testResult.connectivity).every((status: unknown) => (status as { status?: string }).status === 'healthy')) {
      showNotification('Configuration test passed successfully', 'success');
    } else {
      showNotification('Configuration test completed with issues', 'warning');
    }
  };

  const handleJobError = (error: string) => {
    showNotification(`Configuration test failed: ${error}`, 'error');
  };

  const handleCloseProgress = () => {
    setShowProgress(false);
    setJobId(null);
    onClose();
  };

  return (
    <>
      <Modal
        isOpen={isOpen && !showProgress}
        onClose={onClose}
        title="Test Configuration"
        maxWidth="md"
      >
        <div className="space-y-6">
          <div className="text-center">
            <TestTube className="w-12 h-12 text-theme-primary mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">Configuration Testing</h3>
            <p className="text-sm text-theme-secondary mb-6">
              Test your services configuration for validity and service connectivity.
              This process will validate the configuration structure and check if all services are reachable.
            </p>
          </div>
          
          <div className="flex justify-end space-x-3">
            <Button onClick={onClose} variant="secondary">
              Cancel
            </Button>
            <Button onClick={runConfigurationTest} variant="primary">
              <TestTube className="w-4 h-4 mr-2" />
              Start Test
            </Button>
          </div>
        </div>
      </Modal>

      {jobId && (
        <JobProgressModal
          isOpen={showProgress}
          onClose={handleCloseProgress}
          jobId={jobId}
          jobType="services_test_configuration"
          title="Testing Configuration"
          onComplete={handleJobComplete}
          onError={handleJobError}
        />
      )}
    </>
  );
};