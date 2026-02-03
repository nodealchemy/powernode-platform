import { useState, useEffect, useCallback } from 'react';
import { attestationsApi, Attestation, AttestationDetail, AttestationType, VerificationStatus, Pagination } from '../services/attestationsApi';

export function useAttestations(options: {
  page?: number;
  perPage?: number;
  attestationType?: AttestationType;
  verificationStatus?: VerificationStatus;
} = {}) {
  const [attestations, setAttestations] = useState<Attestation[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAttestations = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await attestationsApi.list({
        page: options.page,
        per_page: options.perPage,
        attestation_type: options.attestationType,
        verification_status: options.verificationStatus,
      });
      setAttestations(result.attestations);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch attestations');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.attestationType, options.verificationStatus]);

  useEffect(() => {
    fetchAttestations();
  }, [fetchAttestations]);

  return { attestations, pagination, loading, error, refresh: fetchAttestations };
}

export function useAttestation(id: string | null) {
  const [attestation, setAttestation] = useState<AttestationDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchAttestation = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await attestationsApi.get(id);
      setAttestation(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch attestation');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchAttestation();
  }, [fetchAttestation]);

  return { attestation, loading, error, refresh: fetchAttestation };
}

// Sign attestation hook
export function useSignAttestation() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    id,
    signingKeyId,
  }: {
    id: string;
    signingKeyId?: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await attestationsApi.sign(id, signingKeyId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to sign attestation';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

// Signing keys hook
export function useSigningKeys() {
  const [signingKeys, setSigningKeys] = useState<Array<{
    id: string;
    name: string;
    key_type: 'rsa' | 'ecdsa' | 'ed25519';
    fingerprint: string;
    is_default: boolean;
    expires_at?: string;
    created_at: string;
  }>>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchSigningKeys = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await attestationsApi.listSigningKeys();
      setSigningKeys(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch signing keys');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSigningKeys();
  }, [fetchSigningKeys]);

  return { signingKeys, loading, error, refresh: fetchSigningKeys };
}

// Create attestation hook
export function useCreateAttestation() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (data: {
    attestation_type: AttestationType;
    subject_name: string;
    subject_digest: string;
    predicate: Record<string, unknown>;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await attestationsApi.create(data);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to create attestation';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}
