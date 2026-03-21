import React, { useState, useEffect } from 'react';
import {
  X,
  Package,
  FileCode,
  Link,
  User,
  Calendar,
  ExternalLink,
  CheckCircle,
  XCircle,
  Globe,
  Lock
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemPuppetModule, SystemPuppetResource } from '@/features/system/types/system.types';

interface PuppetModuleDetailModalProps {
  moduleId: string | null;
  isOpen: boolean;
  onClose: () => void;
  onEdit?: (module: SystemPuppetModule) => void;
}

type TabId = 'info' | 'resources' | 'dependencies' | 'metadata';

/**
 * PuppetModuleDetailModal - Modal for viewing Puppet module details with tabs
 */
export const PuppetModuleDetailModal: React.FC<PuppetModuleDetailModalProps> = ({
  moduleId,
  isOpen,
  onClose,
  onEdit
}) => {
  const [module, setModule] = useState<SystemPuppetModule | null>(null);
  const [resources, setResources] = useState<SystemPuppetResource[]>([]);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>('info');

  useEffect(() => {
    if (isOpen && moduleId) {
      setLoading(true);
      setActiveTab('info');

      Promise.all([
        systemApi.getPuppetModule(moduleId),
        systemApi.getPuppetResources(moduleId)
      ])
        .then(([moduleData, resourcesData]) => {
          setModule(moduleData);
          setResources(resourcesData);
        })
        .catch(() => {
          setModule(null);
          setResources([]);
        })
        .finally(() => {
          setLoading(false);
        });
    }
  }, [isOpen, moduleId]);

  if (!isOpen) return null;

  const tabs = [
    { id: 'info' as const, label: 'Information', icon: Package },
    { id: 'resources' as const, label: 'Resources', icon: FileCode, count: resources.length },
    { id: 'dependencies' as const, label: 'Dependencies', icon: Link, count: module?.dependencies?.length || 0 },
    { id: 'metadata' as const, label: 'Metadata', icon: Package }
  ];

  const renderInfoTab = () => {
    if (!module) return null;

    return (
      <div className="space-y-6">
        {/* Basic Info */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Name</label>
              <p className="text-theme-primary font-medium">{module.name}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Description</label>
              <p className="text-theme-primary">{module.description || '—'}</p>
            </div>
            {module.forge_name && (
              <div>
                <label className="block text-sm text-theme-secondary mb-1">Forge Name</label>
                <p className="text-theme-primary font-mono text-sm">{module.forge_name}</p>
              </div>
            )}
          </div>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Version</label>
              <p className="text-theme-primary">{module.version || '—'}</p>
            </div>
            <div>
              <label className="block text-sm text-theme-secondary mb-1">Author</label>
              <div className="flex items-center gap-2 text-theme-primary">
                <User className="w-4 h-4 text-theme-tertiary" />
                <span>{module.author || '—'}</span>
              </div>
            </div>
            {module.license && (
              <div>
                <label className="block text-sm text-theme-secondary mb-1">License</label>
                <p className="text-theme-primary">{module.license}</p>
              </div>
            )}
          </div>
        </div>

        {/* URLs */}
        {(module.source_url || module.project_url) && (
          <div className="pt-4 border-t border-theme space-y-3">
            {module.source_url && (
              <div>
                <label className="block text-sm text-theme-secondary mb-1">Source URL</label>
                <a
                  href={module.source_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-theme-link hover:underline flex items-center gap-1"
                >
                  {module.source_url}
                  <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            )}
            {module.project_url && (
              <div>
                <label className="block text-sm text-theme-secondary mb-1">Project URL</label>
                <a
                  href={module.project_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-theme-link hover:underline flex items-center gap-1"
                >
                  {module.project_url}
                  <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            )}
          </div>
        )}

        {/* Status Badges */}
        <div className="flex flex-wrap gap-4 pt-4 border-t border-theme">
          <div className="flex items-center gap-2">
            {module.enabled ? (
              <CheckCircle className="w-5 h-5 text-theme-success" />
            ) : (
              <XCircle className="w-5 h-5 text-theme-error" />
            )}
            <span className="text-theme-primary">
              {module.enabled ? 'Enabled' : 'Disabled'}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {module.public ? (
              <Globe className="w-5 h-5 text-theme-info" />
            ) : (
              <Lock className="w-5 h-5 text-theme-secondary" />
            )}
            <span className="text-theme-primary">
              {module.public ? 'Public' : 'Private'}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <FileCode className="w-5 h-5 text-theme-secondary" />
            <span className="text-theme-primary">
              {module.resource_count || 0} Resources
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Link className="w-5 h-5 text-theme-secondary" />
            <span className="text-theme-primary">
              {module.assigned_modules_count || 0} Assigned
            </span>
          </div>
        </div>

        {/* Timestamps */}
        <div className="grid grid-cols-2 gap-4 pt-4 border-t border-theme text-sm">
          <div className="flex items-center gap-2">
            <Calendar className="w-4 h-4 text-theme-tertiary" />
            <span className="text-theme-secondary">Created:</span>
            <span className="text-theme-primary">
              {new Date(module.created_at).toLocaleString()}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Calendar className="w-4 h-4 text-theme-tertiary" />
            <span className="text-theme-secondary">Updated:</span>
            <span className="text-theme-primary">
              {new Date(module.updated_at).toLocaleString()}
            </span>
          </div>
        </div>
      </div>
    );
  };

  const renderResourcesTab = () => {
    if (resources.length === 0) {
      return (
        <div className="text-center py-12">
          <FileCode className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <p className="text-theme-secondary">No resources defined</p>
          <p className="text-sm text-theme-tertiary mt-1">
            This module has no Puppet resources
          </p>
        </div>
      );
    }

    return (
      <div className="space-y-4">
        {resources.map(resource => (
          <div
            key={resource.id}
            className="bg-theme-background rounded-lg p-4 border border-theme"
          >
            <div className="flex items-start justify-between mb-2">
              <div>
                <h4 className="font-medium text-theme-primary">{resource.name}</h4>
                <div className="flex items-center gap-2 mt-1">
                  <Badge variant="primary" size="xs">{resource.resource_type}</Badge>
                  {resource.title && (
                    <span className="text-sm text-theme-secondary">{resource.title}</span>
                  )}
                </div>
              </div>
              <Badge variant={resource.enabled ? 'success' : 'secondary'} size="xs">
                {resource.enabled ? 'Enabled' : 'Disabled'}
              </Badge>
            </div>
            {resource.description && (
              <p className="text-sm text-theme-secondary mt-2">{resource.description}</p>
            )}
            {resource.path && (
              <p className="text-xs text-theme-tertiary mt-2 font-mono">{resource.path}</p>
            )}
            {resource.data && (
              <pre className="mt-3 bg-theme-surface rounded p-3 text-xs text-theme-primary overflow-x-auto max-h-32 font-mono border border-theme">
                {resource.data}
              </pre>
            )}
          </div>
        ))}
      </div>
    );
  };

  const renderDependenciesTab = () => {
    if (!module?.dependencies || module.dependencies.length === 0) {
      return (
        <div className="text-center py-12">
          <Link className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <p className="text-theme-secondary">No dependencies</p>
          <p className="text-sm text-theme-tertiary mt-1">
            This module has no external dependencies
          </p>
        </div>
      );
    }

    return (
      <div className="space-y-4">
        {module.dependencies.map((dep, index) => (
          <div
            key={index}
            className="bg-theme-background rounded-lg p-4 border border-theme flex items-center justify-between"
          >
            <div>
              <h4 className="font-medium text-theme-primary">{dep.name}</h4>
            </div>
            {dep.version_requirement && (
              <Badge variant="secondary" size="sm">
                {dep.version_requirement}
              </Badge>
            )}
          </div>
        ))}
      </div>
    );
  };

  const renderMetadataTab = () => {
    if (!module) return null;

    const hasConfig = module.config && Object.keys(module.config).length > 0;
    const hasMetadata = module.metadata && Object.keys(module.metadata).length > 0;

    return (
      <div className="space-y-6">
        {/* Config */}
        <div>
          <h4 className="font-medium text-theme-primary mb-2">Configuration</h4>
          {hasConfig ? (
            <pre className="bg-theme-background rounded-lg p-4 text-sm text-theme-primary overflow-x-auto border border-theme font-mono">
              {JSON.stringify(module.config, null, 2)}
            </pre>
          ) : (
            <p className="text-theme-secondary text-sm">No configuration defined</p>
          )}
        </div>

        {/* Metadata */}
        <div>
          <h4 className="font-medium text-theme-primary mb-2">Metadata</h4>
          {hasMetadata ? (
            <pre className="bg-theme-background rounded-lg p-4 text-sm text-theme-primary overflow-x-auto border border-theme font-mono">
              {JSON.stringify(module.metadata, null, 2)}
            </pre>
          ) : (
            <p className="text-theme-secondary text-sm">No metadata defined</p>
          )}
        </div>

        {/* Resource Types */}
        {module.resource_types && module.resource_types.length > 0 && (
          <div>
            <h4 className="font-medium text-theme-primary mb-2">Resource Types</h4>
            <div className="flex flex-wrap gap-2">
              {module.resource_types.map((type, index) => (
                <Badge key={index} variant="secondary">{type}</Badge>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-4xl bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Package className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : module?.name || 'Puppet Module Details'}
                </h2>
                {module && module.version && (
                  <p className="text-sm text-theme-secondary">
                    v{module.version}
                  </p>
                )}
              </div>
            </div>
            <div className="flex items-center gap-2">
              {module && onEdit && (
                <Button variant="outline" size="sm" onClick={() => onEdit(module)}>
                  Edit
                </Button>
              )}
              <Button variant="ghost" size="sm" onClick={onClose}>
                <X className="w-5 h-5" />
              </Button>
            </div>
          </div>

          {/* Tabs */}
          <div className="border-b border-theme">
            <nav className="flex -mb-px">
              {tabs.map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
                    activeTab === tab.id
                      ? 'border-theme-accent text-theme-accent'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
                  }`}
                >
                  <tab.icon className="w-4 h-4" />
                  {tab.label}
                  {tab.count !== undefined && tab.count > 0 && (
                    <span className="ml-1 px-1.5 py-0.5 text-xs bg-theme-background rounded">
                      {tab.count}
                    </span>
                  )}
                </button>
              ))}
            </nav>
          </div>

          {/* Content */}
          <div className="p-6 max-h-[60vh] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <LoadingSpinner size="lg" />
              </div>
            ) : module ? (
              <>
                {activeTab === 'info' && renderInfoTab()}
                {activeTab === 'resources' && renderResourcesTab()}
                {activeTab === 'dependencies' && renderDependenciesTab()}
                {activeTab === 'metadata' && renderMetadataTab()}
              </>
            ) : (
              <div className="text-center py-12">
                <p className="text-theme-error">Failed to load module details</p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PuppetModuleDetailModal;
