import { sbomsApi } from '../sbomsApi';
import { apiClient } from '@/shared/services/apiClient';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

describe('sbomsApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('list', () => {
    it('returns sboms and pagination on success', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            sboms: [
              {
                id: '123',
                sbom_id: 'sbom-123',
                name: 'Test SBOM',
                format: 'cyclonedx_1_5' as const,
                version: '1.0.0',
                status: 'completed' as const,
                component_count: 50,
                vulnerability_count: 5,
                risk_score: 7.5,
                ntia_minimum_compliant: true,
                created_at: '2024-01-01T00:00:00Z',
                updated_at: '2024-01-01T00:00:00Z',
              },
            ],
            pagination: {
              current_page: 1,
              per_page: 20,
              total_pages: 1,
              total_count: 1,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.list({ page: 1, per_page: 20 });

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms', {
        params: { page: 1, per_page: 20 },
      });
      expect(result).toEqual(mockResponse.data.data);
      expect(result.sboms).toHaveLength(1);
      expect(result.sboms[0].name).toBe('Test SBOM');
    });

    it('calls API with filter parameters', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            sboms: [],
            pagination: {
              current_page: 1,
              per_page: 20,
              total_pages: 0,
              total_count: 0,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      await sbomsApi.list({
        page: 2,
        per_page: 10,
        status: 'completed',
        format: 'spdx_2_3',
        search: 'test',
      });

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms', {
        params: {
          page: 2,
          per_page: 10,
          status: 'completed',
          format: 'spdx_2_3',
          search: 'test',
        },
      });
    });

    it('handles API errors', async () => {
      const error = new Error('Network error');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.list()).rejects.toThrow('Network error');
    });
  });

  describe('get', () => {
    it('returns sbom detail on success', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            sbom: {
              id: '123',
              sbom_id: 'sbom-123',
              name: 'Test SBOM',
              format: 'cyclonedx_1_5' as const,
              version: '1.0.0',
              status: 'completed' as const,
              component_count: 50,
              vulnerability_count: 5,
              risk_score: 7.5,
              ntia_minimum_compliant: true,
              created_at: '2024-01-01T00:00:00Z',
              updated_at: '2024-01-01T00:00:00Z',
              components: [],
              vulnerabilities: [],
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.get('123');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123');
      expect(result).toEqual(mockResponse.data.data.sbom);
      expect(result.id).toBe('123');
    });

    it('handles 404 errors', async () => {
      const error = new Error('Not found');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.get('nonexistent')).rejects.toThrow('Not found');
    });
  });

  describe('create', () => {
    it('creates sbom successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            sbom: {
              id: '123',
              sbom_id: 'sbom-123',
              name: 'New SBOM',
              format: 'cyclonedx_1_5' as const,
              version: '1.0.0',
              status: 'draft' as const,
              component_count: 0,
              vulnerability_count: 0,
              risk_score: 0,
              ntia_minimum_compliant: false,
              created_at: '2024-01-01T00:00:00Z',
              updated_at: '2024-01-01T00:00:00Z',
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const createData = {
        name: 'New SBOM',
        format: 'cyclonedx_1_5' as const,
        repository_id: 'repo-123',
      };

      const result = await sbomsApi.create(createData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/sboms', {
        sbom: createData,
      });
      expect(result).toEqual(mockResponse.data.data.sbom);
      expect(result.name).toBe('New SBOM');
    });

    it('handles validation errors', async () => {
      const error = new Error('Validation failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(
        sbomsApi.create({
          name: '',
          format: 'cyclonedx_1_5',
        })
      ).rejects.toThrow('Validation failed');
    });
  });

  describe('delete', () => {
    it('deletes sbom successfully', async () => {
      mockApiClient.delete.mockResolvedValue({ data: { success: true } });

      await sbomsApi.delete('123');

      expect(mockApiClient.delete).toHaveBeenCalledWith('/supply_chain/sboms/123');
    });

    it('handles delete errors', async () => {
      const error = new Error('Delete failed');
      mockApiClient.delete.mockRejectedValue(error);

      await expect(sbomsApi.delete('123')).rejects.toThrow('Delete failed');
    });
  });

  describe('getComponents', () => {
    it('returns components and pagination', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            components: [
              {
                id: 'comp-1',
                purl: 'pkg:npm/react@18.0.0',
                name: 'react',
                version: '18.0.0',
                ecosystem: 'npm',
                dependency_type: 'direct' as const,
                depth: 0,
                risk_score: 2.5,
                has_known_vulnerabilities: false,
              },
            ],
            pagination: {
              current_page: 1,
              per_page: 20,
              total_pages: 1,
              total_count: 1,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getComponents('123', { page: 1, per_page: 20 });

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/components', {
        params: { page: 1, per_page: 20 },
      });
      expect(result).toEqual(mockResponse.data.data);
      expect(result.components).toHaveLength(1);
    });

    it('calls API with filter parameters', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            components: [],
            pagination: {
              current_page: 1,
              per_page: 20,
              total_pages: 0,
              total_count: 0,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      await sbomsApi.getComponents('123', {
        ecosystem: 'npm',
        dependency_type: 'direct',
      });

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/components', {
        params: {
          ecosystem: 'npm',
          dependency_type: 'direct',
        },
      });
    });

    it('handles API errors', async () => {
      const error = new Error('Failed to fetch components');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getComponents('123')).rejects.toThrow('Failed to fetch components');
    });
  });

  describe('getVulnerabilities', () => {
    it('returns vulnerabilities and pagination', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerabilities: [
              {
                id: 'vuln-1',
                vulnerability_id: 'CVE-2024-0001',
                severity: 'high' as const,
                cvss_score: 8.5,
                cvss_vector: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
                remediation_status: 'open' as const,
                fixed_version: '2.0.0',
                component: { name: 'lodash', version: '4.17.19' },
              },
            ],
            pagination: {
              current_page: 1,
              per_page: 20,
              total_pages: 1,
              total_count: 1,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getVulnerabilities('123', {
        severity: 'high',
        status: 'open',
      });

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/vulnerabilities', {
        params: {
          severity: 'high',
          status: 'open',
        },
      });
      expect(result).toEqual(mockResponse.data.data);
      expect(result.vulnerabilities).toHaveLength(1);
    });

    it('handles API errors', async () => {
      const error = new Error('Failed to fetch vulnerabilities');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getVulnerabilities('123')).rejects.toThrow('Failed to fetch vulnerabilities');
    });
  });

  describe('export', () => {
    it('exports sbom in JSON format', async () => {
      const mockBlob = new Blob(['{"sbom": "data"}'], { type: 'application/json' });
      mockApiClient.post.mockResolvedValue({ data: mockBlob });

      const result = await sbomsApi.export('123', 'json');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/export',
        { format: 'json' },
        { responseType: 'blob' }
      );
      expect(result).toBe(mockBlob);
    });

    it('exports sbom in XML format', async () => {
      const mockBlob = new Blob(['<sbom></sbom>'], { type: 'application/xml' });
      mockApiClient.post.mockResolvedValue({ data: mockBlob });

      const result = await sbomsApi.export('123', 'xml');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/export',
        { format: 'xml' },
        { responseType: 'blob' }
      );
      expect(result).toBe(mockBlob);
    });

    it('handles export errors', async () => {
      const error = new Error('Export failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.export('123', 'json')).rejects.toThrow('Export failed');
    });
  });

  describe('rescan', () => {
    it('rescans sbom successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            sbom: {
              id: '123',
              sbom_id: 'sbom-123',
              name: 'Test SBOM',
              format: 'cyclonedx_1_5' as const,
              version: '1.0.0',
              status: 'generating' as const,
              component_count: 50,
              vulnerability_count: 5,
              risk_score: 7.5,
              ntia_minimum_compliant: true,
              created_at: '2024-01-01T00:00:00Z',
              updated_at: '2024-01-01T00:00:00Z',
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.rescan('123');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/sboms/123/rescan');
      expect(result).toEqual(mockResponse.data.data.sbom);
      expect(result.status).toBe('generating');
    });

    it('handles rescan errors', async () => {
      const error = new Error('Rescan failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.rescan('123')).rejects.toThrow('Rescan failed');
    });
  });

  describe('getVulnerability', () => {
    it('returns vulnerability detail', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerability: {
              id: 'vuln-1',
              vulnerability_id: 'CVE-2024-0001',
              severity: 'critical' as const,
              cvss_score: 9.8,
              cvss_vector: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
              remediation_status: 'open' as const,
              fixed_version: '2.0.0',
              component: { name: 'lodash', version: '4.17.19' },
              description: 'Critical vulnerability',
              references: ['https://nvd.nist.gov/vuln/detail/CVE-2024-0001'],
              published_at: '2024-01-01T00:00:00Z',
              cwe_ids: ['CWE-79'],
              epss_score: 0.95,
              exploit_available: true,
              suppressed: false,
              false_positive: false,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getVulnerability('123', 'vuln-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/vulnerabilities/vuln-1');
      expect(result).toEqual(mockResponse.data.data.vulnerability);
      expect(result.vulnerability_id).toBe('CVE-2024-0001');
    });

    it('handles errors', async () => {
      const error = new Error('Not found');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getVulnerability('123', 'invalid')).rejects.toThrow('Not found');
    });
  });

  describe('updateVulnerabilityStatus', () => {
    it('updates vulnerability status successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerability: {
              id: 'vuln-1',
              vulnerability_id: 'CVE-2024-0001',
              severity: 'high' as const,
              cvss_score: 8.5,
              remediation_status: 'in_progress' as const,
              component: { name: 'lodash', version: '4.17.19' },
            },
          },
        },
      };

      mockApiClient.patch.mockResolvedValue(mockResponse);

      const result = await sbomsApi.updateVulnerabilityStatus('123', 'vuln-1', 'in_progress');

      expect(mockApiClient.patch).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/vulnerabilities/vuln-1',
        { vulnerability: { remediation_status: 'in_progress' } }
      );
      expect(result).toEqual(mockResponse.data.data.vulnerability);
      expect(result.remediation_status).toBe('in_progress');
    });

    it('handles update errors', async () => {
      const error = new Error('Update failed');
      mockApiClient.patch.mockRejectedValue(error);

      await expect(
        sbomsApi.updateVulnerabilityStatus('123', 'vuln-1', 'fixed')
      ).rejects.toThrow('Update failed');
    });
  });

  describe('suppressVulnerability', () => {
    it('suppresses vulnerability successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerability: {
              id: 'vuln-1',
              vulnerability_id: 'CVE-2024-0001',
              severity: 'high' as const,
              cvss_score: 8.5,
              remediation_status: 'wont_fix' as const,
              component: { name: 'lodash', version: '4.17.19' },
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.suppressVulnerability('123', 'vuln-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/vulnerabilities/vuln-1/suppress'
      );
      expect(result).toEqual(mockResponse.data.data.vulnerability);
    });

    it('handles suppress errors', async () => {
      const error = new Error('Suppress failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.suppressVulnerability('123', 'vuln-1')).rejects.toThrow('Suppress failed');
    });
  });

  describe('unsuppressVulnerability', () => {
    it('unsuppresses vulnerability successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerability: {
              id: 'vuln-1',
              vulnerability_id: 'CVE-2024-0001',
              severity: 'high' as const,
              cvss_score: 8.5,
              remediation_status: 'open' as const,
              component: { name: 'lodash', version: '4.17.19' },
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.unsuppressVulnerability('123', 'vuln-1');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/vulnerabilities/vuln-1/unsuppress'
      );
      expect(result).toEqual(mockResponse.data.data.vulnerability);
    });

    it('handles unsuppress errors', async () => {
      const error = new Error('Unsuppress failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.unsuppressVulnerability('123', 'vuln-1')).rejects.toThrow('Unsuppress failed');
    });
  });

  describe('markFalsePositive', () => {
    it('marks vulnerability as false positive', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerability: {
              id: 'vuln-1',
              vulnerability_id: 'CVE-2024-0001',
              severity: 'high' as const,
              cvss_score: 8.5,
              remediation_status: 'wont_fix' as const,
              component: { name: 'lodash', version: '4.17.19' },
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.markFalsePositive('123', 'vuln-1', 'Not applicable to our use case');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/vulnerabilities/vuln-1/false_positive',
        { reason: 'Not applicable to our use case' }
      );
      expect(result).toEqual(mockResponse.data.data.vulnerability);
    });

    it('handles false positive marking errors', async () => {
      const error = new Error('Marking failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(
        sbomsApi.markFalsePositive('123', 'vuln-1', 'reason')
      ).rejects.toThrow('Marking failed');
    });
  });

  describe('getComponentVulnerabilities', () => {
    it('returns component vulnerabilities', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            vulnerabilities: [
              {
                id: 'vuln-1',
                vulnerability_id: 'CVE-2024-0001',
                severity: 'high' as const,
                cvss_score: 8.5,
                remediation_status: 'open' as const,
                component: { name: 'lodash', version: '4.17.19' },
              },
              {
                id: 'vuln-2',
                vulnerability_id: 'CVE-2024-0002',
                severity: 'medium' as const,
                cvss_score: 5.5,
                remediation_status: 'in_progress' as const,
                component: { name: 'lodash', version: '4.17.19' },
              },
            ],
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getComponentVulnerabilities('123', 'comp-1');

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/components/comp-1/vulnerabilities'
      );
      expect(result).toEqual(mockResponse.data.data.vulnerabilities);
      expect(result).toHaveLength(2);
    });

    it('handles errors', async () => {
      const error = new Error('Failed to fetch');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getComponentVulnerabilities('123', 'comp-1')).rejects.toThrow('Failed to fetch');
    });
  });

  describe('getComplianceStatus', () => {
    it('returns compliance status', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            compliance: {
              ntia_minimum_compliant: true,
              ntia_fields: {
                supplier_name: true,
                component_name: true,
                component_version: true,
                unique_identifier: true,
                dependency_relationship: true,
                author: true,
                timestamp: true,
              },
              completeness_score: 95.5,
              missing_fields: [],
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getComplianceStatus('123');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/compliance');
      expect(result).toEqual(mockResponse.data.data.compliance);
      expect(result.ntia_minimum_compliant).toBe(true);
      expect(result.completeness_score).toBe(95.5);
    });

    it('handles compliance check errors', async () => {
      const error = new Error('Compliance check failed');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getComplianceStatus('123')).rejects.toThrow('Compliance check failed');
    });
  });

  describe('calculateRisk', () => {
    it('calculates risk successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            risk: {
              overall_score: 7.5,
              vulnerability_score: 8.0,
              license_score: 6.5,
              dependency_score: 7.8,
              recommendations: [
                'Update vulnerable dependencies',
                'Review high-risk licenses',
              ],
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.calculateRisk('123');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/sboms/123/calculate_risk');
      expect(result).toEqual(mockResponse.data.data.risk);
      expect(result.overall_score).toBe(7.5);
      expect(result.recommendations).toHaveLength(2);
    });

    it('handles calculation errors', async () => {
      const error = new Error('Calculation failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.calculateRisk('123')).rejects.toThrow('Calculation failed');
    });
  });

  describe('correlateVulnerabilities', () => {
    it('correlates vulnerabilities successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            correlation: {
              correlated_count: 15,
              new_vulnerabilities: 3,
              resolved_vulnerabilities: 2,
              last_correlated_at: '2024-01-01T00:00:00Z',
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.correlateVulnerabilities('123');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/sboms/123/correlate_vulnerabilities'
      );
      expect(result).toEqual(mockResponse.data.data.correlation);
      expect(result.correlated_count).toBe(15);
      expect(result.new_vulnerabilities).toBe(3);
    });

    it('handles correlation errors', async () => {
      const error = new Error('Correlation failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.correlateVulnerabilities('123')).rejects.toThrow('Correlation failed');
    });
  });

  describe('getStatistics', () => {
    it('returns statistics', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            statistics: {
              total_sboms: 25,
              sboms_by_status: {
                draft: 2,
                generating: 3,
                completed: 18,
                failed: 2,
              },
              sboms_by_format: {
                cyclonedx_1_4: 5,
                cyclonedx_1_5: 15,
                spdx_2_3: 5,
              },
              total_components: 1250,
              total_vulnerabilities: 87,
              critical_vulnerabilities: 5,
              avg_risk_score: 6.7,
              compliance_rate: 85.5,
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getStatistics();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/statistics');
      expect(result).toEqual(mockResponse.data.data.statistics);
      expect(result.total_sboms).toBe(25);
      expect(result.compliance_rate).toBe(85.5);
    });

    it('handles statistics errors', async () => {
      const error = new Error('Statistics failed');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getStatistics()).rejects.toThrow('Statistics failed');
    });
  });

  describe('listDiffs', () => {
    it('returns list of diffs', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            diffs: [
              {
                id: 'diff-1',
                source_sbom_id: '123',
                compare_sbom_id: '456',
                added_count: 5,
                removed_count: 3,
                changed_count: 7,
                created_at: '2024-01-01T00:00:00Z',
              },
            ],
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.listDiffs('123');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/diffs');
      expect(result).toEqual(mockResponse.data.data.diffs);
      expect(result).toHaveLength(1);
      expect(result[0].added_count).toBe(5);
    });

    it('handles list errors', async () => {
      const error = new Error('List failed');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.listDiffs('123')).rejects.toThrow('List failed');
    });
  });

  describe('getDiff', () => {
    it('returns diff detail', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            diff: {
              id: 'diff-1',
              source_sbom_id: '123',
              compare_sbom_id: '456',
              added_count: 2,
              removed_count: 1,
              changed_count: 3,
              created_at: '2024-01-01T00:00:00Z',
              added_components: [
                { name: 'react', version: '18.0.0', ecosystem: 'npm' },
              ],
              removed_components: [
                { name: 'lodash', version: '4.17.19', ecosystem: 'npm' },
              ],
              changed_components: [
                {
                  name: 'typescript',
                  old_version: '4.9.0',
                  new_version: '5.0.0',
                  ecosystem: 'npm',
                },
              ],
              added_vulnerabilities: [
                { vulnerability_id: 'CVE-2024-0001', severity: 'high' as const },
              ],
              removed_vulnerabilities: [
                { vulnerability_id: 'CVE-2023-0001', severity: 'medium' as const },
              ],
            },
          },
        },
      };

      mockApiClient.get.mockResolvedValue(mockResponse);

      const result = await sbomsApi.getDiff('123', 'diff-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/sboms/123/diffs/diff-1');
      expect(result).toEqual(mockResponse.data.data.diff);
      expect(result.added_components).toHaveLength(1);
      expect(result.changed_components).toHaveLength(1);
    });

    it('handles get errors', async () => {
      const error = new Error('Get failed');
      mockApiClient.get.mockRejectedValue(error);

      await expect(sbomsApi.getDiff('123', 'diff-1')).rejects.toThrow('Get failed');
    });
  });

  describe('createDiff', () => {
    it('creates diff successfully', async () => {
      const mockResponse = {
        data: {
          success: true,
          data: {
            diff: {
              id: 'diff-1',
              source_sbom_id: '123',
              compare_sbom_id: '456',
              added_count: 5,
              removed_count: 3,
              changed_count: 7,
              created_at: '2024-01-01T00:00:00Z',
            },
          },
        },
      };

      mockApiClient.post.mockResolvedValue(mockResponse);

      const result = await sbomsApi.createDiff('123', '456');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/sboms/123/diffs', {
        compare_sbom_id: '456',
      });
      expect(result).toEqual(mockResponse.data.data.diff);
      expect(result.compare_sbom_id).toBe('456');
    });

    it('handles create errors', async () => {
      const error = new Error('Create failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.createDiff('123', '456')).rejects.toThrow('Create failed');
    });
  });

  describe('exportSbom', () => {
    const formats: Array<'json' | 'xml' | 'pdf' | 'cyclonedx' | 'spdx'> = [
      'json',
      'xml',
      'pdf',
      'cyclonedx',
      'spdx',
    ];

    formats.forEach((format) => {
      it(`exports sbom in ${format} format`, async () => {
        const mockBlob = new Blob([`{${format}: "data"}`], { type: 'application/octet-stream' });
        mockApiClient.post.mockResolvedValue({ data: mockBlob });

        const result = await sbomsApi.exportSbom('123', format);

        expect(mockApiClient.post).toHaveBeenCalledWith(
          '/supply_chain/sboms/123/export',
          { format },
          { responseType: 'blob' }
        );
        expect(result).toBe(mockBlob);
      });
    });

    it('handles export errors', async () => {
      const error = new Error('Export failed');
      mockApiClient.post.mockRejectedValue(error);

      await expect(sbomsApi.exportSbom('123', 'json')).rejects.toThrow('Export failed');
    });
  });
});
