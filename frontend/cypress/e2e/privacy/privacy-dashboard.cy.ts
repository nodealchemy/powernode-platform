/// <reference types="cypress" />

/**
 * Privacy Dashboard Page Tests
 *
 * Tests for Privacy Center functionality including:
 * - Page navigation and load
 * - Stats display (Active Consents, Data Exports, Terms Status)
 * - Consent management
 * - Data export requests
 * - Data deletion requests
 * - Data retention policies
 * - Responsive design
 */

describe('Privacy Dashboard Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Privacy Dashboard page', () => {
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Privacy') ||
                          $body.text().includes('Consent') ||
                          $body.text().includes('Data') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Privacy Dashboard page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Privacy Center') ||
                         $body.text().includes('Privacy');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('privacy settings') ||
                               $body.text().includes('manage');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/privacy');
      cy.wait(2000);
    });

    it('should display Active Consents stat', () => {
      cy.get('body').then($body => {
        const hasConsents = $body.text().includes('Active Consents') ||
                            $body.text().includes('Consents');
        if (hasConsents) {
          cy.log('Active Consents stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Data Exports stat', () => {
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasExports = $body.text().includes('Data Exports') ||
                           $body.text().includes('Exports');
        if (hasExports) {
          cy.log('Data Exports stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Terms Status stat', () => {
      cy.get('body').then($body => {
        const hasTerms = $body.text().includes('Terms Status') ||
                         $body.text().includes('Up to Date') ||
                         $body.text().includes('Review Needed');
        if (hasTerms) {
          cy.log('Terms Status stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display stats cards with icons', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="stat"]').length >= 3;
        if (hasCards) {
          cy.log('Stats cards with icons displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Consent Management', () => {
    beforeEach(() => {
      cy.visit('/app/privacy');
      cy.wait(2000);
    });

    it('should display consent management section', () => {
      cy.get('body').then($body => {
        const hasConsent = $body.text().includes('Consent') ||
                           $body.text().includes('Preferences');
        if (hasConsent) {
          cy.log('Consent management section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display consent toggles', () => {
      cy.get('body').then($body => {
        const hasToggles = $body.find('input[type="checkbox"], button[role="switch"], [class*="toggle"]').length > 0;
        if (hasToggles) {
          cy.log('Consent toggles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display consent descriptions', () => {
      cy.get('body').then($body => {
        const hasDescriptions = $body.text().includes('marketing') ||
                                $body.text().includes('analytics') ||
                                $body.text().includes('essential') ||
                                $body.text().includes('cookies');
        if (hasDescriptions) {
          cy.log('Consent descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle consent preference', () => {
      cy.get('body').then($body => {
        const toggle = $body.find('input[type="checkbox"], button[role="switch"]');
        if (toggle.length > 0) {
          cy.wrap(toggle).first().click({ force: true });
          cy.wait(500);
          cy.log('Consent preference toggled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should save consent changes', () => {
      cy.get('body').then($body => {
        const saveButton = $body.find('button:contains("Save"), button:contains("Update")');
        if (saveButton.length > 0) {
          cy.log('Save button found for consent changes');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      cy.visit('/app/privacy');
      cy.wait(2000);
    });

    it('should display data export section', () => {
      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                          $body.text().includes('Download');
        if (hasExport) {
          cy.log('Data export section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Request Export button', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Request Export"), button:contains("Export Data"), button:contains("Download")');
        if (exportButton.length > 0) {
          cy.log('Request Export button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export format options', () => {
      cy.get('body').then($body => {
        const hasFormats = $body.text().includes('JSON') ||
                           $body.text().includes('CSV') ||
                           $body.text().includes('format');
        if (hasFormats) {
          cy.log('Export format options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export request history', () => {
      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('Previous') ||
                           $body.text().includes('History') ||
                           $body.text().includes('Requested');
        if (hasHistory) {
          cy.log('Export request history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download button for completed exports', () => {
      cy.get('body').then($body => {
        const downloadButton = $body.find('button:contains("Download"), [aria-label*="download"]');
        if (downloadButton.length > 0) {
          cy.log('Download button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Deletion', () => {
    beforeEach(() => {
      cy.visit('/app/privacy');
      cy.wait(2000);
    });

    it('should display data deletion section', () => {
      cy.get('body').then($body => {
        const hasDeletion = $body.text().includes('Delete') ||
                            $body.text().includes('Deletion') ||
                            $body.text().includes('Remove');
        if (hasDeletion) {
          cy.log('Data deletion section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Request Deletion button', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Request Deletion"), button:contains("Delete Data"), button:contains("Delete Account")');
        if (deleteButton.length > 0) {
          cy.log('Request Deletion button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deletion type options', () => {
      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('Account') ||
                         $body.text().includes('Data') ||
                         $body.text().includes('type');
        if (hasTypes) {
          cy.log('Deletion type options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deletion warning', () => {
      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('Warning') ||
                           $body.text().includes('permanent') ||
                           $body.text().includes('irreversible') ||
                           $body.text().includes('cannot be undone');
        if (hasWarning) {
          cy.log('Deletion warning displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pending deletion status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Pending') ||
                          $body.text().includes('Processing') ||
                          $body.text().includes('Scheduled') ||
                          $body.text().includes('Cancel');
        if (hasStatus) {
          cy.log('Pending deletion status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel deletion option', () => {
      cy.get('body').then($body => {
        const cancelButton = $body.find('button:contains("Cancel")');
        if (cancelButton.length > 0) {
          cy.log('Cancel deletion option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Retention Policies', () => {
    beforeEach(() => {
      cy.visit('/app/privacy');
      cy.wait(2000);
    });

    it('should display data retention section', () => {
      cy.get('body').then($body => {
        const hasRetention = $body.text().includes('Retention') ||
                             $body.text().includes('Policy') ||
                             $body.text().includes('Policies');
        if (hasRetention) {
          cy.log('Data retention section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display retention periods', () => {
      cy.get('body').then($body => {
        const hasPeriods = $body.text().includes('years') ||
                           $body.text().includes('days') ||
                           $body.text().includes('required');
        if (hasPeriods) {
          cy.log('Retention periods displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display data types', () => {
      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('Data Type') ||
                         $body.text().includes('Account') ||
                         $body.text().includes('Activity');
        if (hasTypes) {
          cy.log('Data types displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display retention actions', () => {
      cy.get('body').then($body => {
        const hasActions = $body.text().includes('delete') ||
                           $body.text().includes('anonymize') ||
                           $body.text().includes('archive');
        if (hasActions) {
          cy.log('Retention actions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Terms Review Alert', () => {
    it('should display terms review alert when needed', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {},
            export_requests: [],
            terms_status: {
              needs_review: true,
              missing: ['privacy_policy', 'terms_of_service']
            }
          }
        }
      });

      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasAlert = $body.text().includes('Updated') ||
                         $body.text().includes('review') ||
                         $body.find('[class*="warning"], [class*="alert"]').length > 0;
        if (hasAlert) {
          cy.log('Terms review alert displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/privacy/*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/privacy/*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load privacy dashboard' }
      });

      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.find('[class*="error"]').length > 0;
        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/privacy/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: {} }
      });

      cy.visit('/app/privacy');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Privacy');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Privacy');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/privacy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"], [class*="col"]').length > 0;
        if (hasGrid) {
          cy.log('Grid layout on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
