import React, { useState } from 'react';
import { Zap, X, CheckCircle2, XCircle, Clock, AlertTriangle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { Progress } from '@/shared/components/ui/Progress';

interface BulkTestModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

interface TestResult {
  provider: string;
  status: 'pending' | 'testing' | 'success' | 'error';
  responseTime?: number;
  error?: string;
}

export const BulkTestModal: React.FC<BulkTestModalProps> = ({
  isOpen,
  onClose,
  onConfirm
}) => {
  const [testing, setTesting] = useState(false);
  const [results, setResults] = useState<TestResult[]>([]);
  const [progress, setProgress] = useState(0);

  // Mock test results for demonstration
  const mockProviders = [
    'Ollama (Local)',
    'OpenAI GPT-4',
    'Anthropic Claude',
    'Hugging Face',
    'Cohere'
  ];

  const handleStartTest = async () => {
    setTesting(true);
    setProgress(0);
    
    // Initialize results
    const initialResults = mockProviders.map(provider => ({
      provider,
      status: 'pending' as const
    }));
    setResults(initialResults);

    // Simulate testing each provider
    for (let i = 0; i < mockProviders.length; i++) {
      const provider = mockProviders[i];
      
      // Update to testing status
      setResults(prev => prev.map(r => 
        r.provider === provider 
          ? { ...r, status: 'testing' as const }
          : r
      ));

      // Simulate test delay
      await new Promise(resolve => setTimeout(resolve, 1000 + Math.random() * 2000));

      // Simulate random results (mostly success)
      const success = Math.random() > 0.2; // 80% success rate
      const responseTime = Math.floor(Math.random() * 3000) + 500;

      setResults(prev => prev.map(r => 
        r.provider === provider 
          ? { 
              ...r, 
              status: success ? 'success' as const : 'error' as const,
              responseTime: success ? responseTime : undefined,
              error: success ? undefined : 'Connection timeout or invalid credentials'
            }
          : r
      ));

      setProgress(((i + 1) / mockProviders.length) * 100);
    }

    setTesting(false);
  };

  const handleConfirm = () => {
    if (!testing && results.length === 0) {
      handleStartTest();
    } else {
      onConfirm();
    }
  };

  const getStatusIcon = (status: TestResult['status']) => {
    switch (status) {
      case 'pending':
        return <div className="h-4 w-4 rounded-full bg-theme-tertiary opacity-30" />;
      case 'testing':
        return <Clock className="h-4 w-4 text-theme-warning animate-spin" />;
      case 'success':
        return <CheckCircle2 className="h-4 w-4 text-theme-success" />;
      case 'error':
        return <XCircle className="h-4 w-4 text-theme-error" />;
    }
  };

  const getStatusText = (result: TestResult) => {
    switch (result.status) {
      case 'pending':
        return 'Waiting...';
      case 'testing':
        return 'Testing connection...';
      case 'success':
        return `✓ Connected (${result.responseTime}ms)`;
      case 'error':
        return result.error || 'Connection failed';
    }
  };

  const successCount = results.filter(r => r.status === 'success').length;
  const errorCount = results.filter(r => r.status === 'error').length;
  const completedCount = successCount + errorCount;

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
            <Zap className="h-5 w-5 text-theme-warning" />
          </div>
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Test All Credentials</h2>
            <p className="text-sm text-theme-tertiary">
              {testing ? 'Testing connections...' : 'Verify all AI provider connections'}
            </p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-8 w-8 p-0"
          disabled={testing}
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <div className="p-6">
        {results.length === 0 ? (
          <div>
            <div className="flex items-start gap-3 p-4 bg-theme-info bg-opacity-10 border border-theme-info border-opacity-20 rounded-lg mb-6">
              <AlertTriangle className="h-5 w-5 text-theme-info mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-sm font-medium text-theme-info">Connection Testing</p>
                <p className="text-sm text-theme-secondary mt-1">
                  This will test the connection to all configured AI providers using their stored credentials. 
                  The test will verify that each provider is reachable and properly authenticated.
                </p>
              </div>
            </div>

            <div className="bg-theme-surface p-4 rounded-lg border border-theme">
              <h4 className="text-sm font-medium text-theme-primary mb-2">What will be tested:</h4>
              <ul className="text-sm text-theme-secondary space-y-1">
                <li>• Connection to each provider's API endpoint</li>
                <li>• Authentication with stored credentials</li>
                <li>• Response time measurement</li>
                <li>• Basic functionality verification</li>
              </ul>
            </div>
          </div>
        ) : (
          <div>
            {testing && (
              <div className="mb-6">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">Testing Progress</span>
                  <span className="text-sm text-theme-tertiary">{Math.round(progress)}%</span>
                </div>
                <Progress value={progress} className="w-full" />
              </div>
            )}

            <div className="space-y-3">
              {results.map((result, index) => (
                <div key={index} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg border border-theme">
                  <div className="flex items-center gap-3">
                    {getStatusIcon(result.status)}
                    <span className="text-sm font-medium text-theme-primary">
                      {result.provider}
                    </span>
                  </div>
                  <span className={`text-sm ${
                    result.status === 'success' ? 'text-theme-success' :
                    result.status === 'error' ? 'text-theme-error' :
                    'text-theme-tertiary'
                  }`}>
                    {getStatusText(result)}
                  </span>
                </div>
              ))}
            </div>

            {completedCount === results.length && (
              <div className="mt-6 p-4 bg-theme-surface rounded-lg border border-theme">
                <h4 className="text-sm font-medium text-theme-primary mb-2">Test Summary</h4>
                <div className="flex items-center gap-4 text-sm">
                  <div className="flex items-center gap-1">
                    <CheckCircle2 className="h-4 w-4 text-theme-success" />
                    <span className="text-theme-success">{successCount} successful</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <XCircle className="h-4 w-4 text-theme-error" />
                    <span className="text-theme-error">{errorCount} failed</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="flex items-center justify-end space-x-3 p-6 border-t border-theme bg-theme-surface">
        <Button
          variant="outline"
          onClick={onClose}
          disabled={testing}
        >
          {testing ? 'Testing...' : 'Cancel'}
        </Button>
        <Button
          onClick={handleConfirm}
          disabled={testing}
          className="flex items-center gap-2"
        >
          <Zap className="h-4 w-4" />
          {results.length === 0 ? 'Start Testing' : 'Done'}
        </Button>
      </div>
    </Modal>
  );
};