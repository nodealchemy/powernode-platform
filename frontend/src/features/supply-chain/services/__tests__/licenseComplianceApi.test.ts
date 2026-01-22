import { licenseComplianceApi } from '../licenseComplianceApi';
import { apiClient } from '@/shared/services/apiClient';
import { createMockAxiosResponse } from '@/test-utils/mockAxios';
import type {
  LicensePolicy,
  LicenseViolation,
  CreateLicensePolicyData,
  Pagination,
} from '../licenseComplianceApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

describe('licenseComplianceApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('listPolicies', () => {
    const mockPolicies: LicensePolicy[] = [
      {
        id: 'policy-1',
        name: 'Permissive Licenses',
        description: 'Allow permissive open source licenses',
        policy_type: 'allowlist',
        enforcement_level: 'warn',
        is_active: true,
        block_copyleft: false,
        block_strong_copyleft: false,
        allowed_licenses: ['MIT', 'Apache-2.0', 'BSD-2-Clause'],
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
      },
      {
        id: 'policy-2',
        name: 'Strict Copyleft',
        description: 'Block copyleft licenses',
        policy_type: 'denylist',
        enforcement_level: 'block',
        is_active: true,
        block_copyleft: true,
        block_strong_copyleft: true,
        denied_licenses: ['GPL-3.0', 'AGPL-3.0'],
        created_at: '2024-01-02T00:00:00Z',
        updated_at: '2024-01-02T00:00:00Z',
      },
    ];

    const mockPagination: Pagination = {
      current_page: 1,
      per_page: 20,
      total_pages: 1,
      total_count: 2,
    };

    it('returns policies and pagination on success', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            license_policies: mockPolicies,
            meta: mockPagination,
          },
        })
      );

      const result = await licenseComplianceApi.listPolicies();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_policies', {
        params: undefined,
      });
      expect(result.policies).toEqual(mockPolicies);
      expect(result.pagination).toEqual(mockPagination);
    });

    it('passes pagination parameters to the API', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            license_policies: [mockPolicies[0]],
            meta: { ...mockPagination, current_page: 2, total_pages: 5 },
          },
        })
      );

      const params = { page: 2, per_page: 10, is_active: true };
      await licenseComplianceApi.listPolicies(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_policies', {
        params,
      });
    });

    it('passes policy_type filter to the API', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            license_policies: [mockPolicies[0]],
            meta: mockPagination,
          },
        })
      );

      const params = { policy_type: 'allowlist' as const };
      await licenseComplianceApi.listPolicies(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_policies', {
        params,
      });
    });

    it('throws error on API failure', async () => {
      const error = new Error('Failed to fetch policies');
      mockApiClient.get.mockRejectedValue(error);

      await expect(licenseComplianceApi.listPolicies()).rejects.toThrow(
        'Failed to fetch policies'
      );
    });
  });

  describe('getPolicy', () => {
    const mockPolicy: LicensePolicy = {
      id: 'policy-1',
      name: 'Permissive Licenses',
      description: 'Allow permissive open source licenses',
      policy_type: 'allowlist',
      enforcement_level: 'warn',
      is_active: true,
      is_default: false,
      priority: 1,
      block_copyleft: false,
      block_strong_copyleft: false,
      require_osi_approved: true,
      allowed_licenses: ['MIT', 'Apache-2.0'],
      exception_packages: [],
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-01T00:00:00Z',
    };

    it('returns policy on success', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: mockPolicy },
        })
      );

      const result = await licenseComplianceApi.getPolicy('policy-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1');
      expect(result).toEqual(mockPolicy);
    });

    it('throws error when policy not found', async () => {
      mockApiClient.get.mockRejectedValue(new Error('Policy not found'));

      await expect(licenseComplianceApi.getPolicy('nonexistent')).rejects.toThrow(
        'Policy not found'
      );
    });
  });

  describe('createPolicy', () => {
    const policyData: CreateLicensePolicyData = {
      name: 'New Policy',
      description: 'Test policy',
      policy_type: 'allowlist',
      enforcement_level: 'warn',
      is_active: true,
      block_copyleft: false,
      block_strong_copyleft: false,
      allowed_licenses: ['MIT', 'Apache-2.0'],
    };

    const createdPolicy: LicensePolicy = {
      id: 'policy-new',
      ...policyData,
      created_at: '2024-01-15T00:00:00Z',
      updated_at: '2024-01-15T00:00:00Z',
    };

    it('creates policy and returns it on success', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: createdPolicy },
        })
      );

      const result = await licenseComplianceApi.createPolicy(policyData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/license_policies', {
        license_policy: policyData,
      });
      expect(result).toEqual(createdPolicy);
      expect(result.id).toBe('policy-new');
    });

    it('sends required fields in request', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: createdPolicy },
        })
      );

      const minimalData: CreateLicensePolicyData = {
        name: 'Minimal Policy',
        policy_type: 'hybrid',
        enforcement_level: 'log',
      };

      await licenseComplianceApi.createPolicy(minimalData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/license_policies', {
        license_policy: minimalData,
      });
    });

    it('throws error on validation failure', async () => {
      mockApiClient.post.mockRejectedValue(new Error('Invalid policy data'));

      const invalidData: CreateLicensePolicyData = {
        name: '',
        policy_type: 'allowlist',
        enforcement_level: 'warn',
      };

      await expect(licenseComplianceApi.createPolicy(invalidData)).rejects.toThrow(
        'Invalid policy data'
      );
    });
  });

  describe('updatePolicy', () => {
    const updateData: Partial<CreateLicensePolicyData> = {
      name: 'Updated Policy',
      enforcement_level: 'block',
    };

    const updatedPolicy: LicensePolicy = {
      id: 'policy-1',
      name: 'Updated Policy',
      policy_type: 'allowlist',
      enforcement_level: 'block',
      is_active: true,
      block_copyleft: false,
      block_strong_copyleft: false,
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-15T10:30:00Z',
    };

    it('updates policy and returns updated version', async () => {
      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: updatedPolicy },
        })
      );

      const result = await licenseComplianceApi.updatePolicy('policy-1', updateData);

      expect(mockApiClient.patch).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1', {
        license_policy: updateData,
      });
      expect(result.name).toBe('Updated Policy');
      expect(result.enforcement_level).toBe('block');
    });

    it('updates partial fields', async () => {
      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: updatedPolicy },
        })
      );

      const partialUpdate: Partial<CreateLicensePolicyData> = {
        is_active: false,
      };

      await licenseComplianceApi.updatePolicy('policy-1', partialUpdate);

      expect(mockApiClient.patch).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1', {
        license_policy: partialUpdate,
      });
    });

    it('throws error on update failure', async () => {
      mockApiClient.patch.mockRejectedValue(new Error('Policy not found'));

      await expect(licenseComplianceApi.updatePolicy('invalid', updateData)).rejects.toThrow(
        'Policy not found'
      );
    });
  });

  describe('deletePolicy', () => {
    it('deletes policy successfully', async () => {
      mockApiClient.delete.mockResolvedValue(createMockAxiosResponse({ success: true }));

      await licenseComplianceApi.deletePolicy('policy-1');

      expect(mockApiClient.delete).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1');
    });

    it('throws error on delete failure', async () => {
      mockApiClient.delete.mockRejectedValue(new Error('Cannot delete active policy'));

      await expect(licenseComplianceApi.deletePolicy('policy-1')).rejects.toThrow(
        'Cannot delete active policy'
      );
    });
  });

  describe('togglePolicyActive', () => {
    const activePolicy: LicensePolicy = {
      id: 'policy-1',
      name: 'Test Policy',
      policy_type: 'allowlist',
      enforcement_level: 'warn',
      is_active: true,
      block_copyleft: false,
      block_strong_copyleft: false,
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-01-15T10:30:00Z',
    };

    const inactivePolicy: LicensePolicy = {
      ...activePolicy,
      is_active: false,
    };

    it('activates policy when toggling to true', async () => {
      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: activePolicy },
        })
      );

      const result = await licenseComplianceApi.togglePolicyActive('policy-1', true);

      expect(mockApiClient.patch).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1', {
        license_policy: { is_active: true },
      });
      expect(result.is_active).toBe(true);
    });

    it('deactivates policy when toggling to false', async () => {
      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { license_policy: inactivePolicy },
        })
      );

      const result = await licenseComplianceApi.togglePolicyActive('policy-1', false);

      expect(mockApiClient.patch).toHaveBeenCalledWith('/supply_chain/license_policies/policy-1', {
        license_policy: { is_active: false },
      });
      expect(result.is_active).toBe(false);
    });

    it('throws error on toggle failure', async () => {
      mockApiClient.patch.mockRejectedValue(new Error('Policy is locked'));

      await expect(licenseComplianceApi.togglePolicyActive('policy-1', true)).rejects.toThrow(
        'Policy is locked'
      );
    });
  });

  describe('listViolations', () => {
    const mockViolations: LicenseViolation[] = [
      {
        id: 'violation-1',
        component_name: 'lodash',
        component_version: '4.17.21',
        license_name: 'GPL-3.0',
        license_spdx_id: 'GPL-3.0',
        violation_type: 'copyleft_contamination',
        severity: 'high',
        status: 'open',
        sbom_id: 'sbom-1',
        created_at: '2024-01-10T00:00:00Z',
      },
      {
        id: 'violation-2',
        component_name: 'react',
        component_version: '18.2.0',
        license_name: 'MIT',
        violation_type: 'unknown_license',
        severity: 'low',
        status: 'resolved',
        resolution_note: 'MIT license approved',
        resolved_at: '2024-01-12T00:00:00Z',
        created_at: '2024-01-11T00:00:00Z',
      },
    ];

    const mockPagination: Pagination = {
      current_page: 1,
      per_page: 20,
      total_pages: 1,
      total_count: 2,
    };

    it('returns violations and pagination on success', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            violations: mockViolations,
            pagination: mockPagination,
          },
        })
      );

      const result = await licenseComplianceApi.listViolations();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations', {
        params: undefined,
      });
      expect(result.violations).toEqual(mockViolations);
      expect(result.pagination).toEqual(mockPagination);
    });

    it('filters violations by status', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            violations: [mockViolations[0]],
            pagination: mockPagination,
          },
        })
      );

      const params = { status: 'open' as const };
      await licenseComplianceApi.listViolations(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations', {
        params,
      });
    });

    it('filters violations by severity', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            violations: [mockViolations[0]],
            pagination: mockPagination,
          },
        })
      );

      const params = { severity: 'high' as const };
      await licenseComplianceApi.listViolations(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations', {
        params,
      });
    });

    it('filters violations by type', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            violations: [mockViolations[0]],
            pagination: mockPagination,
          },
        })
      );

      const params = { violation_type: 'copyleft_contamination' as const };
      await licenseComplianceApi.listViolations(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations', {
        params,
      });
    });

    it('applies pagination parameters', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            violations: [],
            pagination: { ...mockPagination, current_page: 2 },
          },
        })
      );

      const params = { page: 2, per_page: 50 };
      await licenseComplianceApi.listViolations(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations', {
        params,
      });
    });

    it('throws error on API failure', async () => {
      mockApiClient.get.mockRejectedValue(new Error('Failed to fetch violations'));

      await expect(licenseComplianceApi.listViolations()).rejects.toThrow(
        'Failed to fetch violations'
      );
    });
  });

  describe('getViolation', () => {
    const mockViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      license_spdx_id: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'open',
      sbom_id: 'sbom-1',
      policy_id: 'policy-1',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('returns violation on success', async () => {
      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: mockViolation },
        })
      );

      const result = await licenseComplianceApi.getViolation('violation-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/license_violations/violation-1');
      expect(result).toEqual(mockViolation);
    });

    it('throws error when violation not found', async () => {
      mockApiClient.get.mockRejectedValue(new Error('Violation not found'));

      await expect(licenseComplianceApi.getViolation('nonexistent')).rejects.toThrow(
        'Violation not found'
      );
    });
  });

  describe('resolveViolation', () => {
    const resolvedViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'resolved',
      resolution_note: 'Dependency updated to MIT-licensed version',
      resolved_at: '2024-01-15T10:00:00Z',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('resolves violation with note', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: resolvedViolation },
        })
      );

      const result = await licenseComplianceApi.resolveViolation(
        'violation-1',
        'Dependency updated to MIT-licensed version'
      );

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/resolve',
        { resolution_note: 'Dependency updated to MIT-licensed version' }
      );
      expect(result.status).toBe('resolved');
      expect(result.resolution_note).toBe('Dependency updated to MIT-licensed version');
    });

    it('resolves violation without note', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: resolvedViolation },
        })
      );

      await licenseComplianceApi.resolveViolation('violation-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/resolve',
        { resolution_note: undefined }
      );
    });

    it('throws error on resolve failure', async () => {
      mockApiClient.post.mockRejectedValue(new Error('Cannot resolve approved exception'));

      await expect(
        licenseComplianceApi.resolveViolation('violation-1', 'test note')
      ).rejects.toThrow('Cannot resolve approved exception');
    });
  });

  describe('grantException', () => {
    const exceptionViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'exception_granted',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('grants exception with note', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: exceptionViolation },
        })
      );

      const result = await licenseComplianceApi.grantException(
        'violation-1',
        'Internal corporate dependency'
      );

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/grant_exception',
        { note: 'Internal corporate dependency' }
      );
      expect(result.status).toBe('exception_granted');
    });

    it('throws error when exception already granted', async () => {
      mockApiClient.post.mockRejectedValue(new Error('Exception already granted'));

      await expect(
        licenseComplianceApi.grantException('violation-1', 'note')
      ).rejects.toThrow('Exception already granted');
    });
  });

  describe('requestException', () => {
    const requestedViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'open',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('requests exception with justification', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: requestedViolation },
        })
      );

      const result = await licenseComplianceApi.requestException(
        'violation-1',
        'This is a critical business dependency'
      );

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/request_exception',
        {
          justification: 'This is a critical business dependency',
          expires_at: undefined,
        }
      );
      expect(result.id).toBe('violation-1');
    });

    it('requests exception with expiration date', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: requestedViolation },
        })
      );

      const expiresAt = '2024-06-15T00:00:00Z';
      await licenseComplianceApi.requestException('violation-1', 'justification', expiresAt);

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/request_exception',
        {
          justification: 'justification',
          expires_at: expiresAt,
        }
      );
    });

    it('throws error on request failure', async () => {
      mockApiClient.post.mockRejectedValue(new Error('Justification too short'));

      await expect(
        licenseComplianceApi.requestException('violation-1', '')
      ).rejects.toThrow('Justification too short');
    });
  });

  describe('approveException', () => {
    const approvedViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'exception_granted',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('approves exception with notes', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: approvedViolation },
        })
      );

      const result = await licenseComplianceApi.approveException(
        'violation-1',
        'Approved by compliance team'
      );

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/approve_exception',
        {
          notes: 'Approved by compliance team',
          expires_at: undefined,
        }
      );
      expect(result.status).toBe('exception_granted');
    });

    it('approves exception with expiration date', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: approvedViolation },
        })
      );

      const expiresAt = '2024-12-31T00:00:00Z';
      await licenseComplianceApi.approveException('violation-1', 'Approved', expiresAt);

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/approve_exception',
        {
          notes: 'Approved',
          expires_at: expiresAt,
        }
      );
    });

    it('approves exception without notes', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: approvedViolation },
        })
      );

      await licenseComplianceApi.approveException('violation-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/approve_exception',
        {
          notes: undefined,
          expires_at: undefined,
        }
      );
    });

    it('throws error when no pending exception request', async () => {
      mockApiClient.post.mockRejectedValue(new Error('No pending exception request'));

      await expect(licenseComplianceApi.approveException('violation-1')).rejects.toThrow(
        'No pending exception request'
      );
    });
  });

  describe('rejectException', () => {
    const rejectedViolation: LicenseViolation = {
      id: 'violation-1',
      component_name: 'lodash',
      component_version: '4.17.21',
      license_name: 'GPL-3.0',
      violation_type: 'copyleft_contamination',
      severity: 'high',
      status: 'open',
      created_at: '2024-01-10T00:00:00Z',
    };

    it('rejects exception with reason', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: rejectedViolation },
        })
      );

      const result = await licenseComplianceApi.rejectException(
        'violation-1',
        'GPL license not permitted in enterprise deployments'
      );

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/reject_exception',
        { reason: 'GPL license not permitted in enterprise deployments' }
      );
      expect(result.status).toBe('open');
    });

    it('rejects exception without reason', async () => {
      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: { violation: rejectedViolation },
        })
      );

      await licenseComplianceApi.rejectException('violation-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/license_violations/violation-1/reject_exception',
        { reason: undefined }
      );
    });

    it('throws error when exception cannot be rejected', async () => {
      mockApiClient.post.mockRejectedValue(new Error('Exception already approved'));

      await expect(licenseComplianceApi.rejectException('violation-1')).rejects.toThrow(
        'Exception already approved'
      );
    });
  });

  describe('error handling', () => {
    it('handles network errors', async () => {
      const networkError = new TypeError('Network request failed');
      mockApiClient.get.mockRejectedValue(networkError);

      await expect(licenseComplianceApi.listPolicies()).rejects.toThrow(
        'Network request failed'
      );
    });

    it('handles timeout errors', async () => {
      const timeoutError = new Error('Request timeout');
      mockApiClient.get.mockRejectedValue(timeoutError);

      await expect(licenseComplianceApi.listViolations()).rejects.toThrow('Request timeout');
    });

    it('handles API errors with response data', async () => {
      const apiError = {
        response: {
          status: 400,
          data: { error: 'Invalid request parameters' },
        },
      };
      mockApiClient.post.mockRejectedValue(apiError);

      const policyData: CreateLicensePolicyData = {
        name: 'Test',
        policy_type: 'allowlist',
        enforcement_level: 'warn',
      };

      await expect(licenseComplianceApi.createPolicy(policyData)).rejects.toEqual(apiError);
    });
  });
});
