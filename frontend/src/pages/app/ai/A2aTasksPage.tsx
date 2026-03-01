import React, { useState, useEffect } from 'react';
import { ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { A2aTaskListPanel, A2aTaskDetailPanel } from '@/features/ai/a2a-tasks';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import type { A2aTask } from '@/shared/services/ai/types/a2a-types';

interface A2aTasksContentProps {
  refreshKey?: number;
}

export const A2aTasksContent: React.FC<A2aTasksContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [selectedTaskStatus, setSelectedTaskStatus] = useState<string | null>(null);
  const [listKey, setListKey] = useState(0);
  const [showDetail, setShowDetail] = useState(false);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      setListKey((k) => k + 1);
    }
  }, [externalRefreshKey]);

  usePermissions();

  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      if (
        [
          'agent_execution_started',
          'agent_execution_completed',
          'agent_execution_failed',
          'agent_message_sent',
          'agent_message_received',
        ].includes(event.type)
      ) {
        setListKey((k) => k + 1);
      }
    },
  });

  const handleSelectTask = (task: A2aTask) => {
    setSelectedTaskId(task.task_id);
    setSelectedTaskStatus(task.status);
    setShowDetail(true);
  };

  const handleBackToList = () => {
    setShowDetail(false);
  };

  return (
    <div className="flex h-[calc(100vh-280px)]">
      {/* List panel - hidden on mobile when viewing detail */}
      <div className={showDetail ? 'hidden lg:flex' : 'flex'}>
        <A2aTaskListPanel
          selectedTaskId={selectedTaskId}
          onSelectTask={handleSelectTask}
          refreshKey={listKey}
        />
      </div>

      {/* Detail panel */}
      <div className={showDetail ? 'flex flex-col flex-1 min-w-0' : 'hidden lg:flex lg:flex-col lg:flex-1 lg:min-w-0'}>
        {/* Mobile back button */}
        {showDetail && (
          <div className="lg:hidden px-4 py-2 border-b border-theme">
            <button
              onClick={handleBackToList}
              className="flex items-center gap-1 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to list
            </button>
          </div>
        )}
        <A2aTaskDetailPanel taskId={selectedTaskId} taskStatus={selectedTaskStatus} />
      </div>
    </div>
  );
};

export const A2aTasksPage: React.FC = () => {
  return (
    <PageContainer
      title="A2A Tasks"
      description="Monitor Agent-to-Agent communication tasks"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'A2A Tasks' },
      ]}
    >
      <A2aTasksContent />
    </PageContainer>
  );
};

export default A2aTasksPage;
