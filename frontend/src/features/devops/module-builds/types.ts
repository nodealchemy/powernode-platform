/**
 * Module Build Batch types — matches
 *   extensions/system/server/app/serializers/system/module_build_batch_serializer.rb
 *   extensions/system/server/app/controllers/api/v1/system/module_build_batches_controller.rb
 * Drift between this and the serializer surfaces as undefined fields at runtime.
 *
 * System::ModuleBuildBatch is extension-owned (extensions/system) — this is a
 * BLESSED CROSS-BOUNDARY SEAM (same ruling as StorageAssignment, see
 * features/system/storage/services/storageAssignmentsApi.ts): a core DevOps
 * page fronting a system-extension endpoint via URL + permission strings
 * only. It fails closed in a core-only assembly because system.module_builds.*
 * permissions are extension-registered and can never be granted without it.
 */

export type ModuleBuildBatchStatus =
  | 'planning'
  | 'dispatched'
  | 'awaiting_signature'
  | 'publishing'
  | 'complete'
  | 'partial'
  | 'failed'
  | 'cancelled';

export interface ModuleBuildPackageContext {
  repository_id: string | null;
  package_repo_kind: string | null;
  architecture: string | null;
  architectures: string[] | null;
  snapshot: string | null;
  tag: string | null;
}

/** List-shape row (index). */
export interface ModuleBuildBatch {
  id: string;
  status: ModuleBuildBatchStatus;
  trigger: string;
  shadow: boolean;
  base_sha: string | null;
  head_sha: string | null;
  module_slugs: string[];
  planned_count: number;
  succeeded_count: number;
  failed_count: number;
  active: boolean;
  finished: boolean;
  package_context: ModuleBuildPackageContext | null;
  created_at: string;
  updated_at: string;
}

export interface ModuleBuildTaskInfo {
  id: string;
  status: string;
  progress: number | null;
  started_at: string | null;
  completed_at: string | null;
  error_message: string | null;
}

export interface ModuleBuildLeaseInfo {
  id: string;
  status: string;
  node_instance_id: string | null;
  runner_name: string | null;
}

export interface ModuleBuildArtifactInfo {
  version_number: number;
  promotion_state: string;
  oci_ref: string | null;
  oci_digest: string | null;
  size_bytes: number | null;
  architecture: string | null;
  signed: boolean;
}

/** One row per module in a batch's detail breakdown. */
export interface ModuleBuildMember {
  module: string;
  architecture: string | null;
  tag: string | null;
  state: string;
  attempts: number;
  error: string | null;
  task: ModuleBuildTaskInfo | null;
  lease: ModuleBuildLeaseInfo | null;
  artifact: ModuleBuildArtifactInfo | null;
  // Shadow-batch parity diff — shape varies by comparison outcome, so it's
  // surfaced generically rather than typed field-by-field.
  parity: unknown;
}

/** Full-shape row (show / cancel). */
export interface ModuleBuildBatchDetail extends ModuleBuildBatch {
  dispatched_at: string | null;
  awaiting_signature_at: string | null;
  publishing_at: string | null;
  completed_at: string | null;
  failed_at: string | null;
  cancelled_at: string | null;
  error_message: string | null;
  modules: ModuleBuildMember[];
}

export interface ModuleBuildBatchListMeta {
  current_page: number;
  per_page: number;
  total_count: number;
  total_pages: number;
  next_page: number | null;
  prev_page: number | null;
}

export interface ModuleBuildBatchListResponse {
  module_build_batches: ModuleBuildBatch[];
  meta: ModuleBuildBatchListMeta;
}

export interface ModuleBuildBatchListParams {
  status?: string;
  trigger?: string;
  shadow?: boolean;
  page?: number;
}
