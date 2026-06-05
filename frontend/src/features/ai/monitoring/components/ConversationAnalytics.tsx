
import {
  BarChart3,
  Clock,
  MessageCircle,
  RefreshCw,
  TrendingUp
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import { Loading } from '@/shared/components/ui/Loading';
import { EntityLink } from '@/shared/components/entity';
import { ConversationMetrics } from '@/shared/types/monitoring';

interface ConversationAnalyticsProps {
  conversations: ConversationMetrics[];
  isLoading: boolean;
  timeRange: string;
  onRefresh: () => void;
}

export const ConversationAnalytics: React.FC<ConversationAnalyticsProps> = ({
  conversations,
  isLoading,
  timeRange: _timeRange,
  onRefresh
}) => {
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'active': return 'success';
      case 'inactive': return 'outline';
      case 'archived': return 'secondary';
      default: return 'outline';
    }
  };

  if (isLoading && conversations.length === 0) {
    return (
      <Card>
        <CardHeader title="Conversation Analytics" />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading conversation data..." />
        </CardContent>
      </Card>
    );
  }

  // Calculate summary statistics
  const totalMessages = conversations.reduce((sum, conv) => sum + conv.usage.messages_count, 0);
  const totalCost = conversations.reduce((sum, conv) => sum + conv.usage.total_cost, 0);
  const avgResponseTime = conversations.length > 0 
    ? conversations.reduce((sum, conv) => sum + conv.performance.avg_response_time, 0) / conversations.length
    : 0;
  const avgSuccessRate = conversations.length > 0
    ? conversations.reduce((sum, conv) => sum + conv.performance.success_rate, 0) / conversations.length
    : 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">Conversation Analytics</h3>
        <Button
          onClick={onRefresh}
          variant="outline"
          size="sm"
          disabled={isLoading}
        >
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Total Messages</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {totalMessages.toLocaleString()}
                </p>
              </div>
              <MessageCircle className="h-8 w-8 text-theme-info" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Avg Response Time</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {avgResponseTime.toFixed(0)}ms
                </p>
              </div>
              <Clock className="h-8 w-8 text-theme-warning" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Success Rate</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {avgSuccessRate.toFixed(1)}%
                </p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Total Cost</p>
                <p className="text-2xl font-bold text-theme-primary">
                  ${totalCost.toFixed(4)}
                </p>
              </div>
              <BarChart3 className="h-8 w-8 text-theme-error" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Conversation Details */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {conversations.map((conversation) => (
          <Card key={conversation.id}>
            <div className="flex items-start justify-between mb-4 pb-3">
              <div className="flex items-start gap-3">
                <div>
                  <EntityLink
                    type="conversation"
                    id={conversation.id}
                    label={conversation.title}
                    className="text-lg font-semibold"
                  />
                </div>
              </div>
              <div className="flex-shrink-0">
                <Badge variant={getStatusBadge(conversation.status)}>{conversation.status}</Badge>
              </div>
            </div>
            <CardContent className="space-y-4">
              {/* Health Score */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">Health Score</span>
                  <span className={`font-medium ${conversation.health_score >= 90 ? 'text-theme-success' : conversation.health_score >= 70 ? 'text-theme-warning' : 'text-theme-error'}`}>
                    {conversation.health_score.toFixed(1)}%
                  </span>
                </div>
                <Progress value={conversation.health_score} className="h-2" />
              </div>

              {/* Message Distribution */}
              <div className="grid grid-cols-3 gap-2 text-sm">
                <div className="text-center p-2 bg-theme-surface rounded">
                  <div className="font-medium text-theme-primary">
                    {conversation.participants.human_messages}
                  </div>
                  <div className="text-xs text-theme-tertiary">Human</div>
                </div>
                <div className="text-center p-2 bg-theme-surface rounded">
                  <div className="font-medium text-theme-success">
                    {conversation.participants.ai_messages}
                  </div>
                  <div className="text-xs text-theme-tertiary">AI</div>
                </div>
                <div className="text-center p-2 bg-theme-surface rounded">
                  <div className="font-medium text-theme-info">
                    {conversation.participants.system_messages}
                  </div>
                  <div className="text-xs text-theme-tertiary">System</div>
                </div>
              </div>

              {/* Performance Metrics */}
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-theme-tertiary block">Avg Response</span>
                  <span className="font-medium">
                    {conversation.performance.avg_response_time.toFixed(0)}ms
                  </span>
                </div>
                <div>
                  <span className="text-theme-tertiary block">Throughput</span>
                  <span className="font-medium">
                    {conversation.performance.message_throughput.toFixed(1)}/min
                  </span>
                </div>
              </div>

              {/* Usage Stats */}
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-theme-tertiary block">Total Messages</span>
                  <span className="font-medium">
                    {conversation.usage.messages_count}
                  </span>
                </div>
                <div>
                  <span className="text-theme-tertiary block">Tokens</span>
                  <span className="font-medium">
                    {conversation.usage.total_tokens.toLocaleString()}
                  </span>
                </div>
              </div>

              {/* Cost */}
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-tertiary">Total Cost</span>
                <span className="font-medium">
                  ${conversation.usage.total_cost.toFixed(4)}
                </span>
              </div>

              {/* Agent Usage */}
              {conversation.agent_usage.length > 0 && (
                <div className="space-y-2">
                  <span className="text-sm text-theme-tertiary">Agent Usage</span>
                  <div className="space-y-1">
                    {conversation.agent_usage.slice(0, 2).map((agent, index) => (
                      <div key={index} className="flex items-center justify-between text-xs">
                        <EntityLink
                          type="agent"
                          id={agent.agent_id}
                          label={agent.agent_name}
                          className="text-theme-tertiary truncate"
                        />
                        <span className="font-medium">{agent.message_count}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Last Activity */}
              {conversation.last_activity && (
                <div className="flex items-center gap-2 text-xs text-theme-tertiary">
                  <Clock className="h-3 w-3" />
                  <span>Last: {new Date(conversation.last_activity).toLocaleTimeString()}</span>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {conversations.length === 0 && !isLoading && (
        <Card>
          <CardContent className="py-8 text-center">
            <MessageCircle className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
            <p className="text-theme-tertiary">No conversations found for the selected time range</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
};