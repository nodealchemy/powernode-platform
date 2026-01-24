# frozen_string_literal: true

# Supply Chain Security Articles - Priority 2
# Creates comprehensive documentation for Supply Chain Security features

puts "  🔐 Creating Supply Chain Security articles..."

supply_chain_cat = KnowledgeBase::Category.find_by!(slug: "supply-chain-security")
author = User.find_by!(email: "admin@powernode.org")

# Article 28: Supply Chain Security Overview (Featured)
supply_chain_overview_content = <<~MARKDOWN
# Supply Chain Security Overview

Powernode's Supply Chain Security module provides comprehensive tools for managing software supply chain risks, ensuring compliance with security frameworks, and maintaining visibility into your software dependencies.

## What You'll Learn

- Software supply chain security fundamentals
- Key features: SBOMs, Attestations, Scanning, Licenses, Vendors
- Compliance frameworks and certifications
- Risk assessment and mitigation strategies
- Getting started with supply chain security

## Why Supply Chain Security Matters

Modern software relies on thousands of dependencies, creating a complex web of potential vulnerabilities:

- **68% of codebases** contain open source with known vulnerabilities
- **Supply chain attacks** increased 742% from 2019 to 2022
- **Average cost** of a supply chain breach: $4.5M

Powernode helps you:
- Track and inventory all software components
- Identify vulnerabilities before they're exploited
- Demonstrate compliance to customers and auditors
- Manage vendor risks proactively

## Key Features

### Software Bill of Materials (SBOM)

Maintain a complete inventory of software components:

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "components": [
    {
      "type": "library",
      "name": "lodash",
      "version": "4.17.21",
      "purl": "pkg:npm/lodash@4.17.21",
      "licenses": [{"license": {"id": "MIT"}}]
    }
  ]
}
```

**Capabilities:**
- Import SBOMs in SPDX and CycloneDX formats
- Generate SBOMs from package managers
- Track component versions across projects
- Identify outdated and vulnerable components

### Attestations and Provenance

Verify the integrity and origin of software artifacts:

- **Build attestations** - Prove how software was built
- **SLSA compliance** - Meet supply chain security levels
- **Signature verification** - Validate artifact authenticity
- **Provenance tracking** - Trace software origins

### Container Scanning

Analyze container images for security issues:

```yaml
Scan Results:
  Image: myapp:v1.2.3
  Base Image: node:20-alpine
  Vulnerabilities:
    Critical: 0
    High: 2
    Medium: 5
    Low: 12
  Compliance:
    - CIS Docker Benchmark: PASS
    - NIST 800-190: PASS
```

### License Management

Track and enforce license compliance:

| License Type | Commercial Use | Modification | Distribution | Patent |
|--------------|----------------|--------------|--------------|--------|
| MIT | ✅ | ✅ | ✅ | ✅ |
| Apache 2.0 | ✅ | ✅ | ✅ | ✅ |
| GPL 3.0 | ✅ | ✅ | ⚠️ Copyleft | ✅ |
| AGPL 3.0 | ⚠️ | ✅ | ⚠️ Copyleft | ✅ |

### Vendor Risk Management

Assess and monitor third-party vendors:

- Vendor categorization and tiering
- Risk assessment questionnaires
- Compliance document tracking
- Periodic review scheduling
- Risk scoring and thresholds

## Compliance Frameworks

### SLSA (Supply-chain Levels for Software Artifacts)

```yaml
SLSA Levels:
  Level 1:
    - Documentation of build process
    - Provenance generated
  Level 2:
    - Hosted build platform
    - Authenticated provenance
  Level 3:
    - Hardened build platform
    - Non-falsifiable provenance
  Level 4:
    - Hermetic builds
    - Two-person review
