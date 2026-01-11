import React from 'react';
import { Bot, Star, ExternalLink } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { AiProvider } from '@/shared/types/ai';

/**
 * AI Configuration Settings for CI/CD Pipelines
 *
 * This component displays AI providers that can be used with CI/CD pipelines.
 * Provider management (create, edit, delete) is now done through the main
 * AI Providers page (/app/ai-providers).
 */

interface AiConfigSettingsProps {
  configs: AiProvider[];
  loading: boolean;
  defaultId: string | null;
  onSetDefault: (id: string) => void;
  // Deprecated props - kept for backwards compatibility
  onAdd?: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
}

const getProviderDisplayName = (provider: AiProvider): string => {
  // Extract a user-friendly name from the provider
  const slug = provider.slug || '';
  if (slug.includes('anthropic') || slug.includes('claude')) return 'Anthropic (Claude)';
  if (slug.includes('openai') || slug.includes('gpt')) return 'OpenAI';
  if (slug.includes('bedrock')) return 'AWS Bedrock';
  if (slug.includes('vertex')) return 'Google Vertex AI';
  if (slug.includes('ollama')) return 'Ollama (Local)';
  return provider.name || 'Unknown Provider';
};

const getDefaultModel = (provider: AiProvider): string => {
  if (provider.supported_models && provider.supported_models.length > 0) {
    return provider.supported_models[0].name || provider.supported_models[0].id;
  }
  return 'N/A';
};

const ProviderCard: React.FC<{
  provider: AiProvider;
  isDefault: boolean;
  onSetDefault: () => void;
}> = ({ provider, isDefault, onSetDefault }) => (
  <div className="bg-theme-surface rounded-lg border border-theme p-4">
    <div className="flex items-start justify-between">
      <div className="flex items-center gap-3">
        <div className="p-2 bg-theme-primary/10 rounded-lg">
          <Bot className="w-5 h-5 text-theme-primary" />
        </div>
        <div>
          <div className="flex items-center gap-2">
            <h3 className="font-medium text-theme-primary">{provider.name}</h3>
            {isDefault && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-theme-warning/10 text-theme-warning">
                <Star className="w-3 h-3" />
                CI/CD Default
              </span>
            )}
          </div>
          <p className="text-sm text-theme-tertiary">{getProviderDisplayName(provider)}</p>
        </div>
      </div>
      <span
        className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
          provider.is_active
            ? 'bg-theme-success/10 text-theme-success'
            : 'bg-theme-secondary/10 text-theme-secondary'
        }`}
      >
        {provider.is_active ? 'Active' : 'Inactive'}
      </span>
    </div>

    <div className="mt-4 flex items-center gap-4 text-xs text-theme-tertiary">
      <span>Default Model: {getDefaultModel(provider)}</span>
      <span>Models: {provider.model_count}</span>
      <span>Credentials: {provider.credential_count}</span>
    </div>

    <div className="mt-4 pt-4 border-t border-theme flex items-center justify-between">
      <div className="flex items-center gap-2">
        {!isDefault && provider.is_active && provider.credential_count > 0 && (
          <Button onClick={onSetDefault} variant="secondary" size="sm">
            <Star className="w-4 h-4 mr-1" />
            Set as CI/CD Default
          </Button>
        )}
        {provider.credential_count === 0 && (
          <span className="text-xs text-theme-warning">No credentials configured</span>
        )}
      </div>

      <Link
        to={`/app/ai-providers?highlight=${provider.id}`}
        className="inline-flex items-center gap-1 text-xs text-theme-primary hover:underline"
      >
        Manage Provider
        <ExternalLink className="w-3 h-3" />
      </Link>
    </div>
  </div>
);

export const AiConfigSettings: React.FC<AiConfigSettingsProps> = ({
  configs,
  loading,
  defaultId,
  onSetDefault,
}) => {
  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Info banner about provider management */}
      <div className="bg-theme-info/10 border border-theme-info/20 rounded-lg p-4">
        <div className="flex items-start gap-3">
          <Bot className="w-5 h-5 text-theme-info mt-0.5" />
          <div>
            <h4 className="font-medium text-theme-primary">AI Provider Management</h4>
            <p className="text-sm text-theme-secondary mt-1">
              AI providers are now managed centrally. To add, edit, or remove providers,
              visit the{' '}
              <Link to="/app/ai-providers" className="text-theme-primary hover:underline">
                AI Providers page
              </Link>
              . Here you can select which provider to use as the default for CI/CD pipelines.
            </p>
          </div>
        </div>
      </div>

      {configs.length === 0 ? (
        <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
          <Bot className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No AI Providers Available
          </h3>
          <p className="text-theme-secondary mb-4">
            Configure AI providers to power your CI/CD pipelines with Claude.
          </p>
          <Link to="/app/ai-providers">
            <Button variant="primary">
              <ExternalLink className="w-4 h-4 mr-1" />
              Go to AI Providers
            </Button>
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {configs.map((provider) => (
            <ProviderCard
              key={provider.id}
              provider={provider}
              isDefault={provider.id === defaultId}
              onSetDefault={() => onSetDefault(provider.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default AiConfigSettings;
