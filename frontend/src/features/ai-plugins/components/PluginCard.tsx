
import { Package, ExternalLink, Download, Settings, CheckCircle, Star } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { Plugin } from '@/shared/types/plugin';
import { PluginTypeBadge } from './PluginTypeBadge';

interface PluginCardProps {
  plugin: Plugin;
  showInstallButton?: boolean;
  showConfigButton?: boolean;
  onInstall?: (pluginId: string) => void;
  onConfigure?: (pluginId: string) => void;
  onViewDetails?: (pluginId: string) => void;
}

export const PluginCard: React.FC<PluginCardProps> = ({
  plugin,
  showInstallButton = false,
  showConfigButton = false,
  onInstall,
  onConfigure,
  onViewDetails
}) => {
  const isInstalled = plugin.status === 'installed';
  const isOfficial = plugin.is_official;
  const isVerified = plugin.is_verified;

  return (
    <Card className="p-6 hover:border-theme-info transition-colors">
      <div className="flex items-start gap-4 mb-4">
        {/* Plugin Icon */}
        <div className="h-12 w-12 bg-theme-surface-elevated rounded-lg flex items-center justify-center flex-shrink-0">
          {plugin.manifest.plugin?.icon ? (
            <img
              src={plugin.manifest.plugin.icon}
              alt={plugin.name}
              className="h-8 w-8"
            />
          ) : (
            <Package className="h-8 w-8 text-theme-info" />
          )}
        </div>

        {/* Plugin Header */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <h3 className="text-lg font-semibold text-theme-primary truncate">
              {plugin.name}
            </h3>
            {isOfficial && (
              <Badge variant="info" size="sm" className="flex-shrink-0">
                <CheckCircle className="h-3 w-3 mr-1" />
                Official
              </Badge>
            )}
            {isVerified && !isOfficial && (
              <Badge variant="success" size="sm" className="flex-shrink-0">
                <CheckCircle className="h-3 w-3 mr-1" />
                Verified
              </Badge>
            )}
          </div>

          <p className="text-sm text-theme-tertiary">
            by {plugin.author}
          </p>
        </div>
      </div>

      {/* Description */}
      <p className="text-sm text-theme-secondary mb-4 line-clamp-2">
        {plugin.description}
      </p>

      {/* Plugin Types */}
      <div className="flex flex-wrap gap-2 mb-4">
        {plugin.plugin_types.map(type => (
          <PluginTypeBadge key={type} type={type} />
        ))}
      </div>

      {/* Ratings and Stats */}
      <div className="flex items-center gap-4 text-sm text-theme-tertiary mb-4 flex-wrap">
        {plugin.average_rating && (
          <div className="flex items-center gap-1">
            <Star className="h-4 w-4 text-theme-warning fill-theme-warning" />
            <span>{plugin.average_rating.toFixed(1)}</span>
            <span>({plugin.rating_count})</span>
          </div>
        )}

        <div className="flex items-center gap-1">
          <Download className="h-4 w-4" />
          <span>{plugin.install_count.toLocaleString()} installs</span>
        </div>
      </div>

      {/* Meta Information */}
      <div className="text-xs text-theme-tertiary mb-4 flex items-center justify-between">
        <span>v{plugin.version}</span>
        <span>Updated {new Date(plugin.updated_at).toLocaleDateString()}</span>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onViewDetails?.(plugin.id)}
          className="flex-1"
        >
          <ExternalLink className="h-4 w-4 mr-2" />
          Details
        </Button>

        {showConfigButton && isInstalled && (
          <Button
            variant="secondary"
            size="sm"
            onClick={() => onConfigure?.(plugin.id)}
            className="flex-1"
          >
            <Settings className="h-4 w-4 mr-2" />
            Configure
          </Button>
        )}

        {showInstallButton && !isInstalled && (
          <Button
            variant="secondary"
            size="sm"
            onClick={() => onInstall?.(plugin.id)}
            className="flex-1"
          >
            <Package className="h-4 w-4 mr-2" />
            Install
          </Button>
        )}

        {isInstalled && !showConfigButton && (
          <Badge variant="success" size="sm" className="flex-1 justify-center py-2">
            <CheckCircle className="h-3 w-3 mr-1" />
            Installed
          </Badge>
        )}
      </div>
    </Card>
  );
};