```

### NIST Secure Software Development

Align with NIST SSDF practices:

- **Prepare the Organization (PO)** - Policies and training
- **Protect the Software (PS)** - Secure development
- **Produce Well-Secured Software (PW)** - Verification
- **Respond to Vulnerabilities (RV)** - Incident response

### SOC 2 Type II

Demonstrate security controls:

- **Security** - Protection against unauthorized access
- **Availability** - System uptime and performance
- **Processing Integrity** - Accurate data processing
- **Confidentiality** - Protection of sensitive data
- **Privacy** - Personal information handling

## Getting Started

### Day 1: Initial Assessment

1. **Inventory Current State**
   - Navigate to **Supply Chain > Dashboard**
   - Review existing component data
   - Identify gaps in visibility

2. **Import First SBOM**
   - Click **SBOMs > Upload SBOM**
   - Select file (SPDX or CycloneDX)
   - Review parsed components
   - Save to inventory

### Week 1: Vulnerability Analysis

1. **Scan Components**
   - Enable automatic vulnerability scanning
   - Review critical and high findings
   - Create remediation tasks
   - Track resolution progress

2. **Set Up Alerts**
   - Configure CVE notification thresholds
   - Set up email alerts for critical issues
   - Integrate with ticketing systems

### Week 2: Vendor Assessment

1. **Add Key Vendors**
   - Navigate to **Supply Chain > Vendors**
   - Add vendor details and categories
   - Assign risk tiers
   - Upload compliance documents

2. **Schedule Reviews**
   - Set up periodic review cadence
   - Create assessment questionnaires
   - Assign reviewers

## Risk Assessment Framework

### Risk Scoring Methodology

```yaml
Risk Score Calculation:
  Component Risk:
    - Vulnerability severity (40%)
    - License risk (20%)
    - Maintenance status (20%)
    - Usage scope (20%)

  Vendor Risk:
    - Security posture (30%)
    - Compliance status (25%)
    - Financial stability (20%)
    - Incident history (15%)
    - Geographic risk (10%)

  Thresholds:
    Critical: 90-100
    High: 70-89
    Medium: 40-69
    Low: 0-39
```

### Mitigation Strategies

**High-Risk Components:**
- Immediate patching or replacement
- Isolation and monitoring
- Compensating controls
- Vendor engagement

**Medium-Risk Components:**
- Scheduled updates
- Monitoring enhancement
- Documentation review
- Policy alignment

## Dashboard Overview

### Key Metrics

Monitor your supply chain health:

| Metric | Description | Target |
|--------|-------------|--------|
| Component Coverage | % of projects with SBOMs | > 95% |
| Vulnerability Density | Critical vulns per 1000 components | < 5 |
| License Compliance | % of approved licenses | 100% |
| Vendor Risk Score | Average across all vendors | < 40 |
| Attestation Coverage | % of artifacts with attestations | > 90% |

### Visual Analytics

- **Dependency Graph** - Visualize component relationships
- **Risk Heatmap** - Identify high-risk areas
- **Trend Charts** - Track security improvements
- **Compliance Status** - Framework adherence

## Best Practices

### SBOM Management

1. **Automate Generation**
   - Integrate with CI/CD pipelines
   - Generate SBOMs on every build
   - Store with release artifacts

2. **Maintain Currency**
   - Update SBOMs with each release
   - Track version changes
   - Archive historical SBOMs

### Vulnerability Management

1. **Prioritize Effectively**
   - Focus on exploitable vulnerabilities
   - Consider component exposure
   - Evaluate business impact

2. **Respond Quickly**
   - Set SLAs by severity level
   - Automate patching where possible
   - Track remediation metrics

### Vendor Management

1. **Due Diligence**
   - Assess before onboarding
   - Require security certifications
   - Review incident history

2. **Continuous Monitoring**
   - Schedule periodic reviews
   - Monitor public disclosures
   - Track compliance expirations

## Integration Points

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Generate SBOM
  uses: anchore/sbom-action@v0
  with:
    artifact-name: sbom.spdx.json

- name: Upload to Powernode
  run: |
    curl -X POST ${{ secrets.POWERNODE_API }}/supply-chain/sboms \\
      -H "Authorization: Bearer ${{ secrets.API_KEY }}" \\
      -F "file=@sbom.spdx.json" \\
      -F "project=my-app" \\
      -F "version=${{ github.sha }}"
```

### Alerting Integration

