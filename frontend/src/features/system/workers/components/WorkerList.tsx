
import { Worker } from '@/features/system/workers/services/workerApi';

interface WorkerListProps {
  workers: Worker[];
  selectedWorker: Worker | null;
  onWorkerSelect: (worker: Worker) => void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onWorkerUpdate: (workerId: string, data: any) => Promise<any>;
  onWorkerDelete: (workerId: string) => Promise<void>;
  onTokenRegenerate: (workerId: string) => Promise<string>;
}

export const WorkerList: React.FC<WorkerListProps> = ({
  workers,
  selectedWorker: _selectedWorker,
  onWorkerSelect: _onWorkerSelect,
  onWorkerUpdate: _onWorkerUpdate,
  onWorkerDelete: _onWorkerDelete,
  onTokenRegenerate: _onTokenRegenerate
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

