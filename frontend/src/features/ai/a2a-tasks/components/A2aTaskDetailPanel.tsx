import React from 'react';
import { Activity } from 'lucide-react';
import { TaskDetail } from './TaskDetail';
import { TaskEventStream } from './TaskEventStream';

interface A2aTaskDetailPanelProps {
  taskId: string | null;
  taskStatus: string | null;
}

export const A2aTaskDetailPanel: React.FC<A2aTaskDetailPanelProps> = ({ taskId, taskStatus }) => {
  if (!taskId) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <Activity className="h-12 w-12 text-theme-muted mx-auto mb-3" />
          <p className="text-sm text-theme-muted">Select a task to view details</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6">
      <TaskDetail taskId={taskId} />
      <TaskEventStream taskId={taskId} autoConnect={taskStatus === 'active'} />
    </div>
  );
};

export default A2aTaskDetailPanel;