- **Slack** - Real-time vulnerability alerts
- **PagerDuty** - Critical issue escalation
- **Jira** - Automatic ticket creation
- **Email** - Digest and summary reports

## Next Steps

Explore detailed guides:

1. [SBOM Management and Analysis](/kb/sbom-management-analysis) - Deep dive into SBOM features
2. [Vendor Risk Assessment](/kb/vendor-risk-assessment) - Complete vendor management guide

---

Questions about supply chain security? Contact security@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "supply-chain-security-overview") do |article|
  article.title = "Supply Chain Security Overview"
  article.category = supply_chain_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Comprehensive introduction to Powernode's supply chain security features including SBOMs, attestations, vulnerability scanning, and vendor risk management."
  article.content = supply_chain_overview_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Supply Chain Security Overview"

# Article 29: SBOM Management and Analysis
sbom_content = <<~MARKDOWN
# SBOM Management and Analysis

Software Bill of Materials (SBOM) is the foundation of supply chain security. Learn how to create, import, analyze, and maintain SBOMs in Powernode.

## What is an SBOM?

An SBOM is a formal, machine-readable inventory of software components and dependencies. Think of it as a "nutrition label" for software.

### Key Information in an SBOM

- **Component Name** - Package or library identifier
- **Version** - Specific version number
- **Supplier** - Original author or vendor
- **Licenses** - Usage rights and restrictions
- **Dependencies** - Nested component relationships
- **Hashes** - Integrity verification checksums

## SBOM Formats

### CycloneDX

Industry-standard format with excellent vulnerability correlation:

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "version": 1,
  "metadata": {
    "timestamp": "2024-01-15T10:30:00Z",
    "tools": [{"vendor": "Powernode", "name": "SBOM Generator", "version": "1.0"}],
    "component": {
      "type": "application",
      "name": "my-application",
      "version": "2.1.0"
    }
  },
  "components": [
    {
      "type": "library",
      "bom-ref": "pkg:npm/express@4.18.2",
      "name": "express",
      "version": "4.18.2",
      "purl": "pkg:npm/express@4.18.2",
      "licenses": [{"license": {"id": "MIT"}}],
      "externalReferences": [
        {"type": "website", "url": "https://expressjs.com"}
      ]
    }
  ],
  "dependencies": [
    {
      "ref": "my-application",
      "dependsOn": ["pkg:npm/express@4.18.2"]
    }
  ]
}
```

### SPDX

Linux Foundation standard with legal focus:

```json
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "my-application-sbom",
  "documentNamespace": "https://powernode.org/sboms/my-application",
  "creationInfo": {
    "created": "2024-01-15T10:30:00Z",
    "creators": ["Tool: powernode-sbom-1.0"]
  },
  "packages": [
    {
      "SPDXID": "SPDXRef-Package-express",
      "name": "express",
      "versionInfo": "4.18.2",
      "downloadLocation": "https://registry.npmjs.org/express/-/express-4.18.2.tgz",
      "licenseConcluded": "MIT",
      "externalRefs": [
        {
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:npm/express@4.18.2"
        }
      ]
    }
  ]
}
```

## Importing SBOMs

### Manual Upload

1. Navigate to **Supply Chain > SBOMs**
2. Click **Upload SBOM**
3. Select file (JSON, XML, or tag-value format)
4. Configure import options:
   - Project assignment
   - Version tagging
   - Duplicate handling
5. Review parsed components
6. Confirm import

### API Import

```bash
# Upload SBOM via API
curl -X POST https://api.powernode.org/api/v1/supply-chain/sboms \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: multipart/form-data" \\
  -F "file=@sbom.cyclonedx.json" \\
  -F "project_id=proj_01HQ7EXAMPLE" \\
  -F "version=2.1.0" \\
  -F "source=ci-pipeline"
```

### CI/CD Integration

**GitHub Actions:**
```yaml
name: SBOM Generation
on:
  push:
    branches: [main]

jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          format: cyclonedx-json
          output-file: sbom.json

      - name: Upload to Powernode
        run: |
          curl -X POST "${{ secrets.POWERNODE_API_URL }}/supply-chain/sboms" \\
            -H "Authorization: Bearer ${{ secrets.POWERNODE_API_KEY }}" \\
            -F "file=@sbom.json" \\
            -F "project_id=${{ secrets.PROJECT_ID }}" \\
            -F "version=${{ github.sha }}"
```

**GitLab CI:**
```yaml
sbom:
  stage: security
  image: anchore/syft:latest
  script:
    - syft . -o cyclonedx-json > sbom.json
    - |
      curl -X POST "$POWERNODE_API_URL/supply-chain/sboms" \\
        -H "Authorization: Bearer $POWERNODE_API_KEY" \\
        -F "file=@sbom.json" \\
        -F "project_id=$PROJECT_ID" \\
        -F "version=$CI_COMMIT_SHA"
  artifacts:
    paths:
      - sbom.json
```

## Generating SBOMs

### From Package Managers

Powernode can generate SBOMs from various package managers:

**Node.js (npm/yarn):**
```bash
# Using Syft
syft . -o cyclonedx-json > sbom.json

# Using CycloneDX CLI
npx @cyclonedx/cyclonedx-npm --output-file sbom.json
```

**Python (pip/poetry):**
```bash
# Using Syft
syft . -o cyclonedx-json > sbom.json

# Using CycloneDX CLI
pip install cyclonedx-bom
cyclonedx-py -o sbom.json
```

**Ruby (bundler):**
```bash
gem install cyclonedx-ruby
cyclonedx-ruby -o sbom.json
```

**Go:**
```bash
syft . -o cyclonedx-json > sbom.json
```

### From Container Images

```bash
# Scan container image
syft myregistry/myapp:v1.2.3 -o cyclonedx-json > sbom.json

# Scan with additional metadata
syft myregistry/myapp:v1.2.3 \\
  -o cyclonedx-json \\
  --name "My Application" \\
  --version "1.2.3" \\
  > sbom.json
```

## Vulnerability Detection

### Automatic Scanning

When SBOMs are imported, Powernode automatically:

1. Matches components against vulnerability databases
2. Correlates by Package URL (purl) and CPE
3. Calculates risk scores
4. Generates findings

### Vulnerability Sources

| Source | Coverage | Update Frequency |
|--------|----------|------------------|
| NVD (National Vulnerability Database) | Comprehensive | Continuous |
| GitHub Advisory Database | Open source | Real-time |
| OSV (Open Source Vulnerabilities) | Cross-ecosystem | Real-time |
| Vendor Advisories | Product-specific | As released |

### Viewing Vulnerabilities

```yaml
Vulnerability Finding:
  Component: lodash@4.17.20
  CVE: CVE-2021-23337
  Severity: High (CVSS 7.2)
  Description: Prototype pollution in lodash
  Fixed Version: 4.17.21
  Status: Open
  First Detected: 2024-01-10
  EPSS Score: 0.45 (45% exploitation probability)
```

### Risk Prioritization

Powernode prioritizes vulnerabilities using:

- **CVSS Score** - Base severity rating
- **EPSS Score** - Exploitation probability
- **Component Usage** - Direct vs transitive dependency
- **Environment** - Production vs development
- **Compensating Controls** - Network isolation, WAF, etc.

```yaml
Priority Matrix:
  Critical Priority:
    - CVSS >= 9.0 AND EPSS >= 0.5
    - OR CVSS >= 7.0 AND direct dependency AND production

  High Priority:
    - CVSS >= 7.0 AND EPSS >= 0.3
    - OR CVSS >= 9.0 AND transitive dependency

  Medium Priority:
    - CVSS >= 4.0 AND EPSS >= 0.1

  Low Priority:
    - Everything else
```

## Component Analysis

### Dependency Trees

Visualize component relationships:

```
my-application@2.1.0
├── express@4.18.2
│   ├── body-parser@1.20.1
│   │   └── bytes@3.1.2
│   ├── cookie@0.5.0
│   └── debug@2.6.9
├── lodash@4.17.21
└── axios@1.6.0
    └── form-data@4.0.0
