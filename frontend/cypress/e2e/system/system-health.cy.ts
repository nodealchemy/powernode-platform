/// <reference types="cypress" />

/**
 * System Health Tests
 *
 * Tests for System Health monitoring including:
 * - Health dashboard
 * - Service status
 * - Database health
 * - API health
 * - Queue status
 * - Resource monitoring
 */

describe('System Health Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Health Dashboard', () => {
    it('should navigate to system health page', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Health', 'Status', 'System']);
    });

    it('should display overall system status', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Healthy', 'Operational', 'OK', 'Degraded']);
    });

    it('should display health indicators', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="health-indicator"]', '.status-indicator', '.health-badge']);
    });
  });

  describe('Service Status', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display API service status', () => {
      cy.assertContainsAny(['API', 'Backend', 'Server']);
    });

    it('should display database status', () => {
      cy.assertContainsAny(['Database', 'PostgreSQL', 'DB']);
    });

    it('should display cache status', () => {
      cy.assertContainsAny(['Cache', 'Redis', 'Memory']);
    });

    it('should display queue/worker status', () => {
      cy.assertContainsAny(['Queue', 'Worker', 'Sidekiq', 'Job']);
    });
  });

  describe('Resource Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display CPU usage', () => {
      cy.assertContainsAny(['CPU', 'Processor']);
    });

    it('should display memory usage', () => {
      cy.assertContainsAny(['Memory', 'RAM', 'GB']);
    });

    it('should display disk usage', () => {
      cy.assertContainsAny(['Disk', 'Storage', 'Space']);
    });
  });

  describe('Health History', () => {
    it('should display health history', () => {
      cy.visit('/app/admin/system/health/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Past', 'Incident']);
    });

    it('should display uptime percentage', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Uptime', '%', '99']);
    });
  });

  describe('Health Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display health alerts', () => {
      cy.assertContainsAny(['Alert', 'Warning', 'Critical']);
    });

    it('should have alert configuration option', () => {
      cy.assertContainsAny(['Configure', 'Settings']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display system health correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/admin/system/health');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Health', 'Status', 'System']);
        cy.log(`System health displayed correctly on ${name}`);
      });
    });
  });
});
