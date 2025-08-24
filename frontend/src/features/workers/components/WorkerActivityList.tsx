import React from 'react';

interface WorkerActivityListProps {
  workerId: string;
}

export const WorkerActivityList: React.FC<WorkerActivityListProps> = ({ workerId }) => {
WorkerActivityList.displayName = 'WorkerActivityList';
  return (
    <div className="space-y-4">
      <div className="text-center py-8">
        <h3 className="text-lg font-semibold text-theme-primary mb-2">Worker Activities</h3>
        <p className="text-theme-secondary">Activity tracking for worker: {workerId}</p>
        <p className="text-theme-secondary text-sm mt-2">This feature will be implemented soon.</p>
      </div>
    </div>
  );
};

export default WorkerActivityList;