```

### Version Analysis

Track component versions across projects:

| Component | Project A | Project B | Project C | Latest |
|-----------|-----------|-----------|-----------|--------|
| express | 4.18.2 ✅ | 4.17.1 ⚠️ | 4.18.2 ✅ | 4.18.2 |
| lodash | 4.17.21 ✅ | 4.17.20 ❌ | 4.17.21 ✅ | 4.17.21 |
| axios | 1.6.0 ✅ | 0.21.1 ❌ | 1.5.0 ⚠️ | 1.6.0 |

### SBOM Comparison

Compare SBOMs between versions:

```yaml
SBOM Diff: v2.0.0 → v2.1.0

Added Components:
  + axios@1.6.0
  + form-data@4.0.0

Removed Components:
  - request@2.88.2 (deprecated)
  - request-promise@4.2.6

Updated Components:
  ~ express: 4.17.1 → 4.18.2
  ~ lodash: 4.17.20 → 4.17.21 (security fix)

Vulnerability Changes:
  Fixed: CVE-2021-23337 (lodash)
  Fixed: CVE-2020-8244 (request)
  New: None
```

## Container Scanning

### Image Analysis

Scan container images for:

- OS package vulnerabilities
- Application dependencies
- Secrets and credentials
- Configuration issues
- Compliance violations

```bash
# Scan image via API
curl -X POST https://api.powernode.org/api/v1/supply-chain/containers/scan \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "image": "myregistry/myapp:v1.2.3",
    "registry_credentials": {
      "username": "service-account",
      "password": "${{ secrets.REGISTRY_PASSWORD }}"
    }
  }'
```

### Attestation Verification

Verify container provenance:

```yaml
Attestation Verification:
  Image: myregistry/myapp@sha256:abc123...
  Attestations:
    - Type: SLSA Provenance v1.0
      Verified: ✅
      Builder: github-hosted-runners
      Source: github.com/myorg/myapp
      Commit: abc123def456

    - Type: Cosign Signature
      Verified: ✅
      Signer: build-service@myorg.iam
      Timestamp: 2024-01-15T10:30:00Z
```

## Best Practices

### SBOM Generation

1. **Generate Early and Often**
   - Create SBOMs during build, not just release
   - Include development dependencies
   - Track changes over time

2. **Automate Everything**
   - Integrate with CI/CD pipelines
   - Fail builds on critical vulnerabilities
   - Auto-update to fix known issues

3. **Maintain Accuracy**
   - Verify component versions
   - Include all dependencies (direct and transitive)
   - Update licensing information

### Vulnerability Management

1. **Set Clear SLAs**
   ```yaml
   Remediation SLAs:
     Critical: 24 hours
     High: 7 days
     Medium: 30 days
     Low: 90 days
   ```

2. **Track Exceptions**
   - Document accepted risks
   - Set expiration dates
   - Require periodic review

## Troubleshooting

### Import Failures

**Invalid Format:**
- Verify SBOM follows specification
- Check for malformed JSON/XML
- Validate against schema

**Missing Components:**
- Ensure all dependencies resolved
- Check for private packages
- Verify package manager lock files

### Vulnerability Mismatches

**False Positives:**
- Verify component version accuracy
- Check if vulnerability applies to usage
- Document and suppress if confirmed false

**Missing Vulnerabilities:**
- Trigger manual rescan
- Check database update status
- Verify component identification

## Related Articles

- [Supply Chain Security Overview](/kb/supply-chain-security-overview)
- [Vendor Risk Assessment](/kb/vendor-risk-assessment)

---

Need help with SBOM management? Contact security@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "sbom-management-analysis") do |article|
  article.title = "SBOM Management and Analysis"
  article.category = supply_chain_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Complete guide to Software Bill of Materials (SBOM) management including creation, import, vulnerability detection, and container scanning with attestations."
  article.content = sbom_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ SBOM Management and Analysis"

# Article 30: Vendor Risk Assessment
vendor_risk_content = <<~MARKDOWN
# Vendor Risk Assessment

Effectively manage third-party vendor risks with Powernode's comprehensive vendor assessment tools, questionnaires, and continuous monitoring capabilities.

## Vendor Management Dashboard

### Overview

The Vendor Dashboard provides a unified view of all third-party vendors:

- **Total Vendors** - Count by category and risk tier
- **Risk Distribution** - Visual breakdown of risk levels
- **Upcoming Reviews** - Scheduled assessments due
- **Compliance Status** - Certificate expirations and gaps
- **Recent Activity** - Assessment submissions and updates

### Vendor List View

| Vendor | Category | Risk Tier | Score | Next Review | Status |
|--------|----------|-----------|-------|-------------|--------|
| AWS | Cloud Provider | Critical | 25 | Mar 2024 | ✅ Compliant |
| Stripe | Payment | Critical | 30 | Apr 2024 | ✅ Compliant |
| DataDog | Monitoring | High | 45 | Feb 2024 | ⚠️ Review Due |
| Acme Corp | Contractor | Medium | 55 | Jun 2024 | ✅ Compliant |

## Adding Vendors

### Basic Information

1. Navigate to **Supply Chain > Vendors**
2. Click **Add Vendor**
3. Enter vendor details:

```yaml
Vendor Information:
  Name: Acme Cloud Services
  Legal Entity: Acme Cloud Inc.
  Website: https://acmecloud.example.com
  Primary Contact:
    Name: Jane Smith
    Email: jane@acmecloud.example.com
    Phone: +1-555-0123
  Address:
    Street: 123 Tech Park
    City: San Francisco
    State: CA
    Country: USA
