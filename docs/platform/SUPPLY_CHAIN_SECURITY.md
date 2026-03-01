# Supply Chain Security

**Software supply chain security monitoring and compliance**

---

## Table of Contents

1. [Overview](#overview)
2. [Feature Architecture](#feature-architecture)
3. [Components](#components)
4. [Security Scanning](#security-scanning)
5. [Compliance Monitoring](#compliance-monitoring)
6. [API Integration](#api-integration)

---

## Overview

The Supply Chain Security feature provides comprehensive monitoring and management of software dependencies, vulnerabilities, and compliance requirements.

### Key Capabilities

- **Dependency scanning**: Automated vulnerability detection
- **SBOM generation**: Software Bill of Materials
- **License compliance**: Track and validate licenses
- **Security alerts**: Real-time vulnerability notifications
- **Remediation guidance**: Actionable fix recommendations

### Feature Structure

```
frontend/src/features/supply-chain/
├── index.ts              # Public exports
├── components/           # UI components
├── pages/                # Page components
├── services/             # API services
├── hooks/                # Custom hooks
├── types/                # TypeScript types
├── __tests__/            # Test files
└── testing/              # Test utilities
```

---

## Feature Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  Supply Chain Dashboard                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ Dependency  │  │ Vulnerability│  │  License   │        │
│  │  Scanner    │  │   Tracker   │  │  Monitor   │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │
│         └────────────────┼────────────────┘                │
│                          │                                 │
│  ┌───────────────────────▼───────────────────────────┐    │
│  │              Security Analysis Engine              │    │
│  └───────────────────────┬───────────────────────────┘    │
│                          │                                 │
│  ┌───────────────────────▼───────────────────────────┐    │
│  │                 Alert Manager                      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Repository/Package → Scanner → Analysis → Dashboard
                                 ↓
                            Alerts/Reports
```

---

## Components

### Dashboard Components

#### SupplyChainOverview

Main dashboard showing security status:

```typescript
interface SecurityOverview {
  totalDependencies: number;
  vulnerablePackages: number;
  criticalVulnerabilities: number;
  highVulnerabilities: number;
  mediumVulnerabilities: number;
  lowVulnerabilities: number;
  lastScanDate: string;
  complianceScore: number;
}
```

#### VulnerabilityList

Displays detected vulnerabilities:

```typescript
interface Vulnerability {
  id: string;
  cveId: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  packageName: string;
  currentVersion: string;
  fixedVersion: string | null;
  description: string;
  publishedDate: string;
  cvssScore: number;
  exploitAvailable: boolean;
}
```

#### DependencyTree

Visualizes dependency hierarchy:

```typescript
interface Dependency {
  name: string;
  version: string;
  license: string;
  vulnerabilities: Vulnerability[];
  dependencies: Dependency[];
  isDirectDependency: boolean;
}
```

### Scanning Components

#### ScanConfiguration

Configure scanning parameters:

```typescript
interface ScanConfig {
  scanType: 'full' | 'quick' | 'targeted';
  includeDevDependencies: boolean;
  severityThreshold: 'critical' | 'high' | 'medium' | 'low';
  autoFix: boolean;
  ignoredVulnerabilities: string[];
  repositories: string[];
}
```

#### ScanResults

Display scan results:

```typescript
interface ScanResult {
  scanId: string;
  startedAt: string;
  completedAt: string;
  status: 'completed' | 'in_progress' | 'failed';
  vulnerabilitiesFound: number;
  packagesScanned: number;
  recommendations: Recommendation[];
}
```

---

## Security Scanning

### Vulnerability Detection

```typescript
// services/securityScannerService.ts

class SecurityScannerService {
  async scanDependencies(config: ScanConfig): Promise<ScanResult> {
    const response = await apiClient.post('/supply-chain/scan', config);
    return response.data;
  }

  async getVulnerabilities(filters?: VulnerabilityFilters): Promise<Vulnerability[]> {
    const response = await apiClient.get('/supply-chain/vulnerabilities', {
      params: filters,
    });
    return response.data;
  }

  async getDependencyTree(packageName?: string): Promise<Dependency[]> {
    const response = await apiClient.get('/supply-chain/dependencies', {
      params: { package: packageName },
    });
    return response.data;
  }
}
```

### SBOM Generation

```typescript
interface SBOM {
  format: 'cyclonedx' | 'spdx';
  version: string;
  createdAt: string;
  components: SBOMComponent[];
}

interface SBOMComponent {
  type: 'library' | 'application' | 'framework';
  name: string;
  version: string;
  purl: string;
  licenses: string[];
  hashes: {
    algorithm: string;
    value: string;
  }[];
}

async generateSBOM(format: 'cyclonedx' | 'spdx'): Promise<SBOM> {
  const response = await apiClient.post('/supply-chain/sbom/generate', { format });
  return response.data;
}
```

### Severity Classification

| Severity | CVSS Score | Response Time | Example |
|----------|------------|---------------|---------|
| Critical | 9.0 - 10.0 | Immediate | RCE, data exfiltration |
| High | 7.0 - 8.9 | 24 hours | Privilege escalation |
| Medium | 4.0 - 6.9 | 1 week | Information disclosure |
| Low | 0.1 - 3.9 | 30 days | Minor issues |

---

## Compliance Monitoring

### License Compliance

```typescript
interface LicenseReport {
  totalPackages: number;
  licenseBreakdown: {
    license: string;
    count: number;
    packages: string[];
    compatible: boolean;
  }[];
  incompatibleLicenses: {
    package: string;
    license: string;
    reason: string;
  }[];
  complianceScore: number;
}

async getLicenseReport(): Promise<LicenseReport> {
  const response = await apiClient.get('/supply-chain/licenses');
  return response.data;
}
```

### Policy Enforcement

```typescript
interface SecurityPolicy {
  id: string;
  name: string;
  rules: PolicyRule[];
  actions: PolicyAction[];
  enabled: boolean;
}

interface PolicyRule {
  type: 'severity' | 'license' | 'age' | 'maintainer';
  operator: 'equals' | 'greater_than' | 'less_than' | 'contains';
  value: string | number;
}

interface PolicyAction {
  type: 'block' | 'warn' | 'notify';
  target: string[];
}
```

### Compliance Frameworks

Support for standard compliance frameworks:

- **SOC 2**: Security and availability controls
- **ISO 27001**: Information security management
- **PCI DSS**: Payment card security
- **HIPAA**: Healthcare data protection
- **GDPR**: Data privacy compliance

```typescript
interface ComplianceCheck {
  framework: string;
  controls: {
    id: string;
    name: string;
    status: 'compliant' | 'non_compliant' | 'partial';
    evidence: string[];
    remediation?: string;
  }[];
  overallStatus: 'compliant' | 'non_compliant' | 'partial';
  lastChecked: string;
}
```

---

## API Integration

### Endpoints

```http
# Scanning
POST   /api/v1/supply-chain/scan
GET    /api/v1/supply-chain/scans
GET    /api/v1/supply-chain/scans/:id

# Vulnerabilities
GET    /api/v1/supply-chain/vulnerabilities
GET    /api/v1/supply-chain/vulnerabilities/:id
PATCH  /api/v1/supply-chain/vulnerabilities/:id/ignore
PATCH  /api/v1/supply-chain/vulnerabilities/:id/remediate

# Dependencies
GET    /api/v1/supply-chain/dependencies
GET    /api/v1/supply-chain/dependencies/:name

# SBOM
POST   /api/v1/supply-chain/sbom/generate
GET    /api/v1/supply-chain/sbom
GET    /api/v1/supply-chain/sbom/:id/download

# Licenses
GET    /api/v1/supply-chain/licenses
GET    /api/v1/supply-chain/licenses/report

# Policies
GET    /api/v1/supply-chain/policies
POST   /api/v1/supply-chain/policies
PATCH  /api/v1/supply-chain/policies/:id
DELETE /api/v1/supply-chain/policies/:id

# Compliance
GET    /api/v1/supply-chain/compliance
GET    /api/v1/supply-chain/compliance/:framework
```

### Webhook Events

```typescript
type SupplyChainEvent =
  | 'scan.completed'
  | 'vulnerability.detected'
  | 'vulnerability.critical'
  | 'license.violation'
  | 'policy.violation'
  | 'compliance.failed';

interface WebhookPayload {
  event: SupplyChainEvent;
  timestamp: string;
  data: {
    scanId?: string;
    vulnerabilityId?: string;
    packageName?: string;
    severity?: string;
    details: Record<string, unknown>;
  };
}
```

---

## Hooks

### useSupplyChainDashboard

```typescript
const useSupplyChainDashboard = () => {
  const [overview, setOverview] = useState<SecurityOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const data = await supplyChainService.getOverview();
      setOverview(data);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { overview, loading, error, refresh };
};
```

### useVulnerabilities

```typescript
const useVulnerabilities = (filters?: VulnerabilityFilters) => {
  const [vulnerabilities, setVulnerabilities] = useState<Vulnerability[]>([]);
  const [loading, setLoading] = useState(true);

  const ignoreVulnerability = async (id: string, reason: string) => {
    await supplyChainService.ignoreVulnerability(id, reason);
    setVulnerabilities(prev => prev.filter(v => v.id !== id));
  };

  const remediateVulnerability = async (id: string) => {
    const result = await supplyChainService.remediateVulnerability(id);
    return result;
  };

  return {
    vulnerabilities,
    loading,
    ignoreVulnerability,
    remediateVulnerability,
  };
};
```

---

## Best Practices

### 1. Regular Scanning

Schedule automated scans:

```typescript
const scanConfig: ScanConfig = {
  scanType: 'full',
  includeDevDependencies: true,
  severityThreshold: 'medium',
  autoFix: false,
  schedule: '0 0 * * *', // Daily at midnight
};
```

### 2. Severity-Based Response

Prioritize by severity:

| Severity | Action |
|----------|--------|
| Critical | Immediate remediation, block deployment |
| High | Fix within 24 hours |
| Medium | Add to sprint backlog |
| Low | Track for next maintenance |

### 3. License Policy

Define allowed licenses:

```typescript
const allowedLicenses = [
  'MIT',
  'Apache-2.0',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'ISC',
];
```

### 4. Dependency Review

Review before adding dependencies:

- Check vulnerability history
- Verify maintainer activity
- Review license compatibility
- Assess transitive dependencies

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `frontend/src/features/supply-chain/`
