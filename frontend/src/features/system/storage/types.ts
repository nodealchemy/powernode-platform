/**
 * Storage assignment types — matches
 *   extensions/system/server/app/controllers/api/v1/system/storage_assignments_controller.rb#serialize_assignment
 * Drift between this and the controller surfaces as undefined fields at runtime.
 */

export type StorageAssignmentStatus =
  | 'pending'
  | 'provisioning'
  | 'mounted'
  | 'degraded'
  | 'unmounting'
  | 'failed'
  | 'disabled';

export type EncryptionMode =
  | 'inherit'
  | 'none'
  | 'fscrypt'
  | 'luks'
  | 'client_side_aes';

export interface StorageAssignment {
  id: string;
  file_storage_id: string;
  node_instance_id: string;
  sdwan_network_id?: string | null;
  sdwan_virtual_ip_id?: string | null;
  mount_path: string;
  mount_options?: Record<string, unknown>;
  status: StorageAssignmentStatus;
  encryption_mode: EncryptionMode;
  effective_encryption_mode?: EncryptionMode;
  enabled: boolean;
  auto_mount: boolean;
  read_only: boolean;
  last_mounted_at?: string | null;
  last_status_at?: string | null;
  error_message?: string | null;
  active_credential_id?: string | null;
  created_at?: string;
}

export interface StorageAssignmentCreateInput {
  file_storage_id: string;
  node_instance_id: string;
  sdwan_network_id?: string;
  sdwan_virtual_ip_id?: string;
  mount_path: string;
  mount_options?: Record<string, unknown>;
  read_only?: boolean;
  enabled?: boolean;
  auto_mount?: boolean;
  encryption_mode?: EncryptionMode;
}

export interface StorageAssignmentsListResponse {
  assignments: StorageAssignment[];
  meta?: { total_count?: number; page?: number; per_page?: number };
}