```

### Categorization

Assign vendors to appropriate categories:

| Category | Examples | Default Tier |
|----------|----------|--------------|
| Cloud Infrastructure | AWS, Azure, GCP | Critical |
| Payment Processing | Stripe, PayPal, Adyen | Critical |
| Security Tools | CrowdStrike, Splunk | High |
| Development Tools | GitHub, Jira, Confluence | High |
| Marketing | HubSpot, Mailchimp | Medium |
| Office Software | Slack, Zoom, Google Workspace | Medium |
| Consulting | Staff augmentation, agencies | Varies |

### Risk Tiering

Assign risk tiers based on data access and criticality:

```yaml
Risk Tiers:
  Critical:
    Description: Direct access to customer data or critical systems
    Examples:
      - Payment processors
      - Cloud infrastructure
      - Identity providers
    Review Frequency: Quarterly
    Assessment Depth: Comprehensive

  High:
    Description: Access to sensitive data or important systems
    Examples:
      - Security monitoring
      - CI/CD platforms
      - Communication tools
    Review Frequency: Semi-annually
    Assessment Depth: Standard

  Medium:
    Description: Limited data access, non-critical functions
    Examples:
      - Marketing tools
      - Analytics platforms
      - Productivity software
    Review Frequency: Annually
    Assessment Depth: Basic

  Low:
    Description: Minimal data access, easily replaceable
    Examples:
      - Stock photos
      - Domain registrars
      - Office supplies
    Review Frequency: Bi-annually
    Assessment Depth: Minimal
```

## Risk Assessment Questionnaires

### Built-in Templates

Powernode includes pre-built questionnaire templates:

**Security Assessment (SOC 2 Aligned):**
```yaml
Categories:
  - Access Control (15 questions)
  - Data Protection (12 questions)
  - Incident Response (8 questions)
  - Business Continuity (10 questions)
  - Network Security (10 questions)

Sample Questions:
  1. Do you maintain SOC 2 Type II certification?
     Type: Yes/No + Evidence Upload
     Weight: High

  2. How do you encrypt data at rest?
     Type: Multiple Choice
     Options:
       - AES-256
       - AES-128
       - Other (specify)
       - Not encrypted
     Weight: Critical

  3. What is your incident response SLA?
     Type: Text
     Weight: Medium
```

**Privacy Assessment (GDPR Aligned):**
```yaml
Categories:
  - Data Processing (10 questions)
  - Subject Rights (8 questions)
  - Cross-border Transfers (6 questions)
  - Data Retention (5 questions)
  - Subprocessors (7 questions)
