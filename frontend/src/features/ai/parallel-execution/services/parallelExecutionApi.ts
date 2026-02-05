import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  ParallelSession,
  ParallelSessionDetail,
  ParallelSessionConfig,
  MergeOperation,
} from '../types';

class ParallelExecutionApiService extends BaseApiService {
  private resource = 'worktree_sessions';

  async getSessions(filters?: QueryFilters): Promise<PaginatedResponse<ParallelSession>> {
    return this.getList<ParallelSession>(this.resource, filters);
  }

  async getSession(id: string): Promise<ParallelSessionDetail> {
    return this.getOne<ParallelSessionDetail>(this.resource, id);
  }

  async createSession(config: ParallelSessionConfig): Promise<{ session: ParallelSession; message: string }> {
    return this.create<{ session: ParallelSession; message: string }>(this.resource, config);
  }

  async cancelSession(id: string, reason?: string): Promise<{ session: ParallelSession; message: string }> {
    return this.performAction<{ session: ParallelSession; message: string }>(
      this.resource,
      id,
      'cancel',
      { reason }
    );
  }

  async getSessionStatus(id: string): Promise<ParallelSessionDetail> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'status');
    return this.get<ParallelSessionDetail>(path);
  }

  async getMergeOperations(id: string): Promise<{ items: MergeOperation[] }> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'merge_operations');
    return this.get<{ items: MergeOperation[] }>(path);
  }

  async retryMerge(id: string): Promise<{ session: ParallelSession; message: string }> {
    return this.performAction<{ session: ParallelSession; message: string }>(
      this.resource,
      id,
      'retry_merge'
    );
  }

  async getConflicts(sessionId: string) {
    const path = this.buildPath(this.resource, sessionId, undefined, undefined, 'conflicts');
    return this.get(path);
  }

  async getFileLocks(sessionId: string) {
    const path = this.buildPath(this.resource, sessionId, undefined, undefined, 'file_locks');
    return this.get(path);
  }

  async acquireLocks(sessionId: string, data: { worktree_id: string; file_paths: string[]; lock_type?: string; ttl_seconds?: number }) {
    const path = this.buildPath(this.resource, sessionId, undefined, undefined, 'acquire_locks');
    return this.post(path, data);
  }

  async releaseLocks(sessionId: string, data: { worktree_id: string; file_paths?: string[] }) {
    const path = this.buildPath(this.resource, sessionId, undefined, undefined, 'release_locks');
    return this.post(path, data);
  }
}

export const parallelExecutionApi = new ParallelExecutionApiService();
