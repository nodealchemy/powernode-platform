import { Link } from 'react-router-dom';
import type { IntegrationInstanceSummary, IntegrationTemplateSummary } from '../types';
import { IntegrationStatusBadge } from './IntegrationStatusBadge';
import { integrationsApi } from '../services/integrationsApi';

interface IntegrationCardProps {
  instance?: IntegrationInstanceSummary;
  template?: IntegrationTemplateSummary;
  onActivate?: (id: string) => void;
  onDeactivate?: (id: string) => void;
  onDelete?: (id: string) => void;
  showActions?: boolean;
}

export function IntegrationCard({
  instance,
  template,
  onActivate,
  onDeactivate,
  onDelete,
  showActions = true,
}: IntegrationCardProps) {
  // Template card (marketplace view)
  if (template && !instance) {
    return (
      <Link
        to={`/app/integrations/marketplace/${template.id}`}
        className="block bg-theme-card border border-theme rounded-lg p-4 hover:border-theme-primary transition-colors"
      >
        <div className="flex items-start gap-3">
          {template.icon_url ? (
            <img
              src={template.icon_url}
              alt={template.name}
              className="w-10 h-10 rounded-lg"
            />
          ) : (
            <div className="w-10 h-10 rounded-lg bg-theme-surface flex items-center justify-center text-xl">
              {integrationsApi.getTypeIcon(template.integration_type)}
            </div>
          )}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-medium text-theme-primary truncate">
                {template.name}
              </h3>
              {template.is_featured && (
                <span className="px-1.5 py-0.5 text-xs bg-theme-warning bg-opacity-10 text-theme-warning rounded">
                  Featured
                </span>
              )}
            </div>
            <p className="text-sm text-theme-secondary mt-1 line-clamp-2">
              {template.description || 'No description available'}
            </p>
            <div className="flex items-center gap-3 mt-2 text-xs text-theme-tertiary">
              <span>{integrationsApi.getTypeLabel(template.integration_type)}</span>
              <span>{template.category}</span>
              <span>{template.usage_count} installs</span>
            </div>
          </div>
        </div>
      </Link>
    );
  }

  // Instance card (installed integrations view)
  if (instance) {
    const successRate = integrationsApi.getSuccessRate(instance);
    const templateInfo = instance.integration_template;

    return (
      <div className="bg-theme-card border border-theme rounded-lg p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3 flex-1 min-w-0">
            {templateInfo?.icon_url ? (
              <img
                src={templateInfo.icon_url}
                alt={templateInfo.name}
                className="w-10 h-10 rounded-lg"
              />
            ) : (
              <div className="w-10 h-10 rounded-lg bg-theme-surface flex items-center justify-center text-xl">
                {templateInfo
                  ? integrationsApi.getTypeIcon(templateInfo.integration_type)
                  : '📦'}
              </div>
            )}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <Link
                  to={`/app/integrations/${instance.id}`}
                  className="font-medium text-theme-primary hover:text-theme-accent truncate"
                >
                  {instance.name}
                </Link>
                <IntegrationStatusBadge status={instance.status} size="sm" />
              </div>
              {templateInfo && (
                <p className="text-sm text-theme-secondary mt-0.5">
                  {templateInfo.name}
                </p>
              )}
            </div>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4 mt-4 pt-4 border-t border-theme">
          <div>
            <p className="text-xs text-theme-tertiary">Executions</p>
            <p className="text-sm font-medium text-theme-primary">
              {instance.execution_count}
            </p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Success Rate</p>
            <p className="text-sm font-medium text-theme-primary">
              {successRate}%
            </p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Last Run</p>
            <p className="text-sm font-medium text-theme-primary">
              {instance.last_executed_at
                ? new Date(instance.last_executed_at).toLocaleDateString()
                : 'Never'}
            </p>
          </div>
        </div>

        {/* Actions */}
        {showActions && (
          <div className="flex items-center gap-2 mt-4 pt-4 border-t border-theme">
            {instance.status === 'active' ? (
              <button
                onClick={() => onDeactivate?.(instance.id)}
                className="px-3 py-1.5 text-sm text-theme-secondary hover:text-theme-primary bg-theme-surface rounded transition-colors"
              >
                Pause
              </button>
            ) : (
              <button
                onClick={() => onActivate?.(instance.id)}
                className="px-3 py-1.5 text-sm text-white bg-theme-primary hover:bg-theme-primary-hover rounded transition-colors"
              >
                Activate
              </button>
            )}
            <Link
              to={`/app/integrations/${instance.id}`}
              className="px-3 py-1.5 text-sm text-theme-secondary hover:text-theme-primary bg-theme-surface rounded transition-colors"
            >
              Configure
            </Link>
            <button
              onClick={() => onDelete?.(instance.id)}
              className="px-3 py-1.5 text-sm text-theme-error hover:bg-theme-error hover:bg-opacity-10 rounded transition-colors ml-auto"
            >
              Delete
            </button>
          </div>
        )}
      </div>
    );
  }

  return null;
}