```

### Custom Questionnaires

Create industry-specific assessments:

1. Navigate to **Supply Chain > Settings > Questionnaires**
2. Click **Create Template**
3. Define sections and questions
4. Set scoring weights
5. Configure conditional logic
6. Save and activate

```yaml
Custom Questionnaire Example:
  Name: Healthcare Vendor Assessment
  Sections:
    - name: HIPAA Compliance
      questions:
        - text: Are you a HIPAA covered entity or business associate?
          type: single_choice
          options: [Covered Entity, Business Associate, Neither]
          required: true
          weight: 10

        - text: Do you have a signed BAA template available?
          type: yes_no_evidence
          evidence_required: true
          weight: 8

    - name: Technical Safeguards
      questions:
        - text: Describe your PHI encryption methods
          type: text
          min_length: 100
          weight: 9
```

### Sending Assessments

1. Select vendor from list
2. Click **Request Assessment**
3. Choose questionnaire template
4. Set deadline and reminders
5. Add custom message
6. Send invitation

```yaml
Assessment Request:
  Vendor: Acme Cloud Services
  Template: Security Assessment (SOC 2)
  Deadline: 2024-02-28
  Reminders:
    - 7 days before deadline
    - 3 days before deadline
    - On deadline day
  Custom Message: |
    Dear Acme Cloud team,

    As part of our annual vendor review, please complete
    the attached security assessment questionnaire.

    Contact security@ourcompany.com with questions.
```

## Document Management

### Required Documents

Track compliance documents for each vendor:

| Document Type | Required For | Expiration |
|---------------|--------------|------------|
| SOC 2 Type II Report | Critical/High tiers | Annual |
| Penetration Test Summary | Critical tier | Annual |
| Insurance Certificate | All tiers | Annual |
| Business Continuity Plan | Critical/High tiers | Bi-annual |
| Privacy Policy | All tiers | As updated |
| DPA/BAA | Data processors | Contract term |

### Document Upload

Upload and track vendor documents:

1. Navigate to vendor profile
2. Click **Documents** tab
3. Click **Upload Document**
4. Select document type
5. Set expiration date (if applicable)
6. Add notes and tags

```yaml
Document Details:
  Type: SOC 2 Type II Report
  Vendor: Acme Cloud Services
  File: acme_soc2_2024.pdf
  Uploaded: 2024-01-15
  Expiration: 2025-01-15
  Status: Valid
  Notes: Covers period Jan 2023 - Dec 2023
```

### Expiration Alerts

Configure automatic notifications:

```yaml
Alert Configuration:
  Document Expiration:
    - 90 days before: Email to vendor manager
    - 60 days before: Email to vendor manager
    - 30 days before: Email to vendor manager + security team
    - 14 days before: Escalation to security lead
    - Expired: Alert to compliance officer
```

## Risk Scoring

### Scoring Methodology

Powernode calculates vendor risk scores (0-100, lower is better):

```yaml
Risk Score Components:

  Security Posture (30%):
    - Certifications (SOC 2, ISO 27001)
    - Assessment responses
    - Penetration test results
    - Vulnerability history

  Compliance Status (25%):
    - Document currency
    - Questionnaire completion
    - Audit findings
    - Regulatory compliance

  Financial Stability (20%):
    - Credit rating
    - Company age
    - Funding status
    - Revenue stability

  Incident History (15%):
    - Past breaches
    - Response times
    - Remediation quality
    - Public disclosures

  Geographic Risk (10%):
    - Data residency
    - Legal jurisdiction
    - Political stability
    - Regulatory environment
```

### Score Interpretation

| Score Range | Risk Level | Action Required |
|-------------|------------|-----------------|
| 0-30 | Low | Standard monitoring |
| 31-50 | Medium | Enhanced monitoring |
| 51-70 | High | Remediation plan required |
| 71-85 | Critical | Executive review |
| 86-100 | Unacceptable | Relationship review |

### Trend Analysis

Track risk scores over time:

```
Risk Score Trend: Acme Cloud Services

