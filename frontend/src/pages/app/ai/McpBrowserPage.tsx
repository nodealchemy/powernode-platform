import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Server, Search, RefreshCw, Filter, Package, Zap, AlertCircle, CheckCircle2, Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { McpServerCard } from '@/features/ai/components/McpServerCard';
import { McpToolExplorer } from '@/features/ai/components/McpToolExplorer';
import { McpServerFormModal } from '@/features/ai/components/McpServerFormModal';
import { mcpApi } from '@/shared/services/ai/McpApiService';

export interface McpServer {
  id: string;
  name: string;
  description?: string;
  version: string;
  protocol_version: string;
  status: 'connected' | 'disconnected' | 'connecting' | 'error';
  connection_type: 'stdio' | 'sse' | 'websocket' | 'http';
  capabilities: {
    tools?: boolean;
    resources?: boolean;
    prompts?: boolean;
    logging?: boolean;
  };
  tools_count: number;
  resources_count: number;
  prompts_count: number;
  last_connected_at?: string;
  error_message?: string;
  metadata?: {
    author?: string;
    url?: string;
    icon?: string;
  };
}

export interface McpTool {
  id: string;
  server_id: string;
  server_name: string;
  name: string;
  description?: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  input_schema: any;
  category?: string;
  tags?: string[];
}

