import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { workerApi, WorkerListResponse, WorkerStats } from '@/features/workers/services/workerApi';

export const WorkerManagement: React.FC = () => {
  const [workers, setWorkers] = useState<WorkerListResponse | null>(null);
  const [stats, setStats] = useState<WorkerStats | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const user = useSelector((state: any) => state.auth.user);

  useEffect(() => {
    loadWorkers();
    loadStats();
  }, []);

  const loadWorkers = async () => {
    try {
      const data = await workerApi.getWorkers();
      setWorkers(data);
    } catch {
      // Handle error silently
    }
  };

  const loadStats = async () => {
    try {
      const data = await workerApi.getStats();
      setStats(data);
    } catch {
      // Set default stats on error
      setStats({
        total_jobs: 0,
        completed_jobs: 0,
        failed_jobs: 0,
        success_rate: 0,
        avg_processing_time: 0,
        queue_depth: 0,
        queues: {},
        workers_active: 0,
        timestamp: new Date().toISOString()
      });
    }
  };

  // Removed unused handlers - functionality not implemented yet

  const hasPermission = (permission: string) => {
    return user?.permissions?.includes(permission);
  };

  return (
    <div>
      <h1>Worker Management</h1>
      
      {hasPermission('workers.create') && (
        <button onClick={() => setShowCreateModal(true)}>Create Worker</button>
      )}

      {/* Stats Display */}
      {stats && (
        <div>
          <div>{stats.total_jobs}</div>
          <div>{stats.completed_jobs}</div>
          <div>{stats.failed_jobs}</div>
          <div>{stats.success_rate}%</div>
          <div>{stats.avg_processing_time}s</div>
          <div>{stats.queue_depth}</div>
        </div>
      )}

      {/* Workers List */}
      {workers?.workers?.map((worker) => (
        <div key={worker.id}>
          <div>{worker.name}</div>
          <div>{worker.status === 'active' ? 'Active' : worker.status}</div>
          <div>{worker.request_count.toLocaleString()}</div>
          <div>{worker.last_seen_at || 'Never'}</div>
          <div>{worker.masked_token}</div>
          <button>Show</button>
          <button>Copy</button>
          {worker.status === 'suspended' && <button>Activate</button>}
          <button>View Jobs</button>
          {hasPermission('workers.delete') && <button>Delete</button>}
        </div>
      ))}

      {/* Create Modal */}
      {showCreateModal && (
        <div>
          <h2>Create New Worker</h2>
          <label htmlFor="worker-name">Worker Name</label>
          <input id="worker-name" />
          <label htmlFor="description">Description</label>
          <input id="description" />
          <button>Create</button>
        </div>
      )}
    </div>
  );
};

