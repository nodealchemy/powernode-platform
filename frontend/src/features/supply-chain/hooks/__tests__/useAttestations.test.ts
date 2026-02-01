import { renderHook, waitFor, act } from '@testing-library/react';
import {
  useAttestations,
  useAttestation,
  useSignAttestation,
  useSigningKeys,
  useCreateAttestation,
} from '../useAttestations';
import { attestationsApi } from '../../services/attestationsApi';
import type {
  Attestation,
  AttestationDetail,
  Pagination,
  AttestationType,
  VerificationStatus,
} from '../../services/attestationsApi';

jest.mock('../../services/attestationsApi');
const mockApi = attestationsApi as jest.Mocked<typeof attestationsApi>;

// Test factories
function createMockAttestation(overrides?: Partial<Attestation>): Attestation {
  return {
    id: 'att_1',
    attestation_id: 'att_id_1',
    attestation_type: 'slsa_provenance' as AttestationType,
    slsa_level: 3,
    subject_name: 'package-v1.0',
    subject_digest: 'sha256:abc123',
    verification_status: 'verified' as VerificationStatus,
    signed: true,
    rekor_logged: true,
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    ...overrides,
  };
}

function createMockAttestationDetail(
  overrides?: Partial<AttestationDetail>
): AttestationDetail {
  return {
    ...createMockAttestation(),
    build_provenance: {
      builder_id: 'builder-001',
      build_type: 'docker',
      invocation: {
        configSource: {
          uri: 'github.com/org/repo',
          digest: { sha1: 'abc123' },
        },
      },
      materials: [
        {
          uri: 'github.com/org/repo/src/main.ts',
          digest: { sha256: 'def456' },
        },
      ],
    },
    signing_key: {
      id: 'key_1',
      name: 'Default Key',
      key_type: 'cosign',
      is_default: true,
    },
    verification_logs: [
      {
        verified_at: '2024-01-01T12:00:00Z',
        status: 'verified' as VerificationStatus,
        message: 'Successfully verified',
      },
    ],
    ...overrides,
  };
}

function createMockPagination(overrides?: Partial<Pagination>): Pagination {
  return {
    current_page: 1,
    per_page: 20,
    total_pages: 1,
    total_count: 1,
    ...overrides,
  };
}

function createMockSigningKey(
  overrides?: Partial<{
    id: string;
    name: string;
    key_type: 'rsa' | 'ecdsa' | 'ed25519';
    fingerprint: string;
    is_default: boolean;
    expires_at?: string;
    created_at: string;
  }>
) {
  return {
    id: 'key_1',
    name: 'Default Key',
    key_type: 'rsa' as const,
    fingerprint: 'sha256:abc123def456',
    is_default: true,
    created_at: '2024-01-01T00:00:00Z',
    ...overrides,
  };
}

