import React, { useState } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { AgentLanesPanel } from './AgentLanesPanel';
import { TimelineView } from './TimelineView';
import { MergeStatusPanel } from './MergeStatusPanel';
import { ConfigurationPanel } from './ConfigurationPanel';
import { DependencyGraph } from './DependencyGraph';
import { SessionSummaryCards } from './SessionSummaryCards';
import { WorktreeStatusBadge } from './WorktreeStatusBadge';
import { Wifi, WifiOff } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { ParallelSessionDetail } from '../types';

interface SessionDetailViewProps {
  session: ParallelSessionDetail;
  isConnected: boolean;
  onRetryMerge: () => void;
}

export const SessionDetailView: React.FC<SessionDetailViewProps> = ({
  session,
  isConnected,
  onRetryMerge,
}) => {
  const [activeTab, setActiveTab] = useState('agents');
  const isActive = ['pending', 'provisioning', 'active', 'merging'].includes(session.status);

  return (
    <div className="space-y-4">
      {/* Status badges */}
      <div className="flex items-center gap-3">
        <WorktreeStatusBadge status={session.status} type="session" />
        {isActive && (
          <Badge variant={isConnected ? 'success' : 'warning'} size="sm">
            {isConnected ? (
              <><Wifi className="w-3 h-3 mr-1" />Live</>
            ) : (
              <><WifiOff className="w-3 h-3 mr-1" />Connecting...</>
            )}
          </Badge>
        )}
      </div>

      {/* Error message */}
      {session.error_message && (
        <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
          {session.error_message}
        </div>
      )}

      {/* Summary cards */}
      <SessionSummaryCards session={session} />

      {/* Progress bar */}
      <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${
            session.status === 'completed' ? 'bg-theme-status-success' :
            session.status === 'failed' ? 'bg-theme-status-error' :
            'bg-theme-status-info'
          }`}
          style={{ width: `${session.progress_percentage}%` }}
        />
      </div>

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="agents">Agents</TabsTrigger>
          <TabsTrigger value="timeline">Timeline</TabsTrigger>
          <TabsTrigger value="graph">Graph</TabsTrigger>
          <TabsTrigger value="merges">
            Merges
            {session.merge_operations.some((op) => op.has_conflicts) && (
              <span className="ml-1 w-2 h-2 rounded-full bg-theme-status-error inline-block" />
            )}
          </TabsTrigger>
          <TabsTrigger value="config">Configuration</TabsTrigger>
        </TabsList>

        <TabsContent value="agents" className="mt-4">
          <AgentLanesPanel worktrees={session.worktrees} />
        </TabsContent>

        <TabsContent value="timeline" className="mt-4">
          <TimelineView worktrees={session.worktrees} />
        </TabsContent>

        <TabsContent value="graph" className="mt-4">
          <DependencyGraph worktrees={session.worktrees} />
        </TabsContent>

        <TabsContent value="merges" className="mt-4">
          <MergeStatusPanel
            mergeOperations={session.merge_operations}
            onRetryMerge={onRetryMerge}
            sessionStatus={session.status}
          />
        </TabsContent>

        <TabsContent value="config" className="mt-4">
          <ConfigurationPanel session={session} />
        </TabsContent>
      </Tabs>
    </div>
  );
};
