
import { AlertTriangle, Settings, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';

interface SetupDefaultProvidersModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

export const SetupDefaultProvidersModal: React.FC<SetupDefaultProvidersModalProps> = ({
  isOpen,
  onClose,
  onConfirm
}) => {
  const defaultProviders = [
    {
      name: 'Ollama',
      description: 'Local AI models with no API costs',
      features: ['Local hosting', 'No API keys required', 'Privacy-focused']
    },
    {
      name: 'OpenAI',
      description: 'GPT models for text generation and chat',
      features: ['GPT-4 and GPT-3.5', 'Function calling', 'Vision capabilities']
    },
    {
      name: 'Anthropic',
      description: 'Claude models for advanced reasoning',
      features: ['Claude 3 family', 'Long context windows', 'Safety-focused']
    },
    {
      name: 'Hugging Face',
      description: 'Open-source model marketplace',
      features: ['Thousands of models', 'Community-driven', 'Free tier available']
    },
    {
      name: 'Cohere',
      description: 'Enterprise-grade language models',
      features: ['Multilingual support', 'RAG optimization', 'Custom training']
    }
  ];

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Settings className="h-5 w-5 text-theme-info" />
          </div>
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Setup Default Providers</h2>
            <p className="text-sm text-theme-tertiary">Initialize your AI provider library</p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-8 w-8 p-0"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <div className="p-6">
        <div className="mb-6">
          <div className="flex items-start gap-3 p-4 bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-20 rounded-lg">
            <AlertTriangle className="h-5 w-5 text-theme-warning mt-0.5 flex-shrink-0" />
            <div>
              <p className="text-sm font-medium text-theme-warning">Important Note</p>
              <p className="text-sm text-theme-secondary mt-1">
                This will create default AI provider configurations. You'll still need to add your own API credentials 
                for each provider you want to use. Ollama providers may work without API keys depending on your server configuration.
              </p>
            </div>
          </div>
        </div>

        <div className="mb-6">
          <h3 className="text-sm font-medium text-theme-primary mb-3">
            The following providers will be added:
          </h3>
          <div className="space-y-3">
            {defaultProviders.map((provider, index) => (
              <div key={index} className="flex items-start gap-3 p-3 bg-theme-surface rounded-lg border border-theme">
                <div className="h-8 w-8 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center flex-shrink-0">
                  <span className="text-xs font-semibold text-theme-info">
                    {provider.name.charAt(0)}
                  </span>
                </div>
                <div className="flex-1 min-w-0">
                  <h4 className="text-sm font-medium text-theme-primary">{provider.name}</h4>
                  <p className="text-xs text-theme-tertiary mb-2">{provider.description}</p>
                  <div className="flex flex-wrap gap-1">
                    {provider.features.map((feature, featureIndex) => (
                      <span
                        key={featureIndex}
                        className="inline-flex items-center px-2 py-1 rounded-md text-xs bg-theme-info bg-opacity-10 text-theme-info"
                      >
                        {feature}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-theme-surface p-4 rounded-lg border border-theme">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Next Steps</h4>
          <ul className="text-sm text-theme-secondary space-y-1">
            <li>• Providers will be created with default configurations</li>
            <li>• Add your API credentials to activate each provider</li>
            <li>• Test connections to ensure everything works</li>
            <li>• Create AI agents using your preferred providers</li>
          </ul>
        </div>
      </div>

      <div className="flex items-center justify-end space-x-3 p-6 border-t border-theme bg-theme-surface">
        <Button
          variant="outline"
          onClick={onClose}
        >
          Cancel
        </Button>
        <Button
          onClick={onConfirm}
          className="flex items-center gap-2"
        >
          <Settings className="h-4 w-4" />
          Setup Default Providers
        </Button>
      </div>
    </Modal>
  );
};