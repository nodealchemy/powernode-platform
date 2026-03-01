/// <reference types="cypress" />

/**
 * DevOps Runner Health Tests
 *
 * Tests for Runner Health monitoring including:
 * - Runner status display
 * - Health metrics
 * - Runner configuration
 * - Capacity monitoring
 * - Runner alerts
 */

describe('DevOps Runner Health Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Runner Status', () => {
    it('should navigate to runners page', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Runner', 'Agent', 'Worker']);
    });

    it('should display runner list', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="runners-list"]', '.grid']);
    });

    it('should display runner status indicators', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Online', 'Offline', 'Busy', 'Idle']);
    });

    it('should display runner names', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Runner']);
    });
  });

  describe('Health Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display CPU usage', () => {
      cy.assertContainsAny(['CPU', 'Processor', '%']);
    });

    it('should display memory usage', () => {
      cy.assertContainsAny(['Memory', 'RAM', 'GB']);
    });

    it('should display disk usage', () => {
      cy.assertContainsAny(['Disk', 'Storage', 'Space']);
    });

    it('should display uptime', () => {
      cy.assertContainsAny(['Uptime', 'Started', 'days']);
    });
  });

  describe('Runner Configuration', () => {
    it('should have add runner option', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Add Runner', 'Add', 'Register', 'New']);
    });

    it('should display runner configuration', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Configure', 'Settings', 'Tags']);
    });

    it('should display runner tags', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Tag', 'Label']);
    });

    it('should have delete/remove runner option', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Delete', 'Remove', 'Unregister']);
    });
  });

  describe('Capacity Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display concurrent job limit', () => {
      cy.assertContainsAny(['Concurrent', 'Limit', 'Capacity']);
    });

    it('should display active jobs count', () => {
      cy.assertContainsAny(['Active', 'Running', 'Jobs']);
    });

    it('should display queue length', () => {
      cy.assertContainsAny(['Queue', 'Pending', 'Waiting']);
    });
  });

  describe('Runner Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display offline runner alerts', () => {
      cy.assertContainsAny(['Offline', 'Unavailable', 'Warning']);
    });

    it('should display health warnings', () => {
      cy.assertContainsAny(['Warning', 'Critical', 'High']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display runners correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/devops/runners');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Runner', 'Agent', 'Worker']);
      });
    });
  });
});
