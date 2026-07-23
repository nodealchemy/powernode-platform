/**
 * Storage assignment types — matches
 *   extensions/system/server/app/controllers/api/v1/system/storage_assignments_controller.rb#serialize_assignment
 * Drift between this and the controller surfaces as undefined fields at runtime.
 *
 * Referencing the extension controller from core is a BLESSED seam
 * (IMP-ca6b51d65114) — see storageAssignmentsApi.ts for the ruling.
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

/**
 * Storage credential METADATA row — matches
 *   extensions/system/server/app/controllers/api/v1/system/storage_credentials_controller.rb#serialize
 * The backend NEVER serializes credential material; material lives in Vault
 * and is fetched only by the node agent at mount time. Rotation via the UI
 * returns the new credential's metadata row — never a secret.
 */
export interface StorageCredential {
  id: string;
  storage_assignment_id: string;
  node_instance_id: string | null;
  kind: string;
  status: string;
  expires_at: string | null;
  last_rotated_at: string | null;
  needs_rotation: boolean;
  metadata: Record<string, unknown>;
}

export interface StorageCredentialsListResponse {
  credentials: StorageCredential[];
  meta?: { total_count?: number; page?: number; per_page?: number };
}
