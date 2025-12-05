import React, { useState, useEffect } from 'react';
import { X, Package, Download, Star, ExternalLink, CheckCircle, AlertCircle, Code } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Tabs } from '@/shared/components/ui/Tabs';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { pluginsApi } from '@/shared/services/ai';
import type { Plugin } from '@/shared/types/plugin';
import { PluginTypeBadge } from './PluginTypeBadge';

interface PluginDetailModalProps {
  pluginId: string;
  isOpen: boolean;
  onClose: () => void;
  onInstallSuccess?: () => void;
}

export const PluginDetailModal: React.FC<PluginDetailModalProps> = ({
  pluginId,
  isOpen,
  onClose,
  onInstallSuccess
}) => {
  const [plugin, setPlugin] = useState<Plugin | null>(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [installing, setInstalling] = useState(false);
  const [activeTab, setActiveTab] = useState('overview');

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  const canInstallPlugins = hasPermission('ai.plugins.install');

  useEffect(() => {
    const loadPlugin = async () => {
      try {
        setLoading(true);
        const response = await pluginsApi.getPlugin(pluginId);
        setPlugin(response.plugin);
        setIsInstalled(response.is_installed);
      } catch (error) {
        console.error('Failed to load plugin:', error);
        addNotification({
          type: 'error',
          title: 'Error',
          message: 'Failed to load plugin details'
        });
        onClose();
      } finally {
        setLoading(false);
      }
    };

    if (isOpen && pluginId) {
      loadPlugin();
    }
  }, [isOpen, pluginId, addNotification, onClose]);

  const handleInstall = async () => {
    if (!plugin || !canInstallPlugins) return;

    try {
      setInstalling(true);

      await pluginsApi.installPlugin(plugin.id);

      addNotification({
        type: 'success',
        title: 'Plugin Installed',
        message: `${plugin.name} has been installed successfully`
      });

      setIsInstalled(true);
      onInstallSuccess?.();
    } catch (error) {
      console.error('Failed to install plugin:', error);
      addNotification({
        type: 'error',
        title: 'Installation Failed',
        message: 'Failed to install plugin. Please try again.'
      });
    } finally {
      setInstalling(false);
    }
  };

  if (loading) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} size="xl">
        <div className="p-12">
          <LoadingSpinner />
        </div>
      </Modal>
    );
  }

  if (!plugin) {
    return null;
  }

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'manifest', label: 'Manifest' },
    { id: 'stats', label: 'Statistics' }
  ];

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="xl">
      {/* Header */}
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <div className="flex items-center gap-4">
          <div className="h-16 w-16 bg-theme-surface-elevated rounded-lg flex items-center justify-center">
            {plugin.manifest.plugin?.icon ? (
              <img src={plugin.manifest.plugin.icon} alt={plugin.name} className="h-12 w-12" />
            ) : (
              <Package className="h-12 w-12 text-theme-info" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-2 mb-1">
              <h2 className="text-2xl font-semibold text-theme-primary">{plugin.name}</h2>
              {plugin.is_official && (
                <Badge variant="info" size="sm">
                  <CheckCircle className="h-3 w-3 mr-1" />
                  Official
                </Badge>
              )}
              {plugin.is_verified && !plugin.is_official && (
                <Badge variant="success" size="sm">
                  <CheckCircle className="h-3 w-3 mr-1" />
                  Verified
                </Badge>
              )}
            </div>
            <p className="text-theme-tertiary">by {plugin.author} • v{plugin.version}</p>
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

      {/* Plugin Types */}
      <div className="px-6 py-4 border-b border-theme">
        <div className="flex flex-wrap gap-2">
          {plugin.plugin_types.map(type => (
            <PluginTypeBadge key={type} type={type} />
          ))}
        </div>
      </div>

      {/* Tabs */}
      <Tabs
        value={activeTab}
        onValueChange={setActiveTab}
        className="border-b border-theme"
      >
        <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-interactive-primary text-theme-interactive-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </Tabs>

      {/* Content */}
      <div className="p-6 max-h-[60vh] overflow-y-auto">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {/* Description */}
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Description</h3>
              <p className="text-theme-secondary">{plugin.description}</p>
            </div>

            {/* Capabilities */}
            {plugin.capabilities && plugin.capabilities.length > 0 && (
              <div>
                <h3 className="text-lg font-semibold text-theme-primary mb-2">Capabilities</h3>
                <div className="flex flex-wrap gap-2">
                  {plugin.capabilities.map(capability => (
                    <Badge key={capability} variant="outline" size="sm">
                      {capability}
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            {/* Links */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {plugin.homepage && (
                <a
                  href={plugin.homepage}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-theme-info hover:underline"
                >
                  <ExternalLink className="h-4 w-4" />
                  Homepage
                </a>
              )}
              {plugin.source_url && (
                <a
                  href={plugin.source_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-theme-info hover:underline"
                >
                  <Code className="h-4 w-4" />
                  Source Code
                </a>
              )}
            </div>

            {/* Permissions Warning */}
            {plugin.manifest.permissions && plugin.manifest.permissions.length > 0 && (
              <div className="bg-yellow-50 dark:bg-yellow-900/20 rounded-lg p-4">
                <div className="flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-theme-warning flex-shrink-0 mt-0.5" />
                  <div>
                    <h4 className="font-semibold text-yellow-900 dark:text-yellow-200 mb-2">
                      Required Permissions
                    </h4>
                    <ul className="text-sm text-yellow-800 dark:text-yellow-300 space-y-1">
                      {plugin.manifest.permissions.map(permission => (
                        <li key={permission}>• {permission}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {activeTab === 'manifest' && (
          <div>
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Plugin Manifest</h3>
            <pre className="bg-theme-surface-elevated rounded-lg p-4 overflow-x-auto text-sm text-theme-secondary">
              {JSON.stringify(plugin.manifest, null, 2)}
            </pre>
          </div>
        )}

        {activeTab === 'stats' && (
          <div className="space-y-6">
            {/* Rating */}
            {plugin.average_rating && (
              <div>
                <h3 className="text-lg font-semibold text-theme-primary mb-4">Rating</h3>
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-2">
                    <Star className="h-8 w-8 text-yellow-500 fill-yellow-500" />
                    <span className="text-3xl font-bold text-theme-primary">
                      {plugin.average_rating.toFixed(1)}
                    </span>
                  </div>
                  <span className="text-theme-tertiary">
                    ({plugin.rating_count} {plugin.rating_count === 1 ? 'rating' : 'ratings'})
                  </span>
                </div>
              </div>
            )}

            {/* Download Stats */}
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Downloads</h3>
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-theme-surface-elevated rounded-lg p-4">
                  <p className="text-theme-tertiary text-sm mb-1">Total Installs</p>
                  <p className="text-2xl font-semibold text-theme-primary">
                    {plugin.install_count.toLocaleString()}
                  </p>
                </div>
                <div className="bg-theme-surface-elevated rounded-lg p-4">
                  <p className="text-theme-tertiary text-sm mb-1">Downloads</p>
                  <p className="text-2xl font-semibold text-theme-primary">
                    {plugin.download_count.toLocaleString()}
                  </p>
                </div>
              </div>
            </div>

            {/* Metadata */}
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Information</h3>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-theme-tertiary">Version</span>
                  <span className="text-theme-primary font-medium">{plugin.version}</span>
                </div>
                {plugin.license && (
                  <div className="flex justify-between">
                    <span className="text-theme-tertiary">License</span>
                    <span className="text-theme-primary font-medium">{plugin.license}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-theme-tertiary">Created</span>
                  <span className="text-theme-primary font-medium">
                    {new Date(plugin.created_at).toLocaleDateString()}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-theme-tertiary">Last Updated</span>
                  <span className="text-theme-primary font-medium">
                    {new Date(plugin.updated_at).toLocaleDateString()}
                  </span>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Footer Actions */}
      <div className="flex items-center justify-end gap-3 p-6 border-t border-theme">
        <Button variant="outline" onClick={onClose}>
          Close
        </Button>
        {canInstallPlugins && !isInstalled && (
          <Button
            onClick={handleInstall}
            disabled={installing}
            className="flex items-center gap-2"
          >
            {installing ? (
              <>
                <LoadingSpinner className="h-4 w-4" />
                Installing...
              </>
            ) : (
              <>
                <Download className="h-4 w-4" />
                Install Plugin
              </>
            )}
          </Button>
        )}
        {isInstalled && (
          <Badge variant="success" size="lg" className="px-4 py-2">
            <CheckCircle className="h-4 w-4 mr-2" />
            Installed
          </Badge>
        )}
      </div>
    </Modal>
  );
};
