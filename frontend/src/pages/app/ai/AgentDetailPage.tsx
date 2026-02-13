import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { Bot, MessageSquare, Brain, ArrowLeft, BookOpen } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { agentsApi } from '@/shared/services/ai';
import { AgentConnectionsGraph } from '@/features/ai/agents/components/AgentConnectionsGraph';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import type { AiAgent } from '@/shared/types/ai';

const tabs = [
  { id: 'overview', label: 'Overview', path: '/' },
  { id: 'connections', label: 'Connections', path: '/connections' },
  { id: 'knowledge', label: 'Knowledge', path: '/knowledge' },
];

export const AgentDetailPage: React.FC = () => {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { openConversationMaximized } = useChatWindow();
  const [agent, setAgent] = useState<AiAgent | null>(null);
  const [loading, setLoading] = useState(true);

  const getActiveTab = () => {
    if (location.pathname.includes('/connections')) return 'connections';
    if (location.pathname.includes('/knowledge')) return 'knowledge';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  useEffect(() => {
    if (!agentId) return;
    const load = async () => {
      try {
        setLoading(true);
        const data = await agentsApi.getAgent(agentId);
        setAgent(data);
      } catch (_err) {
        navigate('/app/ai/agents');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [agentId, navigate]);

  if (loading || !agent) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading agent..." />;
  }

  const statusVariant = agent.status === 'active' ? 'success' : agent.status === 'error' ? 'danger' : 'secondary';

  const pageActions = [
    {
      id: 'back',
      label: 'Back to Agents',
      onClick: () => navigate('/app/ai/agents/list'),
      variant: 'secondary' as const,
      icon: ArrowLeft,
    },
    {
      id: 'chat',
      label: 'Chat',
      onClick: () => openConversationMaximized(agent.id, agent.name),
      variant: 'outline' as const,
      icon: MessageSquare,
    },
    {
      id: 'memory',
      label: 'Memory',
      onClick: () => navigate(`/app/ai/agents/${agent.id}/memory`),
      variant: 'outline' as const,
      icon: Brain,
    },
  ];

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Agents', href: '/app/ai/agents' },
      { label: agent.name },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title={agent.name}
      description={agent.description || 'AI Agent'}
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath={`/app/ai/agents/${agentId}`}
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <Card className="p-6">
            <div className="flex items-start gap-4 mb-6">
              <div className="h-12 w-12 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Bot className="h-6 w-6 text-theme-info" />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-1">
                  <h2 className="text-xl font-semibold text-theme-primary">{agent.name}</h2>
                  <Badge variant={statusVariant} size="sm">{agent.status}</Badge>
                </div>
                {agent.description && (
                  <p className="text-sm text-theme-secondary">{agent.description}</p>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Type</span>
                  <span className="text-theme-primary">{agent.agent_type || 'N/A'}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Provider</span>
                  <span className="text-theme-primary">{agent.provider?.name || 'N/A'}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Model</span>
                  <span className="text-theme-primary">{agent.model || 'N/A'}</span>
                </div>
              </div>

              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Total Executions</span>
                  <span className="text-theme-primary">{agent.execution_stats?.total_executions || 0}</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Success Rate</span>
                  <span className="text-theme-primary">{agent.execution_stats?.success_rate || 0}%</span>
                </div>
                {agent.skill_slugs && agent.skill_slugs.length > 0 && (
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-tertiary">Skills</span>
                    <div className="flex flex-wrap gap-1 justify-end">
                      {agent.skill_slugs.map((slug) => (
                        <Badge key={slug} variant="info" size="sm">{slug}</Badge>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </Card>
        </TabPanel>

        <TabPanel tabId="connections" activeTab={activeTab}>
          {agentId && <AgentConnectionsGraph agentId={agentId} />}
        </TabPanel>

        <TabPanel tabId="knowledge" activeTab={activeTab}>
          {agentId && (
            <div className="space-y-4">
              <div className="flex items-center gap-2 mb-4">
                <BookOpen size={18} className="text-theme-secondary" />
                <h3 className="text-lg font-medium text-theme-primary">Agent Knowledge & Contexts</h3>
              </div>
              <ContextBrowser
                filters={{ ai_agent_id: agentId }}
                linkToDetail
              />
            </div>
          )}
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default AgentDetailPage;