export const McpBrowserPage: React.FC = () => {
  const [servers, setServers] = useState<McpServer[]>([]);
  const [tools, setTools] = useState<McpTool[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'connected' | 'disconnected' | 'error'>('all');
  const [selectedTool, setSelectedTool] = useState<McpTool | null>(null);
  const [showToolExplorer, setShowToolExplorer] = useState(false);
  const [showServerForm, setShowServerForm] = useState(false);
  const [editingServer, setEditingServer] = useState<McpServer | null>(null);

  const { addNotification } = useNotifications();
  const { currentUser } = useAuth();

  // Permission checks - memoized to prevent infinite loops
  const canViewMcpServers = useMemo(() =>
    currentUser?.permissions?.includes('ai_orchestration.read') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser?.permissions]);

  // Load MCP servers and tools
  const loadData = useCallback(async (showSpinner = true) => {
    if (!canViewMcpServers) {
      setLoading(false);
      return;
    }

    try {
      if (showSpinner) {
        setLoading(true);
      } else {
        setRefreshing(true);
      }

      // Fetch real data from API
      const response = await mcpApi.getServers();
      setServers(response.servers);
      setTools(response.tools);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load MCP data:', error);
      }
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load MCP servers. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canViewMcpServers]);

  // Initial load - only runs once when canViewMcpServers becomes true
  useEffect(() => {
    if (canViewMcpServers) {
      loadData(true);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canViewMcpServers]);

  // Filter servers
  const filteredServers = useMemo(() => {
    let filtered = servers;

    // Filter by status
    if (filterStatus !== 'all') {
      filtered = filtered.filter(s => s.status === filterStatus);
    }

    // Filter by search query
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(s =>
        s.name.toLowerCase().includes(query) ||
        s.description?.toLowerCase().includes(query)
      );
    }

    return filtered;
  }, [servers, filterStatus, searchQuery]);

  // Statistics
  const statistics = useMemo(() => {
    return {
      total_servers: servers.length,
      connected_servers: servers.filter(s => s.status === 'connected').length,
      total_tools: servers.reduce((sum, s) => sum + s.tools_count, 0),
      total_resources: servers.reduce((sum, s) => sum + s.resources_count, 0)
    };
  }, [servers]);

  const handleRefresh = () => {
    loadData(false);
  };

  const handleTestTool = (tool: McpTool) => {
    setSelectedTool(tool);
    setShowToolExplorer(true);
  };

  // Execute a tool via the MCP API
  const handleExecuteTool = useCallback(async (toolId: string, params: Record<string, any>) => {
    // Find the tool to get its server_id
    const tool = tools.find(t => t.id === toolId);
    if (!tool) {
      throw new Error('Tool not found');
    }

    const result = await mcpApi.executeTool(tool.server_id, toolId, params);

    if (!result.success && result.error) {
      throw new Error(result.error);
    }

    return result.result;
  }, [tools]);

  // Server management handlers
  const handleConnect = useCallback(async (serverId: string) => {
    try {
      const { server } = await mcpApi.connectServer(serverId);
      setServers(prev => prev.map(s => s.id === serverId ? { ...s, ...server } : s));
      addNotification({
        type: 'success',
        title: 'Server Connected',
        message: `Connected to ${server.name}`
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Connection Failed',
        message: error instanceof Error ? error.message : 'Failed to connect server'
      });
      throw error;
    }
  }, [addNotification]);

  const handleDisconnect = useCallback(async (serverId: string) => {
    try {
      const { server } = await mcpApi.disconnectServer(serverId);
      setServers(prev => prev.map(s => s.id === serverId ? { ...s, ...server } : s));
      addNotification({
        type: 'success',
        title: 'Server Disconnected',
        message: `Disconnected from ${server.name}`
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Disconnect Failed',
        message: error instanceof Error ? error.message : 'Failed to disconnect server'
      });
      throw error;
    }
  }, [addNotification]);

  const handleDelete = useCallback(async (serverId: string) => {
    const server = servers.find(s => s.id === serverId);
    if (!server) return;

    if (!confirm(`Are you sure you want to delete ${server.name}? This action cannot be undone.`)) {
      return;
    }

    try {
      await mcpApi.deleteServer(serverId);
      setServers(prev => prev.filter(s => s.id !== serverId));
      setTools(prev => prev.filter(t => t.server_id !== serverId));
      addNotification({
        type: 'success',
        title: 'Server Deleted',
        message: `Deleted ${server.name}`
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: error instanceof Error ? error.message : 'Failed to delete server'
      });
    }
  }, [servers, addNotification]);

  const handleEdit = useCallback((server: McpServer) => {
    setEditingServer(server);
    setShowServerForm(true);
  }, []);

  const handleRefreshCapabilities = useCallback(async (serverId: string) => {
    try {
      const { server } = await mcpApi.refreshServerCapabilities(serverId);
      setServers(prev => prev.map(s => s.id === serverId ? { ...s, ...server } : s));
      // Reload tools for this server
      const { tools: serverTools } = await mcpApi.getTools({ server_id: serverId });
      setTools(prev => [
        ...prev.filter(t => t.server_id !== serverId),
        ...serverTools
      ]);
      addNotification({
        type: 'success',
        title: 'Capabilities Refreshed',
        message: `Refreshed capabilities for ${server.name}`
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Refresh Failed',
        message: error instanceof Error ? error.message : 'Failed to refresh capabilities'
      });
      throw error;
    }
  }, [addNotification]);

  const handleAddServer = () => {
    setEditingServer(null);
    setShowServerForm(true);
  };

  const handleServerFormClose = () => {
    setShowServerForm(false);
    setEditingServer(null);
  };

  const handleServerFormSubmit = async (data: {
    name: string;
    description?: string;
    connection_type: 'stdio' | 'websocket' | 'http';
    command?: string;
    args?: string[];
    env?: Record<string, string>;
  }) => {
    try {
      if (editingServer) {
        const { server } = await mcpApi.updateServer(editingServer.id, data);
        setServers(prev => prev.map(s => s.id === editingServer.id ? { ...s, ...server } : s));
        addNotification({
          type: 'success',
          title: 'Server Updated',
          message: `Updated ${server.name}`
        });
      } else {
        const { server } = await mcpApi.createServer(data);
        setServers(prev => [...prev, server]);
        addNotification({
          type: 'success',
          title: 'Server Created',
          message: `Created ${server.name}`
        });
      }
      handleServerFormClose();
    } catch (error) {
      addNotification({
        type: 'error',
        title: editingServer ? 'Update Failed' : 'Create Failed',
        message: error instanceof Error ? error.message : 'Failed to save server'
      });
      throw error;
    }
  };

  if (!canViewMcpServers) {
    return (
      <PageContainer title="MCP Browser">
        <div className="text-center py-12">
          <AlertCircle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
          <p className="text-theme-secondary">
            You don't have permission to view MCP servers.
          </p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="MCP Browser"
      description="Browse and interact with Model Context Protocol servers and tools"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'MCP Browser' }
      ]}
      actions={[
        {
          id: 'add-server',
          label: 'Add Server',
          onClick: handleAddServer,
          variant: 'primary' as const,
          icon: Plus
        },
        {
          id: 'refresh',
          label: 'Refresh',
          onClick: handleRefresh,
          variant: 'outline' as const,
          icon: RefreshCw,
          disabled: refreshing
        }
      ]}
    >
      <div className="space-y-6">
        {/* Statistics */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-interactive-primary bg-opacity-10 rounded-lg flex items-center justify-center">
                <Server className="h-6 w-6 text-theme-interactive-primary" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Total Servers</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics.total_servers}</p>
              </div>
            </div>
          </Card>

          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
                <CheckCircle2 className="h-6 w-6 text-theme-success" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Connected</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics.connected_servers}</p>
              </div>
            </div>
          </Card>

          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Zap className="h-6 w-6 text-theme-info" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Total Tools</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics.total_tools}</p>
              </div>
            </div>
          </Card>

          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
                <Package className="h-6 w-6 text-theme-warning" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Total Resources</p>
                <p className="text-2xl font-bold text-theme-primary">{statistics.total_resources}</p>
              </div>
            </div>
          </Card>
        </div>

        {/* Filters */}
        <Card className="p-4">
          <div className="flex items-center gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
              <Input
                type="text"
                placeholder="Search servers..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>
            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-theme-tertiary" />
              <Select
                value={filterStatus}
                onChange={(value) => setFilterStatus(value as any)}
                className="w-40"
              >
                <option value="all">All Status</option>
                <option value="connected">Connected</option>
                <option value="disconnected">Disconnected</option>
                <option value="error">Error</option>
              </Select>
            </div>
          </div>
        </Card>

        {/* Server Cards */}
        {loading ? (
          <div className="text-center py-12">
            <RefreshCw className="h-8 w-8 animate-spin text-theme-interactive-primary mx-auto mb-4" />
            <p className="text-theme-secondary">Loading MCP servers...</p>
          </div>
        ) : filteredServers.length === 0 ? (
          <Card className="p-12 text-center">
            <Server className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
            <p className="text-theme-secondary mb-2">No MCP servers found</p>
            {searchQuery && (
              <p className="text-theme-tertiary text-sm">
                Try adjusting your search or filters
              </p>
            )}
          </Card>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {filteredServers.map(server => (
              <McpServerCard
                key={server.id}
                server={server}
                tools={tools.filter(t => t.server_id === server.id)}
                onTestTool={handleTestTool}
                onConnect={handleConnect}
                onDisconnect={handleDisconnect}
                onDelete={handleDelete}
                onEdit={handleEdit}
                onRefreshCapabilities={handleRefreshCapabilities}
              />
            ))}
          </div>
        )}
      </div>

      {/* Tool Explorer Modal */}
      {showToolExplorer && selectedTool && (
        <McpToolExplorer
          tool={selectedTool}
          isOpen={showToolExplorer}
          onClose={() => {
            setShowToolExplorer(false);
            setSelectedTool(null);
          }}
          onExecuteTool={handleExecuteTool}
        />
      )}

      {/* Server Form Modal */}
      {showServerForm && (
        <McpServerFormModal
          isOpen={showServerForm}
          onClose={handleServerFormClose}
          onSubmit={handleServerFormSubmit}
          server={editingServer}
        />
      )}
    </PageContainer>
  );
};