describe('Attestation Hooks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('useAttestations', () => {
    it('should initialize with loading state', () => {
      mockApi.list.mockResolvedValue({
        attestations: [],
        pagination: createMockPagination(),
      });

      const { result } = renderHook(() => useAttestations());

      expect(result.current.loading).toBe(true);
      expect(result.current.attestations).toEqual([]);
      expect(result.current.pagination).toBeNull();
      expect(result.current.error).toBeNull();
    });

    it('should fetch attestations on mount', async () => {
      const mockAttestations = [
        createMockAttestation(),
        createMockAttestation({ id: 'att_2', subject_name: 'package-v2.0' }),
      ];
      const mockPagination = createMockPagination({ total_count: 2 });

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useAttestations());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestations).toEqual(mockAttestations);
      expect(result.current.pagination).toEqual(mockPagination);
      expect(result.current.error).toBeNull();
      expect(mockApi.list).toHaveBeenCalledWith({
        page: undefined,
        per_page: undefined,
        attestation_type: undefined,
        verification_status: undefined,
      });
    });

    it('should handle pagination options', async () => {
      const mockAttestations = [createMockAttestation()];
      const mockPagination = createMockPagination({
        current_page: 2,
        per_page: 10,
        total_pages: 5,
        total_count: 50,
      });

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() =>
        useAttestations({ page: 2, perPage: 10 })
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.list).toHaveBeenCalledWith({
        page: 2,
        per_page: 10,
        attestation_type: undefined,
        verification_status: undefined,
      });
      expect(result.current.pagination?.current_page).toBe(2);
      expect(result.current.pagination?.per_page).toBe(10);
    });

    it('should handle attestationType filter', async () => {
      const mockAttestations = [
        createMockAttestation({ attestation_type: 'sbom' }),
      ];
      const mockPagination = createMockPagination();

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() =>
        useAttestations({ attestationType: 'sbom' })
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.list).toHaveBeenCalledWith({
        page: undefined,
        per_page: undefined,
        attestation_type: 'sbom',
        verification_status: undefined,
      });
      expect(result.current.attestations[0].attestation_type).toBe('sbom');
    });

    it('should handle verificationStatus filter', async () => {
      const mockAttestations = [
        createMockAttestation({ verification_status: 'failed' }),
      ];
      const mockPagination = createMockPagination();

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() =>
        useAttestations({ verificationStatus: 'failed' })
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.list).toHaveBeenCalledWith({
        page: undefined,
        per_page: undefined,
        attestation_type: undefined,
        verification_status: 'failed',
      });
      expect(result.current.attestations[0].verification_status).toBe('failed');
    });

    it('should handle combined filters', async () => {
      const mockAttestations = [
        createMockAttestation({
          attestation_type: 'vulnerability_scan',
          verification_status: 'verified',
        }),
      ];
      const mockPagination = createMockPagination();

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() =>
        useAttestations({
          page: 1,
          perPage: 20,
          attestationType: 'vulnerability_scan',
          verificationStatus: 'verified',
        })
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.list).toHaveBeenCalledWith({
        page: 1,
        per_page: 20,
        attestation_type: 'vulnerability_scan',
        verification_status: 'verified',
      });
    });

    it('should handle errors when fetching attestations', async () => {
      const error = new Error('Failed to fetch attestations');
      mockApi.list.mockRejectedValue(error);

      const { result } = renderHook(() => useAttestations());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch attestations');
      expect(result.current.attestations).toEqual([]);
      expect(result.current.pagination).toBeNull();
    });

    it('should handle non-Error exceptions', async () => {
      mockApi.list.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useAttestations());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch attestations');
    });

    it('should provide refresh function to refetch', async () => {
      const mockAttestations = [createMockAttestation()];
      const mockPagination = createMockPagination();

      mockApi.list.mockResolvedValue({
        attestations: mockAttestations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useAttestations());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.list).toHaveBeenCalledTimes(1);

      // Call refresh
      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.list).toHaveBeenCalledTimes(2);
    });

    it('should handle empty attestations list', async () => {
      mockApi.list.mockResolvedValue({
        attestations: [],
        pagination: createMockPagination({ total_count: 0 }),
      });

      const { result } = renderHook(() => useAttestations());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestations).toEqual([]);
      expect(result.current.pagination?.total_count).toBe(0);
      expect(result.current.error).toBeNull();
    });
  });

  describe('useAttestation', () => {
    it('should not fetch when id is null', async () => {
      const { result } = renderHook(() => useAttestation(null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation).toBeNull();
      expect(result.current.error).toBeNull();
      expect(mockApi.get).not.toHaveBeenCalled();
    });

    it('should fetch attestation detail when id is provided', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation).toEqual(mockDetail);
      expect(result.current.error).toBeNull();
      expect(mockApi.get).toHaveBeenCalledWith('att_1');
    });

    it('should include build provenance in detail', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation?.build_provenance).toBeDefined();
      expect(result.current.attestation?.build_provenance?.builder_id).toBe(
        'builder-001'
      );
    });

    it('should include signing key in detail', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation?.signing_key).toBeDefined();
      expect(result.current.attestation?.signing_key?.name).toBe('Default Key');
    });

    it('should include verification logs in detail', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation?.verification_logs).toBeDefined();
      expect(result.current.attestation?.verification_logs).toHaveLength(1);
      expect(
        result.current.attestation?.verification_logs?.[0].status
      ).toBe('verified');
    });

    it('should handle attestation without optional fields', async () => {
      const mockDetail = createMockAttestationDetail({
        build_provenance: undefined,
        signing_key: undefined,
        verification_logs: undefined,
      });
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_2'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation?.build_provenance).toBeUndefined();
      expect(result.current.attestation?.signing_key).toBeUndefined();
      expect(result.current.attestation?.verification_logs).toBeUndefined();
    });

    it('should handle errors when fetching detail', async () => {
      const error = new Error('Attestation not found');
      mockApi.get.mockRejectedValue(error);

      const { result } = renderHook(() => useAttestation('invalid_id'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Attestation not found');
      expect(result.current.attestation).toBeNull();
    });

    it('should handle non-Error exceptions', async () => {
      mockApi.get.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch attestation');
    });

    it('should provide refresh function', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result } = renderHook(() => useAttestation('att_1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.get).toHaveBeenCalledTimes(1);

      // Call refresh
      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(mockApi.get).toHaveBeenLastCalledWith('att_1');
    });

    it('should refetch when id changes', async () => {
      const mockDetail1 = createMockAttestationDetail({ id: 'att_1' });
      const mockDetail2 = createMockAttestationDetail({
        id: 'att_2',
        subject_name: 'other-package',
      });

      mockApi.get.mockResolvedValueOnce(mockDetail1);
      mockApi.get.mockResolvedValueOnce(mockDetail2);

      const { result, rerender } = renderHook(
        ({ id }) => useAttestation(id),
        {
          initialProps: { id: 'att_1' },
        }
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.attestation?.id).toBe('att_1');

      rerender({ id: 'att_2' });

      await waitFor(() => {
        expect(result.current.attestation?.id).toBe('att_2');
      });

      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(mockApi.get).toHaveBeenNthCalledWith(1, 'att_1');
      expect(mockApi.get).toHaveBeenNthCalledWith(2, 'att_2');
    });

    it('should not refetch when id changes from value to null', async () => {
      const mockDetail = createMockAttestationDetail();
      mockApi.get.mockResolvedValue(mockDetail);

      const { result, rerender } = renderHook(
        ({ id }: { id: string | null }) => useAttestation(id),
        {
          initialProps: { id: 'att_1' as string | null },
        }
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.get).toHaveBeenCalledTimes(1);

      rerender({ id: null });

      expect(mockApi.get).toHaveBeenCalledTimes(1);
    });
  });

  describe('useSignAttestation', () => {
    it('should initialize with no loading state', () => {
      const { result } = renderHook(() => useSignAttestation());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
      expect(typeof result.current.mutateAsync).toBe('function');
    });

    it('should sign attestation with default key', async () => {
      const mockSigned = createMockAttestationDetail({
        signed: true,
        signing_key: { id: 'key_1', name: 'Default Key', key_type: 'rsa', is_default: true },
      });
      mockApi.sign.mockResolvedValue(mockSigned);

      const { result } = renderHook(() => useSignAttestation());

      let signResult: AttestationDetail | undefined;
      await act(async () => {
        signResult = await result.current.mutateAsync({
          id: 'att_1',
        });
      });

      expect(signResult).toEqual(mockSigned);
      expect(signResult?.signed).toBe(true);
      expect(mockApi.sign).toHaveBeenCalledWith('att_1', undefined);
    });

    it('should sign attestation with specific key', async () => {
      const mockSigned = createMockAttestationDetail({
        signed: true,
        signing_key: { id: 'key_custom', name: 'Custom Key', key_type: 'ecdsa', is_default: false },
      });
      mockApi.sign.mockResolvedValue(mockSigned);

      const { result } = renderHook(() => useSignAttestation());

      let signResult: AttestationDetail | undefined;
      await act(async () => {
        signResult = await result.current.mutateAsync({
          id: 'att_1',
          signingKeyId: 'key_custom',
        });
      });

      expect(signResult?.signing_key?.id).toBe('key_custom');
      expect(mockApi.sign).toHaveBeenCalledWith('att_1', 'key_custom');
    });

    it('should set loading state during sign operation', async () => {
      mockApi.sign.mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(
              () =>
                resolve(
                  createMockAttestationDetail({ signed: true })
                ),
              100
            )
          )
      );

      const { result } = renderHook(() => useSignAttestation());

      await act(async () => {
        await result.current.mutateAsync({ id: 'att_1' });
      });

      expect(result.current.isLoading).toBe(false);
    });

    it('should handle sign errors', async () => {
      const error = new Error('Signing key not found');
      mockApi.sign.mockRejectedValue(error);

      const { result } = renderHook(() => useSignAttestation());

      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: 'att_1',
            signingKeyId: 'invalid_key',
          });
        } catch {
          // Error is expected
        }
      });

      expect(result.current.error).toBe('Signing key not found');
      expect(result.current.isLoading).toBe(false);
    });

    it('should handle already signed attestation error', async () => {
      const error = new Error('Attestation is already signed');
      mockApi.sign.mockRejectedValue(error);

      const { result } = renderHook(() => useSignAttestation());

      await act(async () => {
        try {
          await result.current.mutateAsync({ id: 'att_already_signed' });
        } catch {
          // Error is expected
        }
      });

      expect(result.current.error).toBe('Attestation is already signed');
    });

    it('should throw error to caller', async () => {
      const error = new Error('Sign operation failed');
      mockApi.sign.mockRejectedValue(error);

      const { result } = renderHook(() => useSignAttestation());

      await expect(
        act(async () => {
          await result.current.mutateAsync({ id: 'att_1' });
        })
      ).rejects.toThrow('Sign operation failed');
    });

    it('should handle non-Error exceptions', async () => {
      mockApi.sign.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useSignAttestation());

      await act(async () => {
        try {
          await result.current.mutateAsync({ id: 'att_1' });
        } catch {
          // Error is expected
        }
      });

      expect(result.current.error).toBe('Failed to sign attestation');
    });

    it('should clear error on successful sign', async () => {
      const error = new Error('First attempt failed');
      const mockSigned = createMockAttestationDetail({ signed: true });

      const { result } = renderHook(() => useSignAttestation());

      // First failed attempt
      mockApi.sign.mockRejectedValueOnce(error);
      await act(async () => {
        try {
          await result.current.mutateAsync({ id: 'att_1' });
        } catch {
          // Expected
        }
      });
      expect(result.current.error).toBe('First attempt failed');

      // Second successful attempt
      mockApi.sign.mockResolvedValueOnce(mockSigned);
      await act(async () => {
        await result.current.mutateAsync({ id: 'att_1' });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('should handle multiple sign calls', async () => {
      const mockSigned1 = createMockAttestationDetail({
        id: 'att_1',
        signed: true,
      });
      const mockSigned2 = createMockAttestationDetail({
        id: 'att_2',
        signed: true,
      });

      mockApi.sign.mockResolvedValueOnce(mockSigned1);
      mockApi.sign.mockResolvedValueOnce(mockSigned2);

      const { result } = renderHook(() => useSignAttestation());

      let result1: AttestationDetail | undefined, result2: AttestationDetail | undefined;
      await act(async () => {
        result1 = await result.current.mutateAsync({ id: 'att_1' });
        result2 = await result.current.mutateAsync({ id: 'att_2' });
      });

      expect(result1?.id).toBe('att_1');
      expect(result2?.id).toBe('att_2');
      expect(mockApi.sign).toHaveBeenCalledTimes(2);
    });
  });

  describe('useSigningKeys', () => {
    it('should initialize with loading state', () => {
      mockApi.listSigningKeys.mockResolvedValue([]);

      const { result } = renderHook(() => useSigningKeys());

      expect(result.current.loading).toBe(true);
      expect(result.current.signingKeys).toEqual([]);
      expect(result.current.error).toBeNull();
    });

    it('should fetch signing keys on mount', async () => {
      const mockKeys = [
        createMockSigningKey({ is_default: true }),
        createMockSigningKey({
          id: 'key_2',
          name: 'Secondary Key',
          is_default: false,
        }),
      ];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.signingKeys).toEqual(mockKeys);
      expect(result.current.error).toBeNull();
      expect(mockApi.listSigningKeys).toHaveBeenCalledTimes(1);
    });

    it('should handle multiple signing keys with different types', async () => {
      const mockKeys = [
        createMockSigningKey({ key_type: 'rsa', is_default: true }),
        createMockSigningKey({
          id: 'key_ecdsa',
          key_type: 'ecdsa',
          is_default: false,
        }),
        createMockSigningKey({
          id: 'key_ed25519',
          key_type: 'ed25519',
          is_default: false,
        }),
      ];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.signingKeys).toHaveLength(3);
      expect(result.current.signingKeys.map((k) => k.key_type)).toEqual([
        'rsa',
        'ecdsa',
        'ed25519',
      ]);
    });

    it('should include expiration dates for keys', async () => {
      const mockKeys = [
        createMockSigningKey({
          is_default: true,
          expires_at: '2025-12-31T23:59:59Z',
        }),
      ];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.signingKeys[0].expires_at).toBe(
        '2025-12-31T23:59:59Z'
      );
    });

    it('should handle empty signing keys list', async () => {
      mockApi.listSigningKeys.mockResolvedValue([]);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.signingKeys).toEqual([]);
      expect(result.current.error).toBeNull();
    });

    it('should handle errors when fetching keys', async () => {
      const error = new Error('Failed to fetch signing keys');
      mockApi.listSigningKeys.mockRejectedValue(error);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch signing keys');
      expect(result.current.signingKeys).toEqual([]);
    });

    it('should handle non-Error exceptions', async () => {
      mockApi.listSigningKeys.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch signing keys');
    });

    it('should provide refresh function', async () => {
      const mockKeys = [createMockSigningKey()];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.listSigningKeys).toHaveBeenCalledTimes(1);

      // Call refresh
      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.listSigningKeys).toHaveBeenCalledTimes(2);
    });

    it('should identify default key', async () => {
      const mockKeys = [
        createMockSigningKey({ is_default: true }),
        createMockSigningKey({
          id: 'key_2',
          is_default: false,
        }),
      ];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      const defaultKey = result.current.signingKeys.find((k) => k.is_default);
      expect(defaultKey?.id).toBe('key_1');
    });

    it('should include fingerprints for verification', async () => {
      const mockKeys = [
        createMockSigningKey({ fingerprint: 'sha256:abc123def456' }),
      ];
      mockApi.listSigningKeys.mockResolvedValue(mockKeys);

      const { result } = renderHook(() => useSigningKeys());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.signingKeys[0].fingerprint).toBe(
        'sha256:abc123def456'
      );
    });
  });

  describe('useCreateAttestation', () => {
    it('should initialize with no loading state', () => {
      const { result } = renderHook(() => useCreateAttestation());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
      expect(typeof result.current.mutateAsync).toBe('function');
    });

    it('should create slsa_provenance attestation', async () => {
      const mockCreated = createMockAttestation({
        attestation_type: 'slsa_provenance',
      });
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const createData = {
        attestation_type: 'slsa_provenance' as AttestationType,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        predicate: {
          builder: { id: 'builder-001' },
        },
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(createResult).toEqual(mockCreated);
      expect(createResult?.attestation_type).toBe('slsa_provenance');
      expect(mockApi.create).toHaveBeenCalledWith(createData);
    });

    it('should create sbom attestation', async () => {
      const mockCreated = createMockAttestation({
        attestation_type: 'sbom',
        slsa_level: null,
      });
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const createData = {
        attestation_type: 'sbom' as AttestationType,
        subject_name: 'sbom-v1.0',
        subject_digest: 'sha256:sbom123',
        predicate: {
          specVersion: '1.3',
          components: [],
        },
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(createResult?.attestation_type).toBe('sbom');
      expect(mockApi.create).toHaveBeenCalledWith(createData);
    });

    it('should create vulnerability_scan attestation', async () => {
      const mockCreated = createMockAttestation({
        attestation_type: 'vulnerability_scan',
      });
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const createData = {
        attestation_type: 'vulnerability_scan' as AttestationType,
        subject_name: 'vuln-scan-v1.0',
        subject_digest: 'sha256:vuln123',
        predicate: {
          vulnerabilities: [],
        },
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(createResult?.attestation_type).toBe('vulnerability_scan');
    });

    it('should create custom attestation', async () => {
      const mockCreated = createMockAttestation({
        attestation_type: 'custom',
      });
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const createData = {
        attestation_type: 'custom' as AttestationType,
        subject_name: 'custom-att-v1.0',
        subject_digest: 'sha256:custom123',
        predicate: {
          customField: 'customValue',
        },
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(createResult?.attestation_type).toBe('custom');
    });

    it('should set loading state during create operation', async () => {
      mockApi.create.mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(
              () =>
                resolve(createMockAttestation()),
              100
            )
          )
      );

      const { result } = renderHook(() => useCreateAttestation());

      await act(async () => {
        await result.current.mutateAsync({
          attestation_type: 'slsa_provenance',
          subject_name: 'test',
          subject_digest: 'sha256:test',
          predicate: {},
        });
      });

      expect(result.current.isLoading).toBe(false);
    });

    it('should handle create errors', async () => {
      const error = new Error('Invalid attestation data');
      mockApi.create.mockRejectedValue(error);

      const { result } = renderHook(() => useCreateAttestation());

      await act(async () => {
        try {
          await result.current.mutateAsync({
            attestation_type: 'slsa_provenance',
            subject_name: '',
            subject_digest: '',
            predicate: {},
          });
        } catch {
          // Error is expected
        }
      });

      expect(result.current.error).toBe('Invalid attestation data');
      expect(result.current.isLoading).toBe(false);
    });

    it('should throw error to caller', async () => {
      const error = new Error('Create operation failed');
      mockApi.create.mockRejectedValue(error);

      const { result } = renderHook(() => useCreateAttestation());

      await expect(
        act(async () => {
          await result.current.mutateAsync({
            attestation_type: 'slsa_provenance',
            subject_name: 'test',
            subject_digest: 'sha256:test',
            predicate: {},
          });
        })
      ).rejects.toThrow('Create operation failed');
    });

    it('should handle non-Error exceptions', async () => {
      mockApi.create.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useCreateAttestation());

      await act(async () => {
        try {
          await result.current.mutateAsync({
            attestation_type: 'slsa_provenance',
            subject_name: 'test',
            subject_digest: 'sha256:test',
            predicate: {},
          });
        } catch {
          // Error is expected
        }
      });

      expect(result.current.error).toBe('Failed to create attestation');
    });

    it('should clear error on successful create', async () => {
      const error = new Error('First attempt failed');
      const mockCreated = createMockAttestation();

      const { result } = renderHook(() => useCreateAttestation());

      // First failed attempt
      mockApi.create.mockRejectedValueOnce(error);
      await act(async () => {
        try {
          await result.current.mutateAsync({
            attestation_type: 'slsa_provenance',
            subject_name: 'test',
            subject_digest: 'sha256:test',
            predicate: {},
          });
        } catch {
          // Expected
        }
      });
      expect(result.current.error).toBe('First attempt failed');

      // Second successful attempt
      mockApi.create.mockResolvedValueOnce(mockCreated);
      await act(async () => {
        await result.current.mutateAsync({
          attestation_type: 'slsa_provenance',
          subject_name: 'test',
          subject_digest: 'sha256:test',
          predicate: {},
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('should handle complex predicate objects', async () => {
      const mockCreated = createMockAttestation();
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const complexPredicate = {
        builder: {
          id: 'https://github.com/my-org/my-builder',
          version: '1.0',
        },
        metadata: {
          invocationId: 'https://github.com/my-org/my-repo/actions/runs/123',
          startedOn: '2024-01-01T00:00:00Z',
          finishedOn: '2024-01-01T01:00:00Z',
        },
        materials: [
          {
            uri: 'git+https://github.com/my-org/my-repo@main',
            digest: {
              sha1: 'abc123def456',
            },
          },
        ],
      };

      const createData = {
        attestation_type: 'slsa_provenance' as AttestationType,
        subject_name: 'complex-package',
        subject_digest: 'sha256:complex123',
        predicate: complexPredicate,
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(mockApi.create).toHaveBeenCalledWith(createData);
      expect(createResult).toEqual(mockCreated);
    });

    it('should handle multiple create calls', async () => {
      const mockCreated1 = createMockAttestation({
        id: 'att_1',
        subject_name: 'package-1',
      });
      const mockCreated2 = createMockAttestation({
        id: 'att_2',
        subject_name: 'package-2',
      });

      mockApi.create.mockResolvedValueOnce(mockCreated1);
      mockApi.create.mockResolvedValueOnce(mockCreated2);

      const { result } = renderHook(() => useCreateAttestation());

      let result1: Attestation | undefined, result2: Attestation | undefined;
      await act(async () => {
        result1 = await result.current.mutateAsync({
          attestation_type: 'slsa_provenance',
          subject_name: 'package-1',
          subject_digest: 'sha256:pkg1',
          predicate: {},
        });
        result2 = await result.current.mutateAsync({
          attestation_type: 'slsa_provenance',
          subject_name: 'package-2',
          subject_digest: 'sha256:pkg2',
          predicate: {},
        });
      });

      expect(result1?.subject_name).toBe('package-1');
      expect(result2?.subject_name).toBe('package-2');
      expect(mockApi.create).toHaveBeenCalledTimes(2);
    });

    it('should pass through all attestation data correctly', async () => {
      const mockCreated = createMockAttestation({
        id: 'att_new',
        attestation_id: 'att_id_new',
        slsa_level: 2,
        subject_name: 'my-package-v1.0',
        subject_digest: 'sha256:def456ghi789',
      });
      mockApi.create.mockResolvedValue(mockCreated);

      const { result } = renderHook(() => useCreateAttestation());

      const createData = {
        attestation_type: 'slsa_provenance' as AttestationType,
        subject_name: 'my-package-v1.0',
        subject_digest: 'sha256:def456ghi789',
        predicate: {
          builder: { id: 'builder-002' },
          metadata: { level: 2 },
        },
      };

      let createResult: Attestation | undefined;
      await act(async () => {
        createResult = await result.current.mutateAsync(createData);
      });

      expect(createResult?.id).toBe('att_new');
      expect(createResult?.slsa_level).toBe(2);
      expect(createResult?.subject_name).toBe('my-package-v1.0');
      expect(createResult?.subject_digest).toBe('sha256:def456ghi789');
    });
  });
});
