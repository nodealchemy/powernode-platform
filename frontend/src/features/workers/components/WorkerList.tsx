import React from 'react';
import { Worker } from '@/features/workers/services/workerApi';

interface WorkerListProps {
  workers: Worker[];
  selectedWorker: Worker | null;
  onWorkerSelect: (worker: Worker) => void;
  onWorkerUpdate: (workerId: string, data: any) => Promise<any>;
  onWorkerDelete: (workerId: string) => Promise<void>;
  onTokenRegenerate: (workerId: string) => Promise<string>;
}

export const WorkerList: React.FC<WorkerListProps> = ({
WorkerList.displayName = 'WorkerList';
  workers,
  selectedWorker,
  onWorkerSelect,
  onWorkerUpdate,
  onWorkerDelete,
  onTokenRegenerate
}) => {
  return (
    <div className="space-y-4">
      <div className="text-center py-8">
        <h3 className="text-lg font-semibold text-theme-primary mb-2">Worker List</h3>
        <p className="text-theme-secondary">Total workers: {workers.length}</p>
        <p className="text-theme-secondary text-sm mt-2">This component will be implemented soon.</p>
      </div>
    </div>
  );
};

export default WorkerList;