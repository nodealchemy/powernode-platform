import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Bot, MessageSquare, Brain } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { agentsApi } from '@/shared/services/ai';
import { AgentConnectionsGraph } from '@/features/ai/agents/components/AgentConnectionsGraph';
import type { AiAgent } from '@/shared/types/ai';

export const AgentDetailPage: React.FC = () => {
  const { agentId } = useParams<{ agentId: string }>();
  const navigate = useNavigate();
  const [agent, setAgent] = useState<AiAgent | null>(null);
  const [loading, setLoading] = useState(true);

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
      id: 'chat',
      label: 'Chat',
      onClick: () => navigate(`/app/ai/agents/${agent.id}/chat`),
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

  return (
    <PageContainer
      title={agent.name}
      description={agent.description || 'AI Agent'}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Agents', href: '/app/ai/agents' },
        { label: agent.name },
      ]}
      actions={pageActions}
    >
      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="connections">Connections</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">
          <Card className="p-6 mt-4">
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
        </TabsContent>

        <TabsContent value="connections">
          <div className="mt-4">
            {agentId && <AgentConnectionsGraph agentId={agentId} />}
          </div>
        </TabsContent>
      </Tabs>
    </PageContainer>
  );
};

export default AgentDetailPage;
