import React from 'react';
import {
  Bot,
  BarChart3,
  Activity,
  MessageCircle,
  DollarSign,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiConversation } from '@/shared/types/ai';

interface ConversationStats {
  message_count?: number;
  user_message_count?: number;
  ai_response_count?: number;
  avg_response_time?: number;
  total_tokens?: number;
  total_cost?: number;
  duration_minutes?: number;
}

interface ConversationStatsPanelProps {
  conversation: AiConversation;
  stats: ConversationStats | null;
  section: 'header' | 'overview' | 'stats' | 'details';
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 4 }).format(amount);

const formatDate = (dateStr: string | undefined | null, format: 'date' | 'time' | 'full' = 'full') => {
  if (!dateStr) return 'N/A';
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return 'N/A';
  switch (format) {
    case 'date': return date.toLocaleDateString();
    case 'time': return date.toLocaleTimeString();
    default: return date.toLocaleString();
  }
};

const renderStatusBadge = (status: string) => {
  const statusConfig = {
    active: { variant: 'success' as const, label: 'Active' },
    completed: { variant: 'info' as const, label: 'Completed' },
    archived: { variant: 'secondary' as const, label: 'Archived' },
    error: { variant: 'danger' as const, label: 'Error' },
  };
  const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.active;
  return <Badge variant={config.variant} size="sm">{config.label}</Badge>;
};

export const ConversationStatsPanel: React.FC<ConversationStatsPanelProps> = ({
  conversation,
  stats,
  section,
}) => {
  if (section === 'header') {
    return (
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Status</p>
                {renderStatusBadge(conversation.status)}
              </div>
              <Activity className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Messages</p>
                <p className="text-lg font-semibold text-theme-primary">
                  {conversation.metadata?.total_messages || conversation.message_count || 0}
                </p>
              </div>
              <MessageCircle className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Total Cost</p>
                <p className="text-lg font-semibold text-theme-primary">
                  {formatCurrency(conversation.metadata?.total_cost || 0)}
                </p>
              </div>
              <DollarSign className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Tokens Used</p>
                <p className="text-lg font-semibold text-theme-primary">
                  {(conversation.metadata?.total_tokens || 0).toLocaleString()}
                </p>
              </div>
              <BarChart3 className="h-5 w-5 text-theme-muted" />
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (section === 'overview') {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <CardHeader title="Conversation Information" />
          <CardContent className="space-y-4">
            <div>
              <label className="text-sm font-medium text-theme-muted">AI Agent</label>
              <div className="mt-1 flex items-center gap-2">
                <Bot className="h-4 w-4 text-theme-muted" />
                <span className="text-theme-primary">{conversation.ai_agent?.name || 'Unknown Agent'}</span>
                {conversation.ai_agent?.agent_type && (
                  <Badge variant="outline" size="sm">
                    {conversation.ai_agent.agent_type.replace('_', ' ')}
                  </Badge>
                )}
              </div>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-muted">Status</label>
              <p className="mt-1 text-theme-primary capitalize">{conversation.status}</p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-muted">Created</label>
              <p className="mt-1 text-theme-primary">
                {formatDate(conversation.created_at, 'date')} at {formatDate(conversation.created_at, 'time')}
              </p>
            </div>
            <div>
              <label className="text-sm font-medium text-theme-muted">Last Activity</label>
              <p className="mt-1 text-theme-primary">
                {formatDate(conversation.metadata?.last_activity || conversation.updated_at)}
              </p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader title="Usage Statistics" />
          <CardContent className="space-y-4">
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Messages:</span>
              <span className="font-medium text-theme-primary">
                {conversation.metadata?.total_messages || conversation.message_count || 0}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Tokens:</span>
              <span className="font-medium text-theme-primary">
                {(conversation.metadata?.total_tokens || 0).toLocaleString()}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Cost:</span>
              <span className="font-medium text-theme-primary">
                {formatCurrency(conversation.metadata?.total_cost || 0)}
              </span>
            </div>
            {stats && (
              <>
                <div className="flex justify-between">
                  <span className="text-theme-muted">Avg Response Time:</span>
                  <span className="font-medium text-theme-primary">
                    {stats.avg_response_time ? `${stats.avg_response_time}ms` : 'N/A'}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-theme-muted">Duration:</span>
                  <span className="font-medium text-theme-primary">
                    {stats.duration_minutes ? `${Math.round(stats.duration_minutes)} min` : 'N/A'}
                  </span>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  if (section === 'stats') {
    return stats ? (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-3">
          <h4 className="font-medium text-theme-primary">Message Statistics</h4>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Messages:</span>
              <span className="text-theme-primary">{stats.message_count}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">User Messages:</span>
              <span className="text-theme-primary">{stats.user_message_count}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">AI Responses:</span>
              <span className="text-theme-primary">{stats.ai_response_count}</span>
            </div>
          </div>
        </div>
        <div className="space-y-3">
          <h4 className="font-medium text-theme-primary">Performance</h4>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-theme-muted">Avg Response Time:</span>
              <span className="text-theme-primary">
                {stats.avg_response_time ? `${stats.avg_response_time}ms` : 'N/A'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Tokens:</span>
              <span className="text-theme-primary">{stats.total_tokens?.toLocaleString()}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">Total Cost:</span>
              <span className="text-theme-primary">{formatCurrency(stats.total_cost || 0)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-muted">Duration:</span>
              <span className="text-theme-primary">
                {stats.duration_minutes ? `${Math.round(stats.duration_minutes)} minutes` : 'N/A'}
              </span>
            </div>
          </div>
        </div>
      </div>
    ) : (
      <p className="text-theme-muted">No detailed statistics available for this conversation.</p>
    );
  }

  if (section === 'details') {
    return (
      <div className="space-y-4">
        <div>
          <label className="text-sm font-medium text-theme-muted">Conversation ID</label>
          <p className="mt-1 text-theme-primary font-mono text-sm">{conversation.id}</p>
        </div>
        <div>
          <label className="text-sm font-medium text-theme-muted">AI Agent ID</label>
          <p className="mt-1 text-theme-primary font-mono text-sm">{conversation.ai_agent?.id || 'N/A'}</p>
        </div>
        <div>
          <label className="text-sm font-medium text-theme-muted">Created At</label>
          <p className="mt-1 text-theme-primary">{formatDate(conversation.created_at)}</p>
        </div>
        <div>
          <label className="text-sm font-medium text-theme-muted">Last Updated</label>
          <p className="mt-1 text-theme-primary">{formatDate(conversation.updated_at)}</p>
        </div>
        {conversation.metadata && Object.keys(conversation.metadata).length > 0 && (
          <div>
            <label className="text-sm font-medium text-theme-muted">Additional Metadata</label>
            <pre className="mt-1 text-xs bg-theme-surface p-3 rounded border text-theme-primary overflow-x-auto">
              {JSON.stringify(conversation.metadata, null, 2)}
            </pre>
          </div>
        )}
      </div>
    );
  }

  return null;
};
