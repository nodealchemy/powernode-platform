import { attestationsApi } from '../attestationsApi';
import { apiClient } from '@/shared/services/apiClient';
import { createMockAxiosResponse } from '@/test-utils/mockAxios';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

describe('attestationsApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('list', () => {
    it('returns list of attestations without params', async () => {
      const mockAttestations = [
        {
          id: 'att_1',
          attestation_id: 'att_id_1',
          attestation_type: 'slsa_provenance' as const,
          slsa_level: 3,
          subject_name: 'package-v1.0',
          subject_digest: 'sha256:abc123',
          verification_status: 'verified' as const,
          signed: true,
          rekor_logged: true,
          created_at: '2024-01-01T00:00:00Z',
          updated_at: '2024-01-01T00:00:00Z',
        },
      ];

      const mockResponse = {
        attestations: mockAttestations,
        pagination: {
          current_page: 1,
          per_page: 20,
          total_pages: 1,
          total_count: 1,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: mockResponse,
        })
      );

      const result = await attestationsApi.list();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations', {
        params: undefined,
      });
      expect(result.attestations).toEqual(mockAttestations);
      expect(result.pagination).toEqual(mockResponse.pagination);
    });

    it('returns list of attestations with pagination params', async () => {
      const mockAttestations = [
        {
          id: 'att_1',
          attestation_id: 'att_id_1',
          attestation_type: 'sbom' as const,
          slsa_level: null,
          subject_name: 'sbom-v1.0',
          subject_digest: 'sha256:def456',
          verification_status: 'unverified' as const,
          signed: false,
          rekor_logged: false,
          created_at: '2024-01-02T00:00:00Z',
          updated_at: '2024-01-02T00:00:00Z',
        },
      ];

      const mockResponse = {
        attestations: mockAttestations,
        pagination: {
          current_page: 2,
          per_page: 10,
          total_pages: 3,
          total_count: 25,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: mockResponse,
        })
      );

      const params = { page: 2, per_page: 10 };
      const result = await attestationsApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations', {
        params,
      });
      expect(result.pagination.current_page).toBe(2);
      expect(result.pagination.total_count).toBe(25);
    });

    it('returns list of attestations filtered by type', async () => {
      const mockAttestations = [
        {
          id: 'att_vuln_1',
          attestation_id: 'att_id_vuln_1',
          attestation_type: 'vulnerability_scan' as const,
          slsa_level: null,
          subject_name: 'vuln-scan-v1.0',
          subject_digest: 'sha256:ghi789',
          verification_status: 'verified' as const,
          signed: true,
          rekor_logged: true,
          created_at: '2024-01-03T00:00:00Z',
          updated_at: '2024-01-03T00:00:00Z',
        },
      ];

      const mockResponse = {
        attestations: mockAttestations,
        pagination: {
          current_page: 1,
          per_page: 20,
          total_pages: 1,
          total_count: 1,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: mockResponse,
        })
      );

      const params = { attestation_type: 'vulnerability_scan' as const };
      const result = await attestationsApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations', {
        params,
      });
      expect(result.attestations[0].attestation_type).toBe('vulnerability_scan');
    });

    it('returns list of attestations filtered by verification status', async () => {
      const mockAttestations = [
        {
          id: 'att_failed_1',
          attestation_id: 'att_id_failed_1',
          attestation_type: 'slsa_provenance' as const,
          slsa_level: 2,
          subject_name: 'failed-att-v1.0',
          subject_digest: 'sha256:jkl012',
          verification_status: 'failed' as const,
          signed: false,
          rekor_logged: false,
          created_at: '2024-01-04T00:00:00Z',
          updated_at: '2024-01-04T00:00:00Z',
        },
      ];

      const mockResponse = {
        attestations: mockAttestations,
        pagination: {
          current_page: 1,
          per_page: 20,
          total_pages: 1,
          total_count: 1,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: mockResponse,
        })
      );

      const params = { verification_status: 'failed' as const };
      const result = await attestationsApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations', {
        params,
      });
      expect(result.attestations[0].verification_status).toBe('failed');
    });

    it('throws error on list failure', async () => {
      const error = new Error('Failed to fetch attestations');
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.list()).rejects.toEqual(error);
      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations', {
        params: undefined,
      });
    });
  });

  describe('get', () => {
    it('returns attestation detail by id', async () => {
      const mockDetail = {
        id: 'att_1',
        attestation_id: 'att_id_1',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 3,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: true,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
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
          key_type: 'rsa',
          is_default: true,
        },
        verification_logs: [
          {
            verified_at: '2024-01-01T12:00:00Z',
            status: 'verified' as const,
            message: 'Successfully verified',
          },
        ],
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockDetail,
          },
        })
      );

      const result = await attestationsApi.get('att_1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations/att_1');
      expect(result).toEqual(mockDetail);
      expect(result.build_provenance).toBeDefined();
      expect(result.signing_key).toBeDefined();
      expect(result.verification_logs).toBeDefined();
    });

    it('returns attestation detail without optional fields', async () => {
      const mockDetail = {
        id: 'att_2',
        attestation_id: 'att_id_2',
        attestation_type: 'custom' as const,
        slsa_level: null,
        subject_name: 'custom-att-v1.0',
        subject_digest: 'sha256:mno345',
        verification_status: 'unverified' as const,
        signed: false,
        rekor_logged: false,
        created_at: '2024-01-05T00:00:00Z',
        updated_at: '2024-01-05T00:00:00Z',
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockDetail,
          },
        })
      );

      const result = await attestationsApi.get('att_2');

      expect(result).toEqual(mockDetail);
      expect(result.build_provenance).toBeUndefined();
      expect(result.signing_key).toBeUndefined();
    });

    it('throws error when attestation not found', async () => {
      const error = new Error('Attestation not found');
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.get('invalid_id')).rejects.toEqual(error);
      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/attestations/invalid_id');
    });

    it('handles network errors', async () => {
      const networkError = new TypeError('Network request failed');
      mockApiClient.get.mockRejectedValue(networkError);

      await expect(attestationsApi.get('att_1')).rejects.toThrow('Network request failed');
    });
  });

  describe('create', () => {
    it('creates new attestation with required fields', async () => {
      const createData = {
        attestation_type: 'slsa_provenance' as const,
        subject_name: 'new-package-v1.0',
        subject_digest: 'sha256:xyz789',
        predicate: {
          builder: { id: 'builder-001' },
          metadata: { invocationId: 'inv_123' },
        },
      };

      const mockCreated = {
        id: 'att_new',
        attestation_id: 'att_id_new',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 1,
        subject_name: 'new-package-v1.0',
        subject_digest: 'sha256:xyz789',
        verification_status: 'unverified' as const,
        signed: false,
        rekor_logged: false,
        created_at: '2024-01-06T00:00:00Z',
        updated_at: '2024-01-06T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockCreated,
          },
        })
      );

      const result = await attestationsApi.create(createData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations', {
        attestation: createData,
      });
      expect(result).toEqual(mockCreated);
      expect(result.id).toBe('att_new');
    });

    it('creates sbom attestation', async () => {
      const createData = {
        attestation_type: 'sbom' as const,
        subject_name: 'sbom-v1.0',
        subject_digest: 'sha256:sbom123',
        predicate: {
          specVersion: '1.3',
          dataLicense: 'CC0-1.0',
          components: [],
        },
      };

      const mockCreated = {
        id: 'att_sbom',
        attestation_id: 'att_id_sbom',
        attestation_type: 'sbom' as const,
        slsa_level: null,
        subject_name: 'sbom-v1.0',
        subject_digest: 'sha256:sbom123',
        verification_status: 'unverified' as const,
        signed: false,
        rekor_logged: false,
        created_at: '2024-01-07T00:00:00Z',
        updated_at: '2024-01-07T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockCreated,
          },
        })
      );

      const result = await attestationsApi.create(createData);

      expect(result.attestation_type).toBe('sbom');
    });

    it('throws error on create failure', async () => {
      const error = new Error('Invalid attestation data');
      mockApiClient.post.mockRejectedValue(error);

      const createData = {
        attestation_type: 'slsa_provenance' as const,
        subject_name: '',
        subject_digest: '',
        predicate: {},
      };

      await expect(attestationsApi.create(createData)).rejects.toEqual(error);
      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations', {
        attestation: createData,
      });
    });
  });

  describe('verify', () => {
    it('verifies attestation and returns updated detail', async () => {
      const mockVerified = {
        id: 'att_1',
        attestation_id: 'att_id_1',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 3,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: true,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-08T00:00:00Z',
        verification_logs: [
          {
            verified_at: '2024-01-08T10:30:00Z',
            status: 'verified' as const,
            message: 'Successfully verified against Rekor',
          },
        ],
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockVerified,
          },
        })
      );

      const result = await attestationsApi.verify('att_1');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations/att_1/verify');
      expect(result.verification_status).toBe('verified');
    });

    it('returns failed status when verification fails', async () => {
      const mockFailed = {
        id: 'att_2',
        attestation_id: 'att_id_2',
        attestation_type: 'sbom' as const,
        slsa_level: null,
        subject_name: 'sbom-v1.0',
        subject_digest: 'sha256:sbom456',
        verification_status: 'failed' as const,
        signed: false,
        rekor_logged: false,
        created_at: '2024-01-09T00:00:00Z',
        updated_at: '2024-01-09T00:00:00Z',
        verification_logs: [
          {
            verified_at: '2024-01-09T11:00:00Z',
            status: 'failed' as const,
            message: 'Attestation signature mismatch',
          },
        ],
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockFailed,
          },
        })
      );

      const result = await attestationsApi.verify('att_2');

      expect(result.verification_status).toBe('failed');
      expect(result.verification_logs?.[0].message).toContain('signature mismatch');
    });

    it('throws error on verify failure', async () => {
      const error = new Error('Attestation not found');
      mockApiClient.post.mockRejectedValue(error);

      await expect(attestationsApi.verify('invalid_id')).rejects.toEqual(error);
      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations/invalid_id/verify');
    });
  });

  describe('recordToRekor', () => {
    it('records attestation to Rekor log', async () => {
      const mockRecorded = {
        id: 'att_1',
        attestation_id: 'att_id_1',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 3,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: true,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-10T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockRecorded,
          },
        })
      );

      const result = await attestationsApi.recordToRekor('att_1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/attestations/att_1/record_to_rekor'
      );
      expect(result.rekor_logged).toBe(true);
    });

    it('sets rekor_logged to true in response', async () => {
      const mockRecorded = {
        id: 'att_2',
        attestation_id: 'att_id_2',
        attestation_type: 'sbom' as const,
        slsa_level: null,
        subject_name: 'sbom-v1.0',
        subject_digest: 'sha256:sbom123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: true,
        created_at: '2024-01-05T00:00:00Z',
        updated_at: '2024-01-10T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockRecorded,
          },
        })
      );

      const result = await attestationsApi.recordToRekor('att_2');

      expect(result.rekor_logged).toBe(true);
    });

    it('throws error on record failure', async () => {
      const error = new Error('Failed to record to Rekor');
      mockApiClient.post.mockRejectedValue(error);

      await expect(attestationsApi.recordToRekor('att_1')).rejects.toEqual(error);
      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/attestations/att_1/record_to_rekor'
      );
    });
  });

  describe('delete', () => {
    it('deletes attestation successfully', async () => {
      mockApiClient.delete.mockResolvedValue(createMockAxiosResponse({ success: true }));

      await attestationsApi.delete('att_1');

      expect(mockApiClient.delete).toHaveBeenCalledWith('/supply_chain/attestations/att_1');
    });

    it('handles delete for non-existent attestation', async () => {
      const error = new Error('Attestation not found');
      mockApiClient.delete.mockRejectedValue(error);

      await expect(attestationsApi.delete('invalid_id')).rejects.toEqual(error);
      expect(mockApiClient.delete).toHaveBeenCalledWith('/supply_chain/attestations/invalid_id');
    });

    it('throws error on delete failure', async () => {
      const error = new Error('Cannot delete signed attestation');
      mockApiClient.delete.mockRejectedValue(error);

      await expect(attestationsApi.delete('att_signed')).rejects.toEqual(error);
    });
  });

  describe('sign', () => {
    it('signs attestation with default key', async () => {
      const mockSigned = {
        id: 'att_1',
        attestation_id: 'att_id_1',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 3,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: false,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-11T00:00:00Z',
        signing_key: {
          id: 'key_default',
          name: 'Default Key',
          key_type: 'rsa',
          is_default: true,
        },
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockSigned,
          },
        })
      );

      const result = await attestationsApi.sign('att_1');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations/att_1/sign', {});
      expect(result.signed).toBe(true);
      expect(result.signing_key?.is_default).toBe(true);
    });

    it('signs attestation with specified key', async () => {
      const mockSigned = {
        id: 'att_1',
        attestation_id: 'att_id_1',
        attestation_type: 'slsa_provenance' as const,
        slsa_level: 3,
        subject_name: 'package-v1.0',
        subject_digest: 'sha256:abc123',
        verification_status: 'verified' as const,
        signed: true,
        rekor_logged: false,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-11T00:00:00Z',
        signing_key: {
          id: 'key_custom',
          name: 'Custom Signing Key',
          key_type: 'ecdsa',
          is_default: false,
        },
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            attestation: mockSigned,
          },
        })
      );

      const result = await attestationsApi.sign('att_1', 'key_custom');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations/att_1/sign', {
        signing_key_id: 'key_custom',
      });
      expect(result.signed).toBe(true);
      expect(result.signing_key?.id).toBe('key_custom');
    });

    it('throws error when signing fails', async () => {
      const error = new Error('Signing key not found');
      mockApiClient.post.mockRejectedValue(error);

      await expect(attestationsApi.sign('att_1', 'invalid_key')).rejects.toEqual(error);
      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/attestations/att_1/sign', {
        signing_key_id: 'invalid_key',
      });
    });

    it('handles already signed attestation', async () => {
      const error = new Error('Attestation is already signed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(attestationsApi.sign('att_already_signed')).rejects.toEqual(error);
    });
  });

  describe('listSigningKeys', () => {
    it('returns list of signing keys', async () => {
      const mockKeys = [
        {
          id: 'key_1',
          name: 'Default Key',
          key_type: 'rsa' as const,
          fingerprint: 'sha256:abc123def456',
          is_default: true,
          created_at: '2024-01-01T00:00:00Z',
        },
        {
          id: 'key_2',
          name: 'Secondary ECDSA Key',
          key_type: 'ecdsa' as const,
          fingerprint: 'sha256:ghi789jkl012',
          is_default: false,
          expires_at: '2025-01-01T00:00:00Z',
          created_at: '2024-01-02T00:00:00Z',
        },
        {
          id: 'key_3',
          name: 'Ed25519 Key',
          key_type: 'ed25519' as const,
          fingerprint: 'sha256:mno345pqr678',
          is_default: false,
          created_at: '2024-01-03T00:00:00Z',
        },
      ];

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            signing_keys: mockKeys,
          },
        })
      );

      const result = await attestationsApi.listSigningKeys();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/signing_keys');
      expect(result).toEqual(mockKeys);
      expect(result.length).toBe(3);
    });

    it('returns empty list when no keys exist', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            signing_keys: [],
          },
        })
      );

      const result = await attestationsApi.listSigningKeys();

      expect(result).toEqual([]);
      expect(result.length).toBe(0);
    });

    it('includes keys with expiration dates', async () => {
      const mockKeys = [
        {
          id: 'key_exp_1',
          name: 'Expiring Key',
          key_type: 'rsa' as const,
          fingerprint: 'sha256:exp123',
          is_default: false,
          expires_at: '2025-06-01T00:00:00Z',
          created_at: '2024-01-01T00:00:00Z',
        },
      ];

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            signing_keys: mockKeys,
          },
        })
      );

      const result = await attestationsApi.listSigningKeys();

      expect(result[0].expires_at).toBe('2025-06-01T00:00:00Z');
    });

    it('throws error on fetch failure', async () => {
      const error = new Error('Failed to fetch signing keys');
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.listSigningKeys()).rejects.toEqual(error);
      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/signing_keys');
    });

    it('handles different key types correctly', async () => {
      const mockKeys = [
        {
          id: 'key_rsa',
          name: 'RSA Key',
          key_type: 'rsa' as const,
          fingerprint: 'sha256:rsa123',
          is_default: false,
          created_at: '2024-01-01T00:00:00Z',
        },
        {
          id: 'key_ecdsa',
          name: 'ECDSA Key',
          key_type: 'ecdsa' as const,
          fingerprint: 'sha256:ecdsa123',
          is_default: false,
          created_at: '2024-01-02T00:00:00Z',
        },
        {
          id: 'key_ed25519',
          name: 'Ed25519 Key',
          key_type: 'ed25519' as const,
          fingerprint: 'sha256:ed25519_123',
          is_default: false,
          created_at: '2024-01-03T00:00:00Z',
        },
      ];

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            signing_keys: mockKeys,
          },
        })
      );

      const result = await attestationsApi.listSigningKeys();

      expect(result).toHaveLength(3);
      expect(result.map((k) => k.key_type)).toEqual(['rsa', 'ecdsa', 'ed25519']);
    });
  });

  describe('error handling across all methods', () => {
    it('handles 404 errors', async () => {
      const error = new Error('Not found');
      (error as any).response = { status: 404, data: { error: 'Not found' } };
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.get('missing_id')).rejects.toEqual(error);
    });

    it('handles 500 errors', async () => {
      const error = new Error('Internal server error');
      (error as any).response = { status: 500, data: { error: 'Internal server error' } };
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.list()).rejects.toEqual(error);
    });

    it('handles network timeout', async () => {
      const timeoutError = new Error('Request timeout');
      timeoutError.name = 'ECONNABORTED';
      mockApiClient.post.mockRejectedValue(timeoutError);

      await expect(attestationsApi.create({
        attestation_type: 'slsa_provenance',
        subject_name: 'test',
        subject_digest: 'sha256:test',
        predicate: {},
      })).rejects.toEqual(timeoutError);
    });

    it('handles malformed responses', async () => {
      const error = new TypeError('Cannot read property data of null');
      mockApiClient.get.mockRejectedValue(error);

      await expect(attestationsApi.listSigningKeys()).rejects.toEqual(error);
    });
  });
});
