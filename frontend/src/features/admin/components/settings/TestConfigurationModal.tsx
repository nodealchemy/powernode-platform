import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { reverseProxyApi, ReverseProxyConfig, ConfigValidationResult, ConnectivityTestResult } from '../../services/reverseProxyApi';
import { 
  CheckCircle, 
  AlertTriangle, 
  XCircle, 
  Clock,
  TestTube,
  Server,
  RefreshCw
} from 'lucide-react';

interface TestConfigurationModalProps {
  isOpen: boolean;
  onClose: () => void;
  config: ReverseProxyConfig;
}

interface TestResults {
  validation: ConfigValidationResult;
  connectivity: ConnectivityTestResult;
  message: string;
}

export const TestConfigurationModal: React.FC<TestConfigurationModalProps> = ({
  isOpen,
  onClose,
  config
}) => {
  const { showNotification } = useNotification();
  const [testing, setTesting] = useState(false);
  const [testResults, setTestResults] = useState<TestResults | null>(null);

  const runConfigurationTest = async () => {
    try {
      setTesting(true);
      setTestResults(null);
      
      const results = await reverseProxyApi.testConfiguration(config);
      setTestResults(results);
      
      if (results.validation.valid && Object.values(results.connectivity).every(service => service.status === 'healthy')) {
        showNotification('Configuration test passed successfully', 'success');
      } else {
        showNotification('Configuration test completed with issues', 'warning');
      }
    } catch (error) {
      console.error('Configuration test failed:', error);
      showNotification('Configuration test failed', 'error');
    } finally {
      setTesting(false);
    }
  };

  const getValidationStatusIcon = (valid: boolean) => {
    return valid ? (
      <CheckCircle className="w-5 h-5 text-theme-success" />
    ) : (
      <XCircle className="w-5 h-5 text-theme-danger" />
    );
  };

  const getConnectivityStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'unhealthy':
        return <AlertTriangle className="w-5 h-5 text-theme-warning" />;
      case 'unreachable':
        return <XCircle className="w-5 h-5 text-theme-danger" />;
      default:
        return <Clock className="w-5 h-5 text-theme-secondary" />;
    }
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'healthy':
        return 'success';
      case 'unhealthy':
        return 'warning';
      case 'unreachable':
        return 'danger';
      default:
        return 'secondary';
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Test Configuration"
      maxWidth="lg"
    >
      <div className="space-y-6">
        {/* Test Button */}
        <FlexBetween>
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Configuration Testing</h3>
            <p className="text-sm text-theme-secondary">
              Test your reverse proxy configuration before applying changes
            </p>
          </div>
          <Button
            onClick={runConfigurationTest}
            disabled={testing}
            variant="primary"
            size="sm"
          >
            {testing ? (
              <>
                <LoadingSpinner size="sm" className="mr-2" />
                Testing...
              </>
            ) : (
              <>
                <TestTube className="w-4 h-4 mr-2" />
                Run Test
              </>
            )}
          </Button>
        </FlexBetween>

        {/* Test Results */}
        {testResults && (
          <div className="space-y-4">
            {/* Configuration Validation */}
            <Card className="p-4">
              <FlexBetween className="mb-4">
                <FlexItemsCenter>
                  {getValidationStatusIcon(testResults.validation.valid)}
                  <h4 className="ml-2 font-medium text-theme-primary">
                    Configuration Validation
                  </h4>
                </FlexItemsCenter>
                <Badge variant={testResults.validation.valid ? 'success' : 'danger'}>
                  {testResults.validation.valid ? 'Valid' : 'Invalid'}
                </Badge>
              </FlexBetween>

              {!testResults.validation.valid && testResults.validation.errors.length > 0 && (
                <div className="bg-theme-danger/10 border border-theme-danger/20 rounded-lg p-3">
                  <p className="text-sm font-medium text-theme-danger mb-2">
                    Configuration Errors:
                  </p>
                  <ul className="text-sm text-theme-danger space-y-1">
                    {testResults.validation.errors.map((error, index) => (
                      <li key={index} className="flex items-start">
                        <span className="w-2 h-2 bg-theme-danger rounded-full mt-2 mr-2 flex-shrink-0" />
                        {error}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {testResults.validation.valid && (
                <div className="bg-theme-success/10 border border-theme-success/20 rounded-lg p-3">
                  <p className="text-sm text-theme-success">
                    ✓ Configuration structure is valid
                  </p>
                </div>
              )}
            </Card>

            {/* Service Connectivity */}
            <Card className="p-4">
              <FlexBetween className="mb-4">
                <FlexItemsCenter>
                  <Server className="w-5 h-5 text-theme-primary" />
                  <h4 className="ml-2 font-medium text-theme-primary">
                    Service Connectivity
                  </h4>
                </FlexItemsCenter>
                <Badge variant="info">
                  {Object.keys(testResults.connectivity).length} Services
                </Badge>
              </FlexBetween>

              <div className="space-y-3">
                {Object.entries(testResults.connectivity).map(([serviceName, serviceResult]) => (
                  <div key={serviceName} className="bg-theme-surface rounded-lg p-3 border border-theme">
                    <FlexBetween className="mb-2">
                      <FlexItemsCenter>
                        {getConnectivityStatusIcon(serviceResult.status)}
                        <span className="ml-2 font-medium text-theme-primary capitalize">
                          {serviceName}
                        </span>
                      </FlexItemsCenter>
                      <Badge variant={getStatusBadgeVariant(serviceResult.status)}>
                        {serviceResult.status}
                      </Badge>
                    </FlexBetween>

                    <div className="text-sm text-theme-secondary space-y-1">
                      {serviceResult.url && (
                        <p>URL: {serviceResult.url}</p>
                      )}
                      {serviceResult.response_code && (
                        <p>Response Code: {serviceResult.response_code}</p>
                      )}
                      {serviceResult.response_time_ms && (
                        <p>Response Time: {serviceResult.response_time_ms}ms</p>
                      )}
                      {serviceResult.error && (
                        <p className="text-theme-danger">Error: {serviceResult.error}</p>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </Card>

            {/* Overall Result */}
            <Card className="p-4">
              <FlexItemsCenter>
                {testResults.validation.valid && 
                 Object.values(testResults.connectivity).every(service => service.status === 'healthy') ? (
                  <>
                    <CheckCircle className="w-6 h-6 text-theme-success" />
                    <div className="ml-3">
                      <p className="font-medium text-theme-success">All Tests Passed</p>
                      <p className="text-sm text-theme-secondary">
                        Configuration is ready to be applied
                      </p>
                    </div>
                  </>
                ) : (
                  <>
                    <AlertTriangle className="w-6 h-6 text-theme-warning" />
                    <div className="ml-3">
                      <p className="font-medium text-theme-warning">Issues Found</p>
                      <p className="text-sm text-theme-secondary">
                        Please review and fix the issues above before applying
                      </p>
                    </div>
                  </>
                )}
              </FlexItemsCenter>
            </Card>
          </div>
        )}

        {testing && (
          <Card className="p-8">
            <FlexItemsCenter justify="center" className="text-theme-secondary">
              <LoadingSpinner size="lg" />
              <div className="ml-4 text-center">
                <p className="font-medium">Running Configuration Test</p>
                <p className="text-sm">Validating configuration and testing service connectivity...</p>
              </div>
            </FlexItemsCenter>
          </Card>
        )}

        {!testResults && !testing && (
          <Card className="p-8 text-center">
            <TestTube className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              Ready to Test
            </h3>
            <p className="text-theme-secondary">
              Click "Run Test" to validate your configuration and check service connectivity
            </p>
          </Card>
        )}
      </div>

      {/* Modal Actions */}
      <div className="flex justify-between items-center pt-4 border-t border-theme">
        <Button
          onClick={runConfigurationTest}
          disabled={testing}
          variant="secondary"
          size="sm"
        >
          <RefreshCw className="w-4 h-4 mr-2" />
          Test Again
        </Button>
        <Button
          onClick={onClose}
          variant="primary"
        >
          Close
        </Button>
      </div>
    </Modal>
  );
};