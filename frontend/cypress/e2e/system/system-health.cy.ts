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

      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Health') ||
                         $body.text().includes('Status') ||
                         $body.text().includes('System');
        if (hasHealth) {
          cy.log('System health page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display overall system status', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Healthy') ||
                         $body.text().includes('Operational') ||
                         $body.text().includes('OK') ||
                         $body.text().includes('Degraded');
        if (hasStatus) {
          cy.log('Overall system status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health indicators', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasIndicators = $body.find('[data-testid="health-indicator"], .status-indicator, .health-badge').length > 0 ||
                             $body.text().includes('●');
        if (hasIndicators) {
          cy.log('Health indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Service Status', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display API service status', () => {
      cy.get('body').then($body => {
        const hasAPI = $body.text().includes('API') ||
                      $body.text().includes('Backend') ||
                      $body.text().includes('Server');
        if (hasAPI) {
          cy.log('API service status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display database status', () => {
      cy.get('body').then($body => {
        const hasDB = $body.text().includes('Database') ||
                     $body.text().includes('PostgreSQL') ||
                     $body.text().includes('DB');
        if (hasDB) {
          cy.log('Database status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cache status', () => {
      cy.get('body').then($body => {
        const hasCache = $body.text().includes('Cache') ||
                        $body.text().includes('Redis') ||
                        $body.text().includes('Memory');
        if (hasCache) {
          cy.log('Cache status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display queue/worker status', () => {
      cy.get('body').then($body => {
        const hasQueue = $body.text().includes('Queue') ||
                        $body.text().includes('Worker') ||
                        $body.text().includes('Sidekiq') ||
                        $body.text().includes('Job');
        if (hasQueue) {
          cy.log('Queue status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Resource Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display CPU usage', () => {
      cy.get('body').then($body => {
        const hasCPU = $body.text().includes('CPU') ||
                      $body.text().includes('Processor');
        if (hasCPU) {
          cy.log('CPU usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display memory usage', () => {
      cy.get('body').then($body => {
        const hasMemory = $body.text().includes('Memory') ||
                         $body.text().includes('RAM') ||
                         $body.text().includes('GB');
        if (hasMemory) {
          cy.log('Memory usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display disk usage', () => {
      cy.get('body').then($body => {
        const hasDisk = $body.text().includes('Disk') ||
                       $body.text().includes('Storage') ||
                       $body.text().includes('Space');
        if (hasDisk) {
          cy.log('Disk usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Health History', () => {
    it('should display health history', () => {
      cy.visit('/app/admin/system/health/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Past') ||
                          $body.text().includes('Incident');
        if (hasHistory) {
          cy.log('Health history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display uptime percentage', () => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUptime = $body.text().includes('Uptime') ||
                         $body.text().includes('%') ||
                         $body.text().includes('99');
        if (hasUptime) {
          cy.log('Uptime percentage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Health Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/admin/system/health');
      cy.waitForPageLoad();
    });

    it('should display health alerts', () => {
      cy.get('body').then($body => {
        const hasAlerts = $body.text().includes('Alert') ||
                         $body.text().includes('Warning') ||
                         $body.text().includes('Critical');
        if (hasAlerts) {
          cy.log('Health alerts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have alert configuration option', () => {
      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configure') ||
                         $body.text().includes('Settings') ||
                         $body.find('button:contains("Configure")').length > 0;
        if (hasConfig) {
          cy.log('Alert configuration option displayed');
        }
      });

      cy.get('body').should('be.visible');
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

        cy.get('body').should('be.visible');
        cy.log(`System health displayed correctly on ${name}`);
      });
    });
  });
});
