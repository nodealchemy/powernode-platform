import { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { TemplateSelectionStep } from './TemplateSelectionStep';
import { CredentialStep } from './CredentialStep';
import { ConfigurationStep } from './ConfigurationStep';
import { TestConnectionStep } from './TestConnectionStep';
import type {
  IntegrationTemplate,
  IntegrationCredential,
  InstanceFormData,
} from '../../types';
import { integrationsApi } from '../../services/integrationsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

type WizardStep = 'template' | 'credential' | 'configuration' | 'test';

interface WizardState {
  template: IntegrationTemplate | null;
  credential: IntegrationCredential | null;
  name: string;
  configuration: Record<string, unknown>;
}

const STEPS: { key: WizardStep; label: string }[] = [
  { key: 'template', label: 'Select Template' },
  { key: 'credential', label: 'Credentials' },
  { key: 'configuration', label: 'Configure' },
  { key: 'test', label: 'Test & Create' },
];

export function IntegrationWizard() {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [currentStep, setCurrentStep] = useState<WizardStep>('template');
  const [isCreating, setIsCreating] = useState(false);
  const [wizardState, setWizardState] = useState<WizardState>({
    template: null,
    credential: null,
    name: '',
    configuration: {},
  });

  const currentStepIndex = STEPS.findIndex((s) => s.key === currentStep);

  const handleTemplateSelect = useCallback((template: IntegrationTemplate) => {
    setWizardState((prev) => ({
      ...prev,
      template,
      name: template.name,
      configuration: template.default_configuration || {},
    }));
    setCurrentStep('credential');
  }, []);

  const handleCredentialSelect = useCallback(
    (credential: IntegrationCredential | null) => {
      setWizardState((prev) => ({
        ...prev,
        credential,
      }));
      setCurrentStep('configuration');
    },
    []
  );

  const handleConfigurationSave = useCallback(
    (name: string, configuration: Record<string, unknown>) => {
      setWizardState((prev) => ({
        ...prev,
        name,
        configuration,
      }));
      setCurrentStep('test');
    },
    []
  );

  const handleBack = useCallback(() => {
    const stepOrder: WizardStep[] = ['template', 'credential', 'configuration', 'test'];
    const currentIndex = stepOrder.indexOf(currentStep);
    if (currentIndex > 0) {
      setCurrentStep(stepOrder[currentIndex - 1]);
    }
  }, [currentStep]);

  const handleCreate = useCallback(async () => {
    if (!wizardState.template) return;

    setIsCreating(true);
    try {
      const formData: InstanceFormData = {
        name: wizardState.name,
        template_id: wizardState.template.id,
        credential_id: wizardState.credential?.id,
        configuration: wizardState.configuration,
      };

      const response = await integrationsApi.createInstance(formData);

      if (response.success && response.data) {
        showNotification('Integration created successfully', 'success');
        navigate(`/app/integrations/${response.data.instance.id}`);
      } else {
        showNotification(response.error || 'Failed to create integration', 'error');
      }
    } catch {
      showNotification('An unexpected error occurred', 'error');
    } finally {
      setIsCreating(false);
    }
  }, [wizardState, navigate, showNotification]);

  const handleCancel = useCallback(() => {
    navigate('/app/integrations/marketplace');
  }, [navigate]);

  return (
    <div className="max-w-4xl mx-auto">
      {/* Progress Steps */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          {STEPS.map((step, index) => (
            <div
              key={step.key}
              className={`flex items-center ${index < STEPS.length - 1 ? 'flex-1' : ''}`}
            >
              <div className="flex items-center">
                <div
                  className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                    index < currentStepIndex
                      ? 'bg-theme-success text-white'
                      : index === currentStepIndex
                        ? 'bg-theme-primary text-white'
                        : 'bg-theme-surface text-theme-tertiary'
                  }`}
                >
                  {index < currentStepIndex ? '✓' : index + 1}
                </div>
                <span
                  className={`ml-2 text-sm ${
                    index <= currentStepIndex
                      ? 'text-theme-primary font-medium'
                      : 'text-theme-tertiary'
                  }`}
                >
                  {step.label}
                </span>
              </div>
              {index < STEPS.length - 1 && (
                <div
                  className={`flex-1 h-0.5 mx-4 ${
                    index < currentStepIndex ? 'bg-theme-success' : 'bg-theme-border'
                  }`}
                />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Step Content */}
      <div className="bg-theme-surface border border-theme rounded-lg p-6">
        {currentStep === 'template' && (
          <TemplateSelectionStep
            onSelect={handleTemplateSelect}
            onCancel={handleCancel}
          />
        )}

        {currentStep === 'credential' && wizardState.template && (
          <CredentialStep
            template={wizardState.template}
            selectedCredential={wizardState.credential}
            onSelect={handleCredentialSelect}
            onBack={handleBack}
          />
        )}

        {currentStep === 'configuration' && wizardState.template && (
          <ConfigurationStep
            template={wizardState.template}
            initialName={wizardState.name}
            initialConfiguration={wizardState.configuration}
            onSave={handleConfigurationSave}
            onBack={handleBack}
          />
        )}

        {currentStep === 'test' && wizardState.template && (
          <TestConnectionStep
            template={wizardState.template}
            credential={wizardState.credential}
            name={wizardState.name}
            configuration={wizardState.configuration}
            onCreate={handleCreate}
            onBack={handleBack}
            isCreating={isCreating}
          />
        )}
      </div>
    </div>
  );
}
