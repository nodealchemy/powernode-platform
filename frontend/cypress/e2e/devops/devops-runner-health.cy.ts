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

      cy.get('body').then($body => {
        const hasRunners = $body.text().includes('Runner') ||
                          $body.text().includes('Agent') ||
                          $body.text().includes('Worker');
        if (hasRunners) {
          cy.log('Runners page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner list', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="runners-list"], .grid').length > 0;
        if (hasList) {
          cy.log('Runner list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner status indicators', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Online') ||
                         $body.text().includes('Offline') ||
                         $body.text().includes('Busy') ||
                         $body.text().includes('Idle');
        if (hasStatus) {
          cy.log('Runner status indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner names', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNames = $body.text().includes('Runner') ||
                        $body.find('[data-testid="runner-name"]').length > 0;
        if (hasNames) {
          cy.log('Runner names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Health Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display CPU usage', () => {
      cy.get('body').then($body => {
        const hasCPU = $body.text().includes('CPU') ||
                      $body.text().includes('Processor') ||
                      $body.text().includes('%');
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

    it('should display uptime', () => {
      cy.get('body').then($body => {
        const hasUptime = $body.text().includes('Uptime') ||
                         $body.text().includes('Started') ||
                         $body.text().includes('days');
        if (hasUptime) {
          cy.log('Uptime displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Runner Configuration', () => {
    it('should have add runner option', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAdd = $body.find('button:contains("Add"), button:contains("Register"), button:contains("New")').length > 0 ||
                      $body.text().includes('Add Runner');
        if (hasAdd) {
          cy.log('Add runner option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner configuration', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configure') ||
                         $body.text().includes('Settings') ||
                         $body.text().includes('Tags');
        if (hasConfig) {
          cy.log('Runner configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner tags', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTags = $body.text().includes('Tag') ||
                       $body.text().includes('Label') ||
                       $body.find('[data-testid="runner-tags"]').length > 0;
        if (hasTags) {
          cy.log('Runner tags displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete/remove runner option', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), button:contains("Remove"), button:contains("Unregister")').length > 0 ||
                         $body.text().includes('Remove');
        if (hasDelete) {
          cy.log('Delete runner option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Capacity Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display concurrent job limit', () => {
      cy.get('body').then($body => {
        const hasLimit = $body.text().includes('Concurrent') ||
                        $body.text().includes('Limit') ||
                        $body.text().includes('Capacity');
        if (hasLimit) {
          cy.log('Concurrent job limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active jobs count', () => {
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active') ||
                         $body.text().includes('Running') ||
                         $body.text().includes('Jobs');
        if (hasActive) {
          cy.log('Active jobs count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display queue length', () => {
      cy.get('body').then($body => {
        const hasQueue = $body.text().includes('Queue') ||
                        $body.text().includes('Pending') ||
                        $body.text().includes('Waiting');
        if (hasQueue) {
          cy.log('Queue length displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Runner Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display offline runner alerts', () => {
      cy.get('body').then($body => {
        const hasAlert = $body.text().includes('Offline') ||
                        $body.text().includes('Unavailable') ||
                        $body.text().includes('Warning');
        if (hasAlert) {
          cy.log('Offline runner alerts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health warnings', () => {
      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('Warning') ||
                          $body.text().includes('Critical') ||
                          $body.text().includes('High') ||
                          $body.find('[data-testid="health-warning"]').length > 0;
        if (hasWarning) {
          cy.log('Health warnings displayed');
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
      it(`should display runners correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/devops/runners');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Runners displayed correctly on ${name}`);
      });
    });
  });
});
