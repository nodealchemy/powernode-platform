import React, { useState, useEffect, useCallback } from 'react';
import {
  Activity,
  CheckCircle,
  XCircle,
  AlertCircle,
  Bot,
  Workflow,
  MessageSquare,
  Zap,
  Eye,
  Filter
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { useAIOrchestrationMonitor, AISystemEvent } from '../services/aiOrchestrationMonitor';

interface ActivityItem {
  id: string;
  type: 'agent_executed' | 'workflow_completed' | 'workflow_failed' | 'provider_health_changed' | 'conversation_started' | 'conversation_ended';
  title: string;
  description: string;
  timestamp: string;
  status: 'success' | 'error' | 'warning' | 'info';
  metadata?: Record<string, unknown>;
  isNew?: boolean;
}

interface RealTimeActivityFeedProps {
  maxItems?: number;
  showFilters?: boolean;
  className?: string;
}

export const RealTimeActivityFeed: React.FC<RealTimeActivityFeedProps> = ({
  maxItems = 10,
  showFilters = true,
  className = ''
}) => {
  const [activities, setActivities] = useState<ActivityItem[]>([]);
  const [filteredActivities, setFilteredActivities] = useState<ActivityItem[]>([]);
  const [selectedTypes, setSelectedTypes] = useState<Set<string>>(new Set());
  const [isLive, setIsLive] = useState(true);
  const [newActivityCount, setNewActivityCount] = useState(0);

  const { subscribe, isConnected } = useAIOrchestrationMonitor();

  const activityTypes = [
    { id: 'agent_executed', label: 'Agent Executions', icon: Bot },
    { id: 'workflow_completed', label: 'Workflow Completed', icon: CheckCircle },
    { id: 'workflow_failed', label: 'Workflow Failed', icon: XCircle },
    { id: 'conversation_started', label: 'Conversations', icon: MessageSquare },
    { id: 'provider_health_changed', label: 'Provider Health', icon: AlertCircle }
  ];

  const addActivity = useCallback((event: AISystemEvent) => {
    const newActivity: ActivityItem = {
      id: `${event.type}-${event.timestamp}-${Math.random()}`,
      type: event.type,
      title: formatEventTitle(event),
      description: formatEventDescription(event),
      timestamp: event.timestamp,
      status: getEventStatus(event),
      metadata: event.data.metadata,
      isNew: true
    };

    setActivities(prev => {
      const updated = [newActivity, ...prev].slice(0, maxItems * 2); // Keep double for filtering
      return updated;
    });

    // Mark as new activity if feed is not currently visible/live
    if (!isLive) {
      setNewActivityCount(prev => prev + 1);
    }

    // Remove "new" flag after 5 seconds
    setTimeout(() => {
      setActivities(prev => 
        prev.map(activity => 
          activity.id === newActivity.id 
            ? { ...activity, isNew: false }
            : activity
        )
      );
    }, 5000);
  }, [maxItems, isLive]);

  useEffect(() => {
    const unsubscribe = subscribe(addActivity);
    return unsubscribe;
  }, [subscribe, addActivity]);

  // Filter activities based on selected types
  useEffect(() => {
    let filtered = activities;
    
    if (selectedTypes.size > 0) {
      filtered = activities.filter(activity => selectedTypes.has(activity.type));
    }
    
    setFilteredActivities(filtered.slice(0, maxItems));
  }, [activities, selectedTypes, maxItems]);

  const formatEventTitle = (event: AISystemEvent): string => {
    switch (event.type) {
      case 'agent_executed':
        return `Agent "${event.data.name || event.data.id}" executed`;
      case 'workflow_completed':
        return `Workflow "${event.data.name || event.data.id}" completed`;
      case 'workflow_failed':
        return `Workflow "${event.data.name || event.data.id}" failed`;
      case 'conversation_started':
        return 'New AI conversation started';
      case 'conversation_ended':
        return 'AI conversation ended';
      case 'provider_health_changed':
        return `Provider "${event.data.name || event.data.id}" health changed`;
      default:
        return 'AI system event';
    }
  };

  const formatEventDescription = (event: AISystemEvent): string => {
    switch (event.type) {
      case 'agent_executed':
        return event.data.message || `Agent execution ${event.data.status || 'completed'}`;
      case 'workflow_completed':
        return event.data.message || 'Workflow execution finished successfully';
      case 'workflow_failed':
        return event.data.message || 'Workflow execution encountered an error';
      case 'conversation_started':
        return event.data.message || 'User initiated new conversation';
      case 'conversation_ended':
        return event.data.message || 'Conversation session ended';
      case 'provider_health_changed':
        return event.data.message || `Status changed to ${event.data.status || 'unknown'}`;
      default:
        return event.data.message || 'System event occurred';
    }
  };

  const getEventStatus = (event: AISystemEvent): 'success' | 'error' | 'warning' | 'info' => {
    switch (event.type) {
      case 'workflow_failed':
        return 'error';
      case 'workflow_completed':
      case 'agent_executed':
        return 'success';
      case 'provider_health_changed':
        return event.data.status === 'healthy' ? 'success' : 'warning';
      default:
        return 'info';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'success': return <CheckCircle className="h-4 w-4 text-theme-success" />;
      case 'error': return <XCircle className="h-4 w-4 text-theme-danger" />;
      case 'warning': return <AlertCircle className="h-4 w-4 text-theme-warning" />;
      case 'info': return <Activity className="h-4 w-4 text-theme-info" />;
      default: return <Activity className="h-4 w-4 text-theme-muted" />;
    }
  };

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'agent_executed': return <Bot className="h-3 w-3" />;
      case 'workflow_completed':
      case 'workflow_failed': return <Workflow className="h-3 w-3" />;
      case 'conversation_started':
      case 'conversation_ended': return <MessageSquare className="h-3 w-3" />;
      case 'provider_health_changed': return <Zap className="h-3 w-3" />;
      default: return <Activity className="h-3 w-3" />;
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMinutes = Math.floor(diffMs / (1000 * 60));

    if (diffMinutes < 1) return 'Just now';
    if (diffMinutes < 60) return `${diffMinutes}m ago`;
    if (diffMinutes < 1440) return `${Math.floor(diffMinutes / 60)}h ago`;
    return date.toLocaleDateString();
  };

  const toggleTypeFilter = (type: string) => {
    setSelectedTypes(prev => {
      const newSet = new Set(prev);
      if (newSet.has(type)) {
        newSet.delete(type);
      } else {
        newSet.add(type);
      }
      return newSet;
    });
  };

  const clearFilters = () => {
    setSelectedTypes(new Set());
  };

  const toggleLiveMode = () => {
    setIsLive(prev => !prev);
    if (!isLive) {
      setNewActivityCount(0);
    }
  };

  return (
    <div className={`space-y-4 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h3 className="text-lg font-semibold text-theme-primary">Activity Feed</h3>
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isConnected() ? 'bg-theme-success-solid' : 'bg-theme-danger-solid'}`} />
            <span className="text-xs text-theme-secondary">
              {isConnected() ? 'Live' : 'Disconnected'}
            </span>
          </div>
          {newActivityCount > 0 && (
            <Badge variant="info" size="sm">
              {newActivityCount} new
            </Badge>
          )}
        </div>
        
        <div className="flex items-center gap-2">
          <button
            onClick={toggleLiveMode}
            className={`btn-theme btn-theme-sm ${isLive ? 'btn-theme-primary' : 'btn-theme-outline'}`}
          >
            <Eye className="h-3 w-3 mr-1" />
            {isLive ? 'Live' : 'Paused'}
          </button>
        </div>
      </div>

      {/* Filters */}
      {showFilters && (
        <div className="flex flex-wrap items-center gap-2">
          <Filter className="h-4 w-4 text-theme-secondary" />
          <span className="text-sm text-theme-secondary">Filter:</span>
          {activityTypes.map(type => {
            const Icon = type.icon;
            const isSelected = selectedTypes.has(type.id);
            return (
              <button
                key={type.id}
                onClick={() => toggleTypeFilter(type.id)}
                className={`flex items-center gap-1 px-2 py-1 rounded text-xs transition-colors ${
                  isSelected 
                    ? 'bg-theme-primary text-white' 
                    : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface/80'
                }`}
              >
                <Icon className="h-3 w-3" />
                {type.label}
              </button>
            );
          })}
          {selectedTypes.size > 0 && (
            <button
              onClick={clearFilters}
              className="text-xs text-theme-secondary hover:text-theme-primary underline"
            >
              Clear all
            </button>
          )}
        </div>
      )}

      {/* Activity List */}
      <div className="space-y-2 max-h-96 overflow-y-auto">
        {filteredActivities.length === 0 ? (
          <div className="text-center py-8 text-theme-secondary">
            <Activity className="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p>No recent activity</p>
            {selectedTypes.size > 0 && (
              <button
                onClick={clearFilters}
                className="text-sm text-theme-primary hover:underline mt-2"
              >
                Clear filters to see all activity
              </button>
            )}
          </div>
        ) : (
          filteredActivities.map((activity) => (
            <div
              key={activity.id}
              className={`flex items-start space-x-3 p-3 rounded-lg transition-all ${
                activity.isNew 
                  ? 'bg-theme-primary/5 border border-theme-primary/20' 
                  : 'hover:bg-theme-surface/50'
              }`}
            >
              <div className="flex-shrink-0 mt-0.5">
                {getStatusIcon(activity.status)}
              </div>
              
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  {getTypeIcon(activity.type)}
                  <div className="text-sm font-medium text-theme-primary truncate">
                    {activity.title}
                  </div>
                  {activity.isNew && (
                    <Badge variant="info" size="sm">New</Badge>
                  )}
                </div>
                <div className="text-sm text-theme-secondary">
                  {activity.description}
                </div>
              </div>
              
              <div className="flex-shrink-0 text-xs text-theme-muted">
                {formatTimestamp(activity.timestamp)}
              </div>
            </div>
          ))
        )}
      </div>

    </div>
  );
};