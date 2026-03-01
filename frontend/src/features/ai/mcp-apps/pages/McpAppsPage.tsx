import React, { useState } from 'react';
import { AppWindow, Plus, Eye, Settings } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { McpAppGallery } from '../components/McpAppGallery';
import { McpAppRenderer } from '../components/McpAppRenderer';
import { McpAppConfigurator } from '../components/McpAppConfigurator';
import type { McpApp } from '../types/mcpApps';

export const McpAppsPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const [selectedApp, setSelectedApp] = useState<McpApp | null>(null);
  const [editingAppId, setEditingAppId] = useState<string | null>(null);
  const [showConfigurator, setShowConfigurator] = useState(false);
  const [activeTab, setActiveTab] = useState('gallery');

  const canView = hasPermission('ai.agents.read');
  const canManage = hasPermission('ai.agents.manage');

  if (!canView) {
    return (
      <div className="text-center py-12">
        <AppWindow className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view MCP Apps.</p>
      </div>
    );
  }

  const handleSelectApp = (app: McpApp) => {
    setSelectedApp(app);
    setActiveTab('preview');
  };

  const handleEditApp = (app: McpApp) => {
    setEditingAppId(app.id);
    setShowConfigurator(true);
    setActiveTab('configure');
  };

  const handleNewApp = () => {
    setEditingAppId(null);
    setShowConfigurator(true);
    setActiveTab('configure');
  };

  const handleConfiguratorClose = () => {
    setShowConfigurator(false);
    setEditingAppId(null);
    setActiveTab('gallery');
  };

  const handleConfiguratorSaved = () => {
    setShowConfigurator(false);
    setEditingAppId(null);
    setActiveTab('gallery');
  };

  const tabs = [
    {
      id: 'gallery',
      label: 'Gallery',
      icon: <AppWindow className="h-4 w-4" />,
      content: (
        <McpAppGallery
          onSelectApp={handleSelectApp}
          onEditApp={handleEditApp}
          selectedAppId={selectedApp?.id || null}
        />
      ),
    },
    {
      id: 'preview',
      label: 'Preview',
      icon: <Eye className="h-4 w-4" />,
      content: selectedApp ? (
        <McpAppRenderer
          appId={selectedApp.id}
          appName={selectedApp.name}
        />
      ) : (
        <div className="text-center py-12">
          <Eye className="h-8 w-8 text-theme-muted mx-auto mb-2 opacity-50" />
          <p className="text-sm text-theme-secondary">Select an app from the gallery to preview.</p>
        </div>
      ),
    },
    ...(showConfigurator
      ? [
          {
            id: 'configure',
            label: 'Configure',
            icon: <Settings className="h-4 w-4" />,
            content: (
              <McpAppConfigurator
                appId={editingAppId || undefined}
                onClose={handleConfiguratorClose}
                onSaved={handleConfiguratorSaved}
              />
            ),
          },
        ]
      : []),
  ];

  return (
    <div>
      {canManage && (
        <div className="flex justify-end mb-4">
          <button
            onClick={handleNewApp}
            className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-primary text-theme-on-primary rounded hover:opacity-90"
          >
            <Plus className="h-4 w-4" />
            New App
          </button>
        </div>
      )}
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        variant="underline"
      />
    </div>
  );
};

// Re-export as named content component for embedding
export { McpAppsPage as McpAppsContent };

// Standalone page wrapper
export const McpAppsStandalonePage: React.FC = () => (
  <PageContainer
    title="MCP Apps"
    description="Model Context Protocol apps gallery, sandboxed rendering, and configuration"
    breadcrumbs={[
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'MCP Apps' },
    ]}
  >
    <McpAppsPage />
  </PageContainer>
);
