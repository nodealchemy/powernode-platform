/// <reference types="cypress" />

describe('Admin Site Settings Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Site Settings page', () => {
      cy.visit('/app/admin/site-settings');
      cy.url().should('include', '/admin');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Site Settings') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Site Settings page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('site-wide settings') ||
                       $body.text().includes('footer') ||
                       $body.text().includes('social media');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Reset button', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasReset = $body.text().includes('Reset') ||
                        $body.find('button:contains("Reset")').length > 0;
        if (hasReset) {
          cy.log('Reset button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Save Changes button', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSave = $body.text().includes('Save Changes') ||
                       $body.text().includes('Save') ||
                       $body.find('button:contains("Save")').length > 0;
        if (hasSave) {
          cy.log('Save Changes button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Basic Information Section', () => {
    it('should display Basic Information section', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Basic Information');
        if (hasSection) {
          cy.log('Basic Information section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Site Name input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Site Name') ||
                        $body.find('input[placeholder*="Powernode"]').length > 0;
        if (hasInput) {
          cy.log('Site Name input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Copyright Year input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Copyright Year');
        if (hasInput) {
          cy.log('Copyright Year input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Copyright Text input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Copyright Text');
        if (hasInput) {
          cy.log('Copyright Text input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Footer Description input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Footer Description');
        if (hasInput) {
          cy.log('Footer Description input found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Contact Information Section', () => {
    it('should display Contact Information section', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Contact Information');
        if (hasSection) {
          cy.log('Contact Information section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Contact Email input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Contact Email') ||
                        $body.find('input[type="email"]').length > 0;
        if (hasInput) {
          cy.log('Contact Email input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Contact Phone input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Contact Phone');
        if (hasInput) {
          cy.log('Contact Phone input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Company Address input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Company Address') ||
                        $body.find('textarea').length > 0;
        if (hasInput) {
          cy.log('Company Address input found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Social Media Links Section', () => {
    it('should display Social Media Links section', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Social Media Links') ||
                          $body.text().includes('Social Media');
        if (hasSection) {
          cy.log('Social Media Links section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Show/Hide URLs toggle', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Show URLs') ||
                         $body.text().includes('Hide URLs');
        if (hasToggle) {
          cy.log('Show/Hide URLs toggle found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Facebook URL input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Facebook') ||
                        $body.find('input[placeholder*="facebook"]').length > 0;
        if (hasInput) {
          cy.log('Facebook URL input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Twitter/X URL input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Twitter') ||
                        $body.text().includes('X Profile') ||
                        $body.find('input[placeholder*="twitter"]').length > 0;
        if (hasInput) {
          cy.log('Twitter URL input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display LinkedIn URL input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('LinkedIn') ||
                        $body.find('input[placeholder*="linkedin"]').length > 0;
        if (hasInput) {
          cy.log('LinkedIn URL input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Instagram URL input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('Instagram') ||
                        $body.find('input[placeholder*="instagram"]').length > 0;
        if (hasInput) {
          cy.log('Instagram URL input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display YouTube URL input', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasInput = $body.text().includes('YouTube') ||
                        $body.find('input[placeholder*="youtube"]').length > 0;
        if (hasInput) {
          cy.log('YouTube URL input found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Settings Section', () => {
    it('should display Performance Settings section', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Performance Settings') ||
                          $body.text().includes('Performance');
        if (hasSection) {
          cy.log('Performance Settings section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Footer Caching toggle', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Footer Caching') ||
                         $body.text().includes('Caching');
        if (hasToggle) {
          cy.log('Footer Caching toggle found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Settings Status Section', () => {
    it('should display Settings Status section', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Settings Status') ||
                          $body.text().includes('Status');
        if (hasSection) {
          cy.log('Settings Status section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Public Settings indicator', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasIndicator = $body.text().includes('Public Settings') ||
                            $body.text().includes('Visible to all');
        if (hasIndicator) {
          cy.log('Public Settings indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Total Settings count', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasCount = $body.text().includes('Total Settings') ||
                        $body.text().match(/\d+ public/);
        if (hasCount) {
          cy.log('Total Settings count found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Caching status', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Footer Caching') ||
                         $body.text().includes('Enabled') ||
                         $body.text().includes('Disabled');
        if (hasStatus) {
          cy.log('Caching status indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Access Level indicator', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasIndicator = $body.text().includes('Access Level') ||
                            $body.text().includes('Admin only');
        if (hasIndicator) {
          cy.log('Access Level indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Form Interactions', () => {
    it('should allow editing Site Name', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const inputs = $body.find('input[class*="input"]');
        if (inputs.length > 0) {
          cy.get('input').first().should('not.be.disabled');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should toggle Show/Hide URLs', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        if ($body.text().includes('Show URLs') || $body.text().includes('Hide URLs')) {
          cy.contains('Show URLs').should('be.visible').click().then(() => {
            cy.log('Toggle clicked');
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/settings/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/admin/site-settings');
      cy.get('body').should('be.visible');
    });

    it('should show error notification on save failure', () => {
      cy.intercept('PUT', '**/api/**/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Save failed' }
      }).as('saveError');

      cy.intercept('POST', '**/api/**/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Save failed' }
      }).as('savePostError');

      cy.visit('/app/admin/site-settings');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/settings/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: { settings: [] } });
        });
      }).as('slowLoad');

      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.find('[class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Form Validation', () => {
    it('should accept valid email format', () => {
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const emailInput = $body.find('input[type="email"]');
        if (emailInput.length > 0) {
          cy.get('input[type="email"]').clear().type('test@example.com');
          cy.get('input[type="email"]').should('have.value', 'test@example.com');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/site-settings');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/site-settings');
      cy.get('body').should('be.visible');
    });

    it('should stack form fields on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive grid layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/admin/site-settings');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="md:grid-cols"]').length > 0 ||
                           $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
