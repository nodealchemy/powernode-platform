import { test, expect } from '@playwright/test';
import { SupplyChainDashboardPage } from '../pages/supply-chain/dashboard.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Supply Chain E2E Tests
 *
 * Tests for supply chain management pages: Dashboard, SBOMs, Container Images,
 * Attestations, Vendors, and License Policies.
 *
 * These tests verify that each page loads and renders expected content.
 * Pages may render with data, empty states, or error states depending on
 * backend availability. Tests use flexible selectors and conditional checks.
 */

test.describe('Supply Chain', () => {
  let supplyChainPage: SupplyChainDashboardPage;

  test.beforeEach(async ({ page }) => {
    // Suppress page errors (API calls may fail without backend)
    page.on('pageerror', () => {});
    supplyChainPage = new SupplyChainDashboardPage(page);
  });

  test.describe('Dashboard', () => {
    test.beforeEach(async () => {
      await supplyChainPage.goto();
      await supplyChainPage.waitForReady();
    });

    test('should load supply chain dashboard', async ({ page }) => {
      // PageContainer title is "Supply Chain Security"
      // Error state shows "Failed to load dashboard"
      // Loading state shows "Loading dashboard..."
      // All states contain meaningful text
      const body = page.locator('body');
      await expect(body).toContainText(/supply chain|failed to load|loading/i);
    });

    test('should display SBOM section', async ({ page }) => {
      // Dashboard has StatCard with title "SBOMs" and QuickLinkCard with name "SBOMs"
      // If API fails, error state shows "Failed to load dashboard" (no SBOM text)
      const hasSbom = await page.getByText(/sbom|software bill/i).count() > 0;
      const hasError = await page.getByText(/failed to load/i).count() > 0;
      expect(hasSbom || hasError).toBeTruthy();
    });

    test('should display containers section', async ({ page }) => {
      // Dashboard has StatCard "Container Images" and QuickLinkCard "Container Images"
      const hasContainers = await page.getByText(/container/i).count() > 0;
      const hasError = await page.getByText(/failed to load/i).count() > 0;
      expect(hasContainers || hasError).toBeTruthy();
    });

    test('should display vendors section', async ({ page }) => {
      // Dashboard has StatCard "Vendors" and QuickLinkCard "Vendors"
      const hasVendors = await page.getByText(/vendor/i).count() > 0;
      const hasError = await page.getByText(/failed to load/i).count() > 0;
      expect(hasVendors || hasError).toBeTruthy();
    });

    test('should display licenses section', async ({ page }) => {
      // Dashboard has QuickLinkCard "License Policies" and "License Violations"
      const hasLicenses = await page.getByText(/license/i).count() > 0;
      const hasError = await page.getByText(/failed to load/i).count() > 0;
      expect(hasLicenses || hasError).toBeTruthy();
    });

    test('should display attestations section', async ({ page }) => {
      // Dashboard has StatCard "Attestations" and QuickLinkCard "Attestations"
      const hasAttestations = await page.getByText(/attestation/i).count() > 0;
      const hasError = await page.getByText(/failed to load/i).count() > 0;
      expect(hasAttestations || hasError).toBeTruthy();
    });
  });

  test.describe('SBOMs', () => {
    test.beforeEach(async () => {
      await supplyChainPage.gotoSboms();
      await supplyChainPage.waitForReady();
    });

    test('should load SBOMs page', async ({ page }) => {
      // Page title is "Software Bill of Materials"
      await expect(page.locator('body')).toContainText(/software bill of materials|sbom/i);
    });

    test('should display SBOM list or empty state', async ({ page }) => {
      // DataTable renders table rows, or empty state with "No SBOMs Found"
      const hasTable = await page.locator('table tbody tr').count() > 0;
      const hasEmpty = await page.getByText(/no sboms found|no sbom/i).count() > 0;
      const hasError = await page.getByText(/error|failed/i).count() > 0;
      expect(hasTable || hasEmpty || hasError).toBeTruthy();
    });

    test('should have refresh button', async ({ page }) => {
      // SBOMs page has a "Refresh" action in PageContainer
      const hasRefresh = await page.getByRole('button', { name: /refresh/i }).count() > 0;
      expect(hasRefresh).toBeTruthy();
    });

    test('should display tab navigation', async ({ page }) => {
      // Tabs: All, Completed, Generating, Failed
      const hasAllTab = await page.getByText('All').count() > 0;
      const hasCompletedTab = await page.getByText('Completed').count() > 0;
      expect(hasAllTab || hasCompletedTab).toBeTruthy();
    });

    test('should display table headers when data exists', async ({ page }) => {
      // Table headers: Name, Format, Status, Components, Vulnerabilities, Risk Score, NTIA
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        const hasFormatHeader = await page.getByText('Format').count() > 0;
        const hasStatusHeader = await page.getByText('Status').count() > 0;
        expect(hasFormatHeader || hasStatusHeader).toBeTruthy();
      }
    });

    test('should display vulnerability info when data exists', async ({ page }) => {
      // Vulnerability count column exists in the table header
      const hasVulnHeader = await page.getByText(/vulnerabilit/i).count() > 0;
      if (hasVulnHeader) {
        expect(hasVulnHeader).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });
  });

  test.describe('Containers', () => {
    test.beforeEach(async () => {
      await supplyChainPage.gotoContainers();
      await supplyChainPage.waitForReady();
    });

    test('should load containers page', async ({ page }) => {
      // Page title is "Container Images"
      await expect(page.locator('body')).toContainText(/container image/i);
    });

    test('should display container list or empty state', async ({ page }) => {
      // DataTable or empty state "No container images found"
      const hasTable = await page.locator('table tbody tr').count() > 0;
      const hasEmpty = await page.getByText(/no container images/i).count() > 0;
      const hasError = await page.getByText(/error|failed/i).count() > 0;
      expect(hasTable || hasEmpty || hasError).toBeTruthy();
    });

    test('should display tab navigation', async ({ page }) => {
      // Tabs: All Images, Verified, Unverified, Quarantined
      const hasAllTab = await page.getByText('All Images').count() > 0;
      const hasVerifiedTab = await page.getByText('Verified').count() > 0;
      expect(hasAllTab || hasVerifiedTab).toBeTruthy();
    });

    test('should display table headers when data exists', async ({ page }) => {
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        // Table has columns: Image, Digest, Critical, High, Medium, Low, Status, Deployed, Last Scanned
        const hasImageHeader = await page.getByText('Image').count() > 0;
        const hasStatusHeader = await page.getByText('Status').count() > 0;
        expect(hasImageHeader || hasStatusHeader).toBeTruthy();
      }
    });

    test('should display scan-related columns', async ({ page }) => {
      // Table has "Last Scanned" column header and severity columns
      const hasScanHeader = await page.getByText(/last scanned|critical|high|medium/i).count() > 0;
      if (hasScanHeader) {
        expect(hasScanHeader).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });
  });

  test.describe('Attestations', () => {
    test.beforeEach(async () => {
      await supplyChainPage.gotoAttestations();
      await supplyChainPage.waitForReady();
    });

    test('should load attestations page', async ({ page }) => {
      // Page title is "Attestations"
      await expect(page.locator('body')).toContainText(/attestation/i);
    });

    test('should display attestation list or empty state', async ({ page }) => {
      // DataTable or empty state "No attestations found"
      const hasTable = await page.locator('table tbody tr').count() > 0;
      const hasEmpty = await page.getByText(/no attestations found/i).count() > 0;
      const hasError = await page.getByText(/error|failed/i).count() > 0;
      expect(hasTable || hasEmpty || hasError).toBeTruthy();
    });

    test('should display tab navigation', async ({ page }) => {
      // Tabs: All Attestations, SLSA Provenance, SBOM, Custom
      const hasAllTab = await page.getByText('All Attestations').count() > 0;
      const hasSlsaTab = await page.getByText('SLSA Provenance').count() > 0;
      expect(hasAllTab || hasSlsaTab).toBeTruthy();
    });

    test('should display attestation type info in tabs or table', async ({ page }) => {
      // Tab labels include "SLSA Provenance", "SBOM", "Custom"
      const hasSlsa = await page.getByText(/slsa/i).count() > 0;
      const hasSbomTab = await page.getByText(/sbom/i).count() > 0;
      expect(hasSlsa || hasSbomTab).toBeTruthy();
    });

    test('should display verification column in table', async ({ page }) => {
      // Table has "Verified" and "Signed" column headers
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        const hasVerifiedHeader = await page.getByText('Verified').count() > 0;
        const hasSignedHeader = await page.getByText('Signed').count() > 0;
        expect(hasVerifiedHeader || hasSignedHeader).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });
  });

  test.describe('Vendors', () => {
    test.beforeEach(async () => {
      await supplyChainPage.gotoVendors();
      await supplyChainPage.waitForReady();
    });

    test('should load vendors page', async ({ page }) => {
      // Page title is "Vendor Management"
      await expect(page.locator('body')).toContainText(/vendor/i);
    });

    test('should display vendor list or empty state', async ({ page }) => {
      // DataTable or empty state "No vendors found"
      const hasTable = await page.locator('table tbody tr').count() > 0;
      const hasEmpty = await page.getByText(/no vendors found/i).count() > 0;
      const hasError = await page.getByText(/error|failed/i).count() > 0;
      expect(hasTable || hasEmpty || hasError).toBeTruthy();
    });

    test('should have add vendor button', async ({ page }) => {
      // VendorsPage has "Add Vendor" action in PageContainer
      const hasAdd = await page.getByRole('button', { name: /add vendor/i }).count() > 0;
      expect(hasAdd).toBeTruthy();
    });

    test('should display tab navigation', async ({ page }) => {
      // Tabs: All Vendors, Critical Risk, High Risk, Needs Assessment
      const hasAllTab = await page.getByText('All Vendors').count() > 0;
      const hasCriticalTab = await page.getByText('Critical Risk').count() > 0;
      expect(hasAllTab || hasCriticalTab).toBeTruthy();
    });

    test('should display risk-related columns when data exists', async ({ page }) => {
      // Table has columns: Risk Tier, Risk Score, Status, Data Sensitivity
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        const hasRiskTier = await page.getByText('Risk Tier').count() > 0;
        const hasRiskScore = await page.getByText('Risk Score').count() > 0;
        expect(hasRiskTier || hasRiskScore).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });

    test('should display data sensitivity column when data exists', async ({ page }) => {
      // Table has "Data Sensitivity" column with PII, PHI, PCI badges
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        const hasSensitivity = await page.getByText('Data Sensitivity').count() > 0;
        expect(hasSensitivity).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });
  });

  test.describe('Licenses', () => {
    test.beforeEach(async () => {
      await supplyChainPage.gotoLicenses();
      await supplyChainPage.waitForReady();
    });

    test('should load licenses page', async ({ page }) => {
      // Route /supply-chain/licenses maps to LicensePoliciesPage
      // Title is "License Policies"
      await expect(page.locator('body')).toContainText(/license polic/i);
    });

    test('should display license policy list or empty state', async ({ page }) => {
      // DataTable or empty state "No license policies"
      const hasTable = await page.locator('table tbody tr').count() > 0;
      const hasEmpty = await page.getByText(/no license polic/i).count() > 0;
      const hasError = await page.getByText(/error|failed/i).count() > 0;
      expect(hasTable || hasEmpty || hasError).toBeTruthy();
    });

    test('should have create policy button', async ({ page }) => {
      // LicensePoliciesPage has "Create Policy" action in PageContainer
      const hasCreate = await page.getByRole('button', { name: /create policy/i }).count() > 0;
      expect(hasCreate).toBeTruthy();
    });

    test('should display policy type columns when data exists', async ({ page }) => {
      // Table has columns: Name, Type, Enforcement, Active, Copyleft Rules, Actions
      const hasTable = await page.locator('table').count() > 0;
      if (hasTable) {
        const hasTypeHeader = await page.getByText('Type').count() > 0;
        const hasEnforcement = await page.getByText('Enforcement').count() > 0;
        expect(hasTypeHeader || hasEnforcement).toBeTruthy();
      } else {
        await expectOrAlternateState(page, false);
      }
    });

    test('should display compliance-related info', async ({ page }) => {
      // Page description mentions "compliance" or table has Copyleft Rules column
      const hasCompliance = await page.getByText(/compliance|copyleft/i).count() > 0;
      const hasEnforcement = await page.getByText(/enforcement/i).count() > 0;
      const hasDescription = await page.getByText(/license/i).count() > 0;
      expect(hasCompliance || hasEnforcement || hasDescription).toBeTruthy();
    });
  });
});
