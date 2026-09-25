import React, { useState, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { AppWindow, Plus, Eye, Settings } from 'lucide-react';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { McpAppGallery } from '../components/McpAppGallery';
import { McpAppRenderer } from '../components/McpAppRenderer';
import { McpAppConfigurator } from '../components/McpAppConfigurator';
import type { McpApp } from '../types/mcpApps';

const MCP_APPS_BASE_PATH = '/app/ai/mcp/apps';

const getActiveMcpAppsTab = (pathname: string): string => {
  if (pathname.startsWith(`${MCP_APPS_BASE_PATH}/preview`)) return 'preview';
  if (pathname.startsWith(`${MCP_APPS_BASE_PATH}/configure`)) return 'configure';
  return 'gallery';
};

const McpAppsPage: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const { hasPermission } = usePermissions();
  const [selectedApp, setSelectedApp] = useState<McpApp | null>(null);
  const [editingAppId, setEditingAppId] = useState<string | null>(null);
  const [showConfigurator, setShowConfigurator] = useState(false);
  const [activeTab, setActiveTab] = useState(getActiveMcpAppsTab(location.pathname));

  useEffect(() => {
    const newTab = getActiveMcpAppsTab(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const canView = hasPermission('ai.agents.read');
  const canManage = hasPermission('ai.agents.manage');

  if (!canView) {
    return (
      <div className="text-center py-12">
        <AppWindow className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view MCP Apps.</p>
      </div>
    );
  }

  const handleSelectApp = (app: McpApp) => {
    setSelectedApp(app);
    setActiveTab('preview');
    navigate(`${MCP_APPS_BASE_PATH}/preview`);
  };

  const handleEditApp = (app: McpApp) => {
    setEditingAppId(app.id);
    setShowConfigurator(true);
    setActiveTab('configure');
    navigate(`${MCP_APPS_BASE_PATH}/configure`);
  };

  const handleNewApp = () => {
    setEditingAppId(null);
    setShowConfigurator(true);
    setActiveTab('configure');
    navigate(`${MCP_APPS_BASE_PATH}/configure`);
  };

  const handleConfiguratorClose = () => {
    setShowConfigurator(false);
    setEditingAppId(null);
    setActiveTab('gallery');
    navigate(MCP_APPS_BASE_PATH);
  };

  const handleConfiguratorSaved = () => {
    setShowConfigurator(false);
    setEditingAppId(null);
    setActiveTab('gallery');
    navigate(MCP_APPS_BASE_PATH);
  };

  const tabs = [
    {
      id: 'gallery',
      label: 'Gallery',
      icon: <AppWindow className="h-4 w-4" />,
      path: '/',
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
      path: '/preview',
      content: selectedApp ? (
        <McpAppRenderer
          appId={selectedApp.id}
          appName={selectedApp.name}
        />
      ) : (
        <div className="text-center py-12">
          <Eye className="h-8 w-8 text-theme-tertiary mx-auto mb-2 opacity-50" />
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
            path: '/configure',
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
            className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-interactive-primary text-theme-on-primary rounded hover:opacity-90"
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
        basePath={MCP_APPS_BASE_PATH}
        renderContent={(tabId) => tabs.find((tab) => tab.id === tabId)?.content}
        variant="underline"
      />
    </div>
  );
};

// Re-export as named content component for embedding
export { McpAppsPage as McpAppsContent };

