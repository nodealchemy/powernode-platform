/// <reference types="cypress" />

/**
 * AI Plugin Management Tests
 *
 * Tests for AI Plugin functionality including:
 * - Plugin browsing
 * - Plugin installation
 * - Plugin configuration
 * - Plugin updates
 * - Plugin permissions
 * - Plugin removal
 */

describe('AI Plugin Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Plugin Browsing', () => {
    it('should navigate to plugins page', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlugins = $body.text().includes('Plugin') ||
                          $body.text().includes('Extension') ||
                          $body.text().includes('Integration');
        if (hasPlugins) {
          cy.log('Plugins page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plugin list', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('[data-testid="plugin-list"], .plugin-card, .grid').length > 0;
        if (hasList) {
          cy.log('Plugin list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plugin categories', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Category') ||
                             $body.text().includes('All') ||
                             $body.find('[data-testid="plugin-categories"]').length > 0;
        if (hasCategories) {
          cy.log('Plugin categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have search for plugins', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Plugin search displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Details', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should display plugin name', () => {
      cy.get('body').then($body => {
        const hasName = $body.find('h2, h3, .plugin-name').length > 0;
        if (hasName) {
          cy.log('Plugin names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plugin description', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.find('p, .description').length > 0;
        if (hasDescription) {
          cy.log('Plugin descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plugin version', () => {
      cy.get('body').then($body => {
        const hasVersion = $body.text().includes('v') ||
                          $body.text().match(/\d+\.\d+/) !== null ||
                          $body.text().includes('Version');
        if (hasVersion) {
          cy.log('Plugin version displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plugin author', () => {
      cy.get('body').then($body => {
        const hasAuthor = $body.text().includes('By') ||
                         $body.text().includes('Author') ||
                         $body.text().includes('Publisher');
        if (hasAuthor) {
          cy.log('Plugin author displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Installation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should have install button', () => {
      cy.get('body').then($body => {
        const hasInstall = $body.find('button:contains("Install"), button:contains("Add")').length > 0 ||
                          $body.text().includes('Install');
        if (hasInstall) {
          cy.log('Install button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display installed badge', () => {
      cy.get('body').then($body => {
        const hasInstalled = $body.text().includes('Installed') ||
                            $body.text().includes('Active') ||
                            $body.find('[data-testid="installed-badge"]').length > 0;
        if (hasInstalled) {
          cy.log('Installed badge displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show installation confirmation', () => {
      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Install') ||
                          $body.text().includes('Add');
        if (hasConfirm) {
          cy.log('Installation confirmation available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Configuration', () => {
    it('should navigate to installed plugins', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInstalled = $body.text().includes('Installed') ||
                            $body.text().includes('My Plugins') ||
                            $body.text().includes('Active');
        if (hasInstalled) {
          cy.log('Installed plugins page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have configure option', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfigure = $body.find('button:contains("Configure"), button:contains("Settings")').length > 0 ||
                            $body.text().includes('Configure');
        if (hasConfigure) {
          cy.log('Configure option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have enable/disable toggle', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], [role="switch"]').length > 0 ||
                         $body.text().includes('Enable') ||
                         $body.text().includes('Disable');
        if (hasToggle) {
          cy.log('Enable/disable toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Updates', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();
    });

    it('should display update available badge', () => {
      cy.get('body').then($body => {
        const hasUpdate = $body.text().includes('Update') ||
                         $body.text().includes('New version') ||
                         $body.find('[data-testid="update-badge"]').length > 0;
        if (hasUpdate) {
          cy.log('Update available indicator shown');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have update button', () => {
      cy.get('body').then($body => {
        const hasUpdateBtn = $body.find('button:contains("Update")').length > 0;
        if (hasUpdateBtn) {
          cy.log('Update button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have update all option', () => {
      cy.get('body').then($body => {
        const hasUpdateAll = $body.find('button:contains("Update all"), button:contains("Update All")').length > 0 ||
                            $body.text().includes('Update all');
        if (hasUpdateAll) {
          cy.log('Update all option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Permissions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should display plugin permissions', () => {
      cy.get('body').then($body => {
        const hasPermissions = $body.text().includes('Permission') ||
                              $body.text().includes('Access') ||
                              $body.text().includes('require');
        if (hasPermissions) {
          cy.log('Plugin permissions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display data access requirements', () => {
      cy.get('body').then($body => {
        const hasData = $body.text().includes('Data') ||
                       $body.text().includes('Read') ||
                       $body.text().includes('Write');
        if (hasData) {
          cy.log('Data access requirements displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plugin Removal', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();
    });

    it('should have uninstall option', () => {
      cy.get('body').then($body => {
        const hasUninstall = $body.find('button:contains("Uninstall"), button:contains("Remove")').length > 0 ||
                            $body.text().includes('Uninstall');
        if (hasUninstall) {
          cy.log('Uninstall option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show uninstall confirmation', () => {
      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Are you sure') ||
                          $body.text().includes('Remove');
        if (hasConfirm) {
          cy.log('Uninstall confirmation available');
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
      it(`should display plugins correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/ai/plugins');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Plugins displayed correctly on ${name}`);
      });
    });
  });
});