100 |
 80 |
 60 |     *
 40 | *       *   *
 20 |             *   *   *
  0 +---+---+---+---+---+---+
    Q1  Q2  Q3  Q4  Q1  Q2
    2023            2024

Current Score: 25 (Low Risk)
Trend: Improving (-15 points over 6 quarters)
```

## Periodic Reviews

### Review Scheduling

Configure automatic review schedules:

```yaml
Review Schedule by Tier:
  Critical:
    Frequency: Every 90 days
    Scope: Full reassessment
    Approver: Security Director

  High:
    Frequency: Every 180 days
    Scope: Standard assessment
    Approver: Security Manager

  Medium:
    Frequency: Annually
    Scope: Basic questionnaire
    Approver: IT Manager

  Low:
    Frequency: Every 2 years
    Scope: Minimal review
    Approver: Procurement
```

### Review Workflow

1. **Notification** - Vendor manager alerted of upcoming review
2. **Preparation** - Gather current documents and data
3. **Assessment** - Send questionnaire if needed
4. **Analysis** - Review responses and documents
5. **Scoring** - Calculate updated risk score
6. **Approval** - Route for appropriate sign-off
7. **Documentation** - Record findings and decisions
8. **Follow-up** - Track any remediation items

## Compliance Tracking

### Gap Analysis

Identify compliance gaps across vendors:

```yaml
Compliance Gap Report:

SOC 2 Type II Coverage:
  - Total Critical/High Vendors: 15
  - With Valid SOC 2: 12 (80%)
  - Expired: 2
  - Never Provided: 1

Missing Documents:
  - Acme Corp: Penetration Test (due 30 days ago)
  - Beta Inc: Insurance Certificate (expires in 15 days)
  - Gamma LLC: DPA not signed

Overdue Assessments:
  - Delta Services: Last assessed 400 days ago
  - Epsilon Tech: Assessment incomplete (45 days past due)
```

### Audit Reporting

Generate reports for auditors:

1. Navigate to **Supply Chain > Reports**
2. Select **Compliance Summary**
3. Choose time period and vendors
4. Export as PDF or CSV

```yaml
Audit Report Contents:
  - Executive summary
  - Vendor inventory with tiers
  - Risk score distribution
  - Assessment completion rates
  - Document currency status
  - Remediation tracking
  - Year-over-year comparison
```

## Best Practices

### Vendor Onboarding

1. **Pre-Assessment**
   - Evaluate before contract signing
   - Require minimum security standards
   - Define data access scope

2. **Contractual Requirements**
   - Include security addendum
   - Define breach notification SLAs
   - Require annual assessments
   - Include audit rights

3. **Initial Assessment**
   - Complete full questionnaire
   - Collect all required documents
   - Calculate baseline risk score
   - Set up monitoring

### Ongoing Management

1. **Continuous Monitoring**
   - Track public disclosures
   - Monitor news and alerts
   - Watch for breaches

2. **Relationship Management**
   - Regular check-in meetings
   - Security roadmap discussions
   - Collaborative remediation

3. **Exit Planning**
   - Data return procedures
   - Transition timelines
   - Alternative vendor identification

## Troubleshooting

### Assessment Issues

**Vendor Not Responding:**
- Send reminder emails
- Escalate to vendor management
- Consider business impact
- Document non-compliance

**Incomplete Submissions:**
- Identify missing items
- Provide clarification
- Extend deadline if justified
- Follow up directly

### Scoring Discrepancies

**Unexpected Score Change:**
- Review recent document changes
- Check questionnaire updates
- Verify data accuracy
- Audit calculation inputs

## Related Articles

- [Supply Chain Security Overview](/kb/supply-chain-security-overview)
- [SBOM Management and Analysis](/kb/sbom-management-analysis)

---

Need help with vendor assessments? Contact security@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "vendor-risk-assessment") do |article|
  article.title = "Vendor Risk Assessment"
  article.category = supply_chain_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Complete guide to vendor risk management including assessments, questionnaire templates, document tracking, risk scoring, and compliance monitoring."
  article.content = vendor_risk_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Vendor Risk Assessment"

puts "  ✅ Supply Chain Security articles created (3 articles)"
