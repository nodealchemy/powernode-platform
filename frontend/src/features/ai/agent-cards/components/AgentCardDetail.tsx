import React, { useState, useEffect } from 'react';
import {
  Bot,
  Globe,
  Lock,
  Building2,
  Clock,
  AlertCircle,
  Play,
  Pause,
  RefreshCw,
  Copy,
  ExternalLink,
  Code,
  Activity,
  Target,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { agentCardsApiService } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { CapabilityList } from './CapabilityBadge';
import { cn } from '@/shared/utils/cn';
import { formatDateTime } from '@/shared/utils/formatters';
import type { AgentCard, A2aAgentCardJson } from '@/shared/services/ai/types/a2a-types';

interface AgentCardDetailProps {
  cardId: string;
  onEdit?: () => void;
  onClose?: () => void;
  className?: string;
}

const visibilityConfig: Record<string, { icon: React.FC<{ className?: string }>; label: string }> = {
  public: { icon: Globe, label: 'Public' },
  internal: { icon: Building2, label: 'Internal' },
  private: { icon: Lock, label: 'Private' },
};

export const AgentCardDetail: React.FC<AgentCardDetailProps> = ({
  cardId,
  onEdit,
  onClose,
  className,
}) => {
  const [card, setCard] = useState<AgentCard | null>(null);
  const [a2aJson, setA2aJson] = useState<A2aAgentCardJson | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showA2aJson, setShowA2aJson] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const { addNotification } = useNotifications();

  useEffect(() => {
    loadCard();
  }, [cardId]);

  const loadCard = async () => {
    try {
      setLoading(true);
      setError(null);

      const [cardResponse, a2aResponse] = await Promise.all([
        agentCardsApiService.getAgentCard(cardId),
        agentCardsApiService.getA2aJson(cardId).catch(() => null),
      ]);

      setCard(cardResponse.agent_card);
      if (a2aResponse) {
        setA2aJson(a2aResponse);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load agent card');
    } finally {
      setLoading(false);
    }
  };

  const handlePublish = async () => {
    if (!card) return;
    try {
      setActionLoading('publish');
      const response = await agentCardsApiService.publishAgentCard(cardId);
      setCard(response.agent_card);
      addNotification({ type: 'success', title: 'Published', message: response.message });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to publish agent card' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleDeprecate = async () => {
    if (!card) return;
    try {
      setActionLoading('deprecate');
      const response = await agentCardsApiService.deprecateAgentCard(cardId);
      setCard(response.agent_card);
      addNotification({ type: 'success', title: 'Deprecated', message: response.message });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to deprecate agent card' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleRefreshMetrics = async () => {
    if (!card) return;
    try {
      setActionLoading('metrics');
      const response = await agentCardsApiService.refreshMetrics(cardId);
      setCard(response.agent_card);
      addNotification({ type: 'success', title: 'Refreshed', message: 'Metrics updated' });
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to refresh metrics' });
    } finally {
      setActionLoading(null);
    }
  };

  const copyA2aJson = () => {
    if (a2aJson) {
      navigator.clipboard.writeText(JSON.stringify(a2aJson, null, 2));
      addNotification({ type: 'success', title: 'Copied', message: 'A2A JSON copied to clipboard' });
    }
  };

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading agent card..." />
        </CardContent>
      </Card>
    );
  }

  if (error || !card) {
    return (
      <Card className={className}>
        <CardContent className="py-12 text-center">
          <AlertCircle className="h-12 w-12 text-theme-danger mx-auto mb-4" />
          <p className="text-theme-danger">{error || 'Agent card not found'}</p>
          <Button variant="outline" size="sm" onClick={onClose} className="mt-4">
            Go Back
          </Button>
        </CardContent>
      </Card>
    );
  }

  const VisibilityIcon = visibilityConfig[card.visibility]?.icon || Lock;
  const visibilityLabel = visibilityConfig[card.visibility]?.label || card.visibility;

  return (
    <div className={cn('space-y-6', className)}>
      {/* Header Card */}
      <Card>
        <CardContent className="p-6">
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-4">
              <div className="h-16 w-16 bg-theme-info/10 rounded-xl flex items-center justify-center">
                <Bot className="h-8 w-8 text-theme-info" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-theme-primary">{card.name}</h1>
                <p className="text-theme-secondary mt-1">{card.description}</p>
                <div className="flex items-center gap-4 mt-3">
                  <div className="flex items-center gap-1.5 text-sm text-theme-muted">
                    <VisibilityIcon className="h-4 w-4" />
                    <span>{visibilityLabel}</span>
                  </div>
                  {card.protocol_version && (
                    <Badge variant="outline" size="sm">
                      Protocol v{card.protocol_version}
                    </Badge>
                  )}
                  <Badge
                    variant={card.status === 'active' ? 'success' : card.status === 'deprecated' ? 'warning' : 'outline'}
                    size="sm"
                  >
                    {card.status}
                  </Badge>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {card.status === 'inactive' && (
                <Button
                  variant="primary"
                  size="sm"
                  onClick={handlePublish}
                  disabled={actionLoading === 'publish'}
                >
                  {actionLoading === 'publish' ? (
                    <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                  ) : (
                    <Play className="h-4 w-4 mr-2" />
                  )}
                  Publish
                </Button>
              )}
              {card.status === 'active' && (
                <Button
                  variant="warning"
                  size="sm"
                  onClick={handleDeprecate}
                  disabled={actionLoading === 'deprecate'}
                >
                  {actionLoading === 'deprecate' ? (
                    <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                  ) : (
                    <Pause className="h-4 w-4 mr-2" />
                  )}
                  Deprecate
                </Button>
              )}
              <Button variant="outline" size="sm" onClick={onEdit}>
                Edit
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Capabilities */}
          <Card>
            <CardHeader
              title="Capabilities"
              icon={<Target className="h-5 w-5" />}
            />
            <CardContent className="space-y-4">
              {card.capabilities?.skills && card.capabilities.skills.length > 0 ? (
                <div>
                  <h4 className="text-sm font-medium text-theme-secondary mb-2">Skills</h4>
                  <CapabilityList skills={card.capabilities.skills} showAll />
                </div>
              ) : (
                <p className="text-theme-muted text-sm">No capabilities defined</p>
              )}

              {card.capabilities?.streaming !== undefined && (
                <div className="flex items-center gap-2 text-sm">
                  <span className="text-theme-secondary">Streaming:</span>
                  <Badge variant={card.capabilities.streaming ? 'success' : 'outline'} size="sm">
                    {card.capabilities.streaming ? 'Supported' : 'Not Supported'}
                  </Badge>
                </div>
              )}

              {card.capabilities?.push_notifications !== undefined && (
                <div className="flex items-center gap-2 text-sm">
                  <span className="text-theme-secondary">Push Notifications:</span>
                  <Badge variant={card.capabilities.push_notifications ? 'success' : 'outline'} size="sm">
                    {card.capabilities.push_notifications ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>
              )}
            </CardContent>
          </Card>

          {/* A2A JSON */}
          <Card>
            <CardHeader
              title="A2A Agent Card JSON"
              icon={<Code className="h-5 w-5" />}
              action={
                <div className="flex items-center gap-2">
                  <Button variant="ghost" size="sm" onClick={copyA2aJson}>
                    <Copy className="h-4 w-4 mr-1" />
                    Copy
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setShowA2aJson(!showA2aJson)}
                  >
                    {showA2aJson ? 'Hide' : 'Show'}
                  </Button>
                </div>
              }
            />
            {showA2aJson && a2aJson && (
              <CardContent>
                <pre className="bg-theme-surface-dark p-4 rounded-lg text-xs overflow-x-auto max-h-96">
                  <code className="text-theme-primary">
                    {JSON.stringify(a2aJson, null, 2)}
                  </code>
                </pre>
              </CardContent>
            )}
          </Card>

          {/* Authentication */}
          {card.authentication && Object.keys(card.authentication).length > 0 && (
            <Card>
              <CardHeader
                title="Authentication"
                icon={<Lock className="h-5 w-5" />}
              />
              <CardContent>
                <div className="space-y-2">
                  {card.authentication.schemes?.map((scheme, idx) => (
                    <div key={idx} className="flex items-center gap-2">
                      <Badge variant="outline" size="sm">{scheme}</Badge>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Metrics */}
          <Card>
            <CardHeader
              title="Metrics"
              icon={<Activity className="h-5 w-5" />}
              action={
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleRefreshMetrics}
                  disabled={actionLoading === 'metrics'}
                >
                  <RefreshCw className={cn('h-4 w-4', actionLoading === 'metrics' && 'animate-spin')} />
                </Button>
              }
            />
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="text-center p-3 bg-theme-surface rounded-lg">
                  <div className="text-2xl font-bold text-theme-primary">
                    {card.task_count || 0}
                  </div>
                  <div className="text-xs text-theme-muted">Tasks Completed</div>
                </div>
                <div className="text-center p-3 bg-theme-surface rounded-lg">
                  <div className="text-2xl font-bold text-theme-success">
                    {card.task_count > 0 && card.success_count !== undefined
                      ? `${Math.round((card.success_count / card.task_count) * 100)}%`
                      : 'N/A'}
                  </div>
                  <div className="text-xs text-theme-muted">Success Rate</div>
                </div>
              </div>

              {card.avg_response_time_ms !== undefined && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">Avg Duration</span>
                  <span className="text-theme-primary">
                    {card.avg_response_time_ms < 1000
                      ? `${Math.round(card.avg_response_time_ms)}ms`
                      : `${(card.avg_response_time_ms / 1000).toFixed(1)}s`}
                  </span>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Info */}
          <Card>
            <CardHeader title="Information" />
            <CardContent className="space-y-3 text-sm">
              {card.endpoint_url && (
                <div className="flex items-start gap-2">
                  <ExternalLink className="h-4 w-4 text-theme-muted mt-0.5" />
                  <div>
                    <div className="text-theme-secondary">Endpoint</div>
                    <a
                      href={card.endpoint_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-theme-info hover:underline break-all"
                    >
                      {card.endpoint_url}
                    </a>
                  </div>
                </div>
              )}

              <div className="flex items-start gap-2">
                <Clock className="h-4 w-4 text-theme-muted mt-0.5" />
                <div>
                  <div className="text-theme-secondary">Created</div>
                  <div className="text-theme-primary">{formatDateTime(card.created_at)}</div>
                </div>
              </div>

              <div className="flex items-start gap-2">
                <Clock className="h-4 w-4 text-theme-muted mt-0.5" />
                <div>
                  <div className="text-theme-secondary">Updated</div>
                  <div className="text-theme-primary">{formatDateTime(card.updated_at)}</div>
                </div>
              </div>

              {card.ai_agent_id && (
                <div className="flex items-start gap-2">
                  <Bot className="h-4 w-4 text-theme-muted mt-0.5" />
                  <div>
                    <div className="text-theme-secondary">Linked Agent</div>
                    <div className="text-theme-primary font-mono text-xs">{card.ai_agent_id}</div>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default AgentCardDetail;
