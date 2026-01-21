import { apiClient } from '@/shared/services/apiClient';

interface ApiResponse<T> {
  success: boolean;
  data: T;
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

type AttestationType = 'slsa_provenance' | 'sbom' | 'vulnerability_scan' | 'custom';
type VerificationStatus = 'unverified' | 'verified' | 'failed' | 'expired';

interface Attestation {
  id: string;
  attestation_id: string;
  attestation_type: AttestationType;
  slsa_level: 1 | 2 | 3 | null;
  subject_name: string;
  subject_digest: string;
  verification_status: VerificationStatus;
  signed: boolean;
  rekor_logged: boolean;
  created_at: string;
  updated_at: string;
}

interface AttestationDetail extends Attestation {
  build_provenance?: {
    builder_id: string;
    build_type: string;
    invocation: Record<string, unknown>;
    materials: Array<{ uri: string; digest: Record<string, string> }>;
  };
  signing_key?: {
    id: string;
    name: string;
    key_type: string;
    is_default: boolean;
  };
  verification_logs?: Array<{
    verified_at: string;
    status: VerificationStatus;
    message?: string;
  }>;
}

export const attestationsApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    attestation_type?: AttestationType;
    verification_status?: VerificationStatus;
  }): Promise<{ attestations: Attestation[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      attestations: Attestation[];
      pagination: Pagination;
    }>>('/supply_chain/attestations', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<AttestationDetail> => {
    const response = await apiClient.get<ApiResponse<{
      attestation: AttestationDetail;
    }>>(`/supply_chain/attestations/${id}`);
    return response.data.data.attestation;
  },

  create: async (data: {
    attestation_type: AttestationType;
    subject_name: string;
    subject_digest: string;
    predicate: Record<string, unknown>;
  }): Promise<Attestation> => {
    const response = await apiClient.post<ApiResponse<{
      attestation: Attestation;
    }>>('/supply_chain/attestations', { attestation: data });
    return response.data.data.attestation;
  },

  verify: async (id: string): Promise<AttestationDetail> => {
    const response = await apiClient.post<ApiResponse<{
      attestation: AttestationDetail;
    }>>(`/supply_chain/attestations/${id}/verify`);
    return response.data.data.attestation;
  },

  recordToRekor: async (id: string): Promise<AttestationDetail> => {
    const response = await apiClient.post<ApiResponse<{
      attestation: AttestationDetail;
    }>>(`/supply_chain/attestations/${id}/record_to_rekor`);
    return response.data.data.attestation;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/attestations/${id}`);
  },

  // Signing methods
  sign: async (id: string, signingKeyId?: string): Promise<AttestationDetail> => {
    const response = await apiClient.post<ApiResponse<{
      attestation: AttestationDetail;
    }>>(`/supply_chain/attestations/${id}/sign`, signingKeyId ? { signing_key_id: signingKeyId } : {});
    return response.data.data.attestation;
  },

  listSigningKeys: async (): Promise<SigningKey[]> => {
    const response = await apiClient.get<ApiResponse<{
      signing_keys: SigningKey[];
    }>>('/supply_chain/signing_keys');
    return response.data.data.signing_keys;
  },
};

interface SigningKey {
  id: string;
  name: string;
  key_type: 'rsa' | 'ecdsa' | 'ed25519';
  fingerprint: string;
  is_default: boolean;
  expires_at?: string;
  created_at: string;
}

interface CreateAttestationRequest {
  attestation_type: AttestationType;
  subject_name: string;
  subject_digest: string;
  predicate: Record<string, unknown>;
  slsa_level?: 1 | 2 | 3;
}

export type { Attestation, AttestationDetail, AttestationType, VerificationStatus, Pagination, SigningKey, CreateAttestationRequest };
