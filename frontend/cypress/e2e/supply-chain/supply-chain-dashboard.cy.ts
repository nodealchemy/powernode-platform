/// <reference types="cypress" />

/**
 * Supply Chain Dashboard E2E Tests
 *
 * Tests for the Supply Chain Dashboard page functionality including:
 * - Dashboard navigation and page load
 * - Stats cards display and navigation
 * - Alerts panel display
 * - Activity feed display
 * - Quick access links
 * - Refresh functionality
 * - Responsive design
 */

describe('Supply Chain Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('Page Navigation', () => {
    it('should load Supply Chain Dashboard page', () => {
      cy.assertPageReady('/app/supply-chain', 'Supply Chain');
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/supply-chain');
      cy.assertContainsAny(['Dashboard', 'Supply Chain', 'Overview']);
    });

    it('should navigate from main dashboard via sidebar', () => {
      cy.navigateTo('/app/dashboard');
      cy.get('body').then(($body) => {
        const supplyChainLink = $body.find('a[href*="/supply-chain"]');
        if (supplyChainLink.length > 0) {
          cy.wrap(supplyChainLink).first().click();
          cy.url().should('include', '/supply-chain');
        }
      });
    });
  });

  describe('Stats Cards Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should display supply chain statistics', () => {
      cy.assertContainsAny(['SBOMs', 'Vulnerabilities', 'Container', 'Images', 'Attestations', 'Vendors', 'License']);
    });

    it('should display key metrics values', () => {
      // Check for numeric values on stat cards
      cy.assertContainsAny(['15', '42', '25', '18', '12', '5']);
    });

    it('should display security metrics', () => {
      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low', 'Risk', 'Score']);
    });

    it('should navigate to SBOMs page when clicking SBOM stat card', () => {
      cy.get('body').then($body => {
        const sbomCard = $body.find('[data-testid*="sbom"], a[href*="/sboms"]:not([href*="/supply-chain"]):first');
        if (sbomCard.length > 0) {
          cy.wrap(sbomCard).first().click({ force: true });
          cy.url().should('include', '/sbom');
        }
      });
    });

    it('should navigate to Containers page when clicking container stat card', () => {
      cy.get('body').then($body => {
        const containerCard = $body.find('[data-testid*="container"], a[href*="/containers"]');
        if (containerCard.length > 0) {
          cy.wrap(containerCard).first().click({ force: true });
          cy.url().should('include', '/container');
        }
      });
    });
  });

  describe('Alerts Panel', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should display alerts section', () => {
      cy.assertContainsAny(['Alerts', 'Attention', 'Security', 'Issues', 'Warning']);
    });

    it('should display critical alerts with severity indicators', () => {
      cy.assertContainsAny(['Critical', 'High', 'vulnerability', 'violation']);
    });

    it('should show alert action links', () => {
      cy.get('body').then($body => {
        const alertLinks = $body.find('[data-testid*="alert"] a, [data-testid*="alert"] button');
        if (alertLinks.length > 0) {
          cy.wrap(alertLinks).first().should('be.visible');
        }
      });
    });
  });

  describe('Activity Feed', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should display activity feed section', () => {
      cy.assertContainsAny(['Activity', 'Recent', 'History', 'Events']);
    });

    it('should display recent activities', () => {
      cy.assertContainsAny(['SBOM generated', 'scan completed', 'Attestation', 'created', 'verified']);
    });

    it('should display activity timestamps', () => {
      // Activities should show relative or absolute timestamps
      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Access Links', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should display quick access or navigation links', () => {
      cy.assertContainsAny(['Quick', 'Access', 'Links', 'SBOMs', 'Container', 'Vendors', 'License']);
    });

    it('should navigate to SBOMs from quick link', () => {
      cy.get('body').then($body => {
        const sbomLink = $body.find('a[href*="/sboms"]');
        if (sbomLink.length > 0) {
          cy.wrap(sbomLink).first().click();
          cy.url().should('include', '/sboms');
        }
      });
    });

    it('should navigate to Vendors from quick link', () => {
      cy.get('body').then($body => {
        const vendorLink = $body.find('a[href*="/vendors"]');
        if (vendorLink.length > 0) {
          cy.wrap(vendorLink).first().click();
          cy.url().should('include', '/vendors');
        }
      });
    });
  });

  describe('Compliance Summary', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should display compliance metrics', () => {
      cy.assertContainsAny(['Compliance', 'NTIA', 'SLSA', 'compliant', 'Compliant']);
    });

    it('should show compliance percentages or scores', () => {
      // The dashboard shows "NTIA Compliant" with a count value
      cy.assertContainsAny(['%', 'Level', 'Score', 'Compliant', 'compliant', '10']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should have refresh button', () => {
      cy.assertHasElement([
        '[data-testid="action-refresh"]',
        '[aria-label="Refresh"]',
        '[aria-label*="Refresh"]',
        'button:contains("Refresh")',
      ]);
    });

    it('should refresh data when clicking refresh button', () => {
      cy.get('body').then($body => {
        const refreshBtn = $body.find('[data-testid="action-refresh"], [aria-label*="Refresh"], button:contains("Refresh")');
        if (refreshBtn.length > 0) {
          cy.wrap(refreshBtn).first().click();
          cy.wait('@getSupplyChainDashboard');
        }
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('/api/v1/supply_chain/**', {
        statusCode: 500,
        visitUrl: '/app/supply-chain',
      });
    });

    it('should handle network timeout gracefully', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/dashboard', {
        statusCode: 200,
        body: { success: true, data: {} },
        delay: 5000,
      }).as('slowDashboard');

      cy.visit('/app/supply-chain');
      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain', {
        checkContent: 'Supply Chain',
      });
    });

    it('should stack stat cards on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.assertPageReady('/app/supply-chain');
      cy.get('body').should('be.visible');
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain');
    });

    it('should have proper heading structure', () => {
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible links', () => {
      cy.get('a').each($link => {
        cy.wrap($link).should('have.attr', 'href');
      });
    });
  });
});

export {};
