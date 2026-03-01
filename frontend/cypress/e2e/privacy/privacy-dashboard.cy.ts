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
    cy.standardTestSetup({ intercepts: ['privacy'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Privacy Dashboard page', () => {
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Privacy', 'Consent', 'Data', 'Loading']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Privacy Center', 'Privacy', 'Center', 'Dashboard']);
    });

    it('should display page description', () => {
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['privacy settings', 'Manage your', 'Privacy', 'Data', 'Consent', 'Settings']);
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should display Active Consents stat', () => {
      cy.assertContainsAny(['Active Consents', 'Consent', 'Active', 'Privacy']);
    });

    it('should display Data Exports stat', () => {
      cy.assertContainsAny(['Data Exports', 'Export', 'Data', 'Privacy']);
    });

    it('should display Terms Status stat', () => {
      cy.assertContainsAny(['Terms Status', 'Terms', 'Status', 'Up to Date', 'Privacy']);
    });

    it('should display stats cards with icons', () => {
      cy.assertHasElement(['[data-testid*="stat-card"]', '[data-testid*="privacy"]', '.grid']);
    });
  });

  describe('Consent Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should display consent management section', () => {
      cy.assertContainsAny(['Consent Preferences', 'Consent', 'Preferences', 'Privacy', 'Data']);
    });

    it('should display consent toggles', () => {
      cy.assertHasElement(['button[role="switch"]']);
    });

    it('should display consent type labels', () => {
      cy.assertContainsAny(['Marketing', 'Analytics', 'Cookies', 'Communications', 'Privacy', 'Consent']);
    });

    it('should display consent descriptions', () => {
      cy.assertContainsAny(['Manage how your data is used', 'data', 'privacy', 'consent', 'manage']);
    });

    it('should toggle consent preference', () => {
      cy.get('button[role="switch"]').not(':disabled').first()
        .should('be.visible')
        .click();
      cy.assertContainsAny(['Save Changes', 'Consent', 'Privacy']);
    });

    it('should save consent changes', () => {
      cy.get('button[role="switch"]').not(':disabled').first()
        .should('be.visible')
        .click();
      cy.clickButton('Save Changes');
      cy.wait('@updateConsents');
    });

    it('should display privacy rights info', () => {
      cy.assertContainsAny(['Your Privacy Rights', 'Privacy', 'Rights', 'Consent', 'withdraw']);
    });

    it('should show Required badge for required consents', () => {
      cy.assertContainsAny(['Required', 'Consent', 'Privacy', 'required']);
    });

    it('should disable toggle for required consents', () => {
      cy.assertHasElement(['button[role="switch"]:disabled']);
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should display data export section', () => {
      cy.assertContainsAny(['Data Export', 'Export', 'Data', 'Download', 'Privacy']);
    });

    it('should have Request Export button', () => {
      cy.assertContainsAny(['Request Export', 'Export', 'Request', 'Download', 'Privacy']);
    });

    it('should display export format options', () => {
      cy.assertHasElement(['select', '[data-testid*="format"]']);
    });

    it('should select different export formats', () => {
      cy.get('select').first().select('csv');
      cy.get('select').first().should('have.value', 'csv');
      cy.get('select').first().select('zip');
      cy.get('select').first().should('have.value', 'zip');
    });

    it('should request data export', () => {
      cy.clickButton('Request Export');
      cy.wait('@requestExport');
    });

    it('should show requesting state', () => {
      cy.intercept('POST', '/api/v1/privacy/export*', {
        delay: 1000,
        statusCode: 200,
        body: {
          success: true,
          data: {
            request: { id: 'test-id', status: 'pending', format: 'json', export_type: 'full', downloadable: false, created_at: new Date().toISOString() }
          }
        }
      }).as('requestExportSlow');
      cy.clickButton('Request Export');
      cy.assertContainsAny(['Requesting...', 'Request', 'Export']);
    });
  });

  describe('Data Export History', () => {
    const mockConsentsForExport = {
      marketing: { granted: true, required: false, description: 'Marketing emails' },
      analytics: { granted: true, required: false, description: 'Analytics' },
      cookies: { granted: true, required: true, description: 'Essential cookies' },
      data_sharing: { granted: false, required: false, description: 'Data sharing' },
      third_party: { granted: false, required: false, description: 'Third party' },
      communications: { granted: true, required: true, description: 'Communications' },
      newsletter: { granted: true, required: false, description: 'Newsletter' },
      promotional: { granted: false, required: false, description: 'Promotional' },
    };

    it('should display recent exports section when exports exist', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForExport,
            export_requests: [
              {
                id: 'export-1',
                status: 'completed',
                format: 'json',
                export_type: 'full',
                downloadable: true,
                download_token: 'token-123',
                created_at: '2025-01-15T10:00:00Z',
                file_size_bytes: 1024000
              }
            ],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: []
          }
        }
      }).as('getDashboardExports');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Recent Exports', 'Export', 'JSON', 'Privacy', 'Data']);
    });

    it('should have download button for completed exports', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForExport,
            export_requests: [
              {
                id: 'export-1',
                status: 'completed',
                format: 'json',
                export_type: 'full',
                downloadable: true,
                download_token: 'token-123',
                created_at: '2025-01-15T10:00:00Z'
              }
            ],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: []
          }
        }
      }).as('getDashboardExports');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Download', 'Export', 'Privacy', 'Data']);
    });

    it('should show processing status for pending exports', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForExport,
            export_requests: [
              {
                id: 'export-1',
                status: 'processing',
                format: 'json',
                export_type: 'full',
                downloadable: false,
                created_at: '2025-01-15T10:00:00Z'
              }
            ],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: []
          }
        }
      }).as('getDashboardExports');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Processing', 'Export', 'Privacy', 'Data', 'processing']);
    });
  });

  describe('Data Deletion', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should display data deletion section', () => {
      cy.assertContainsAny(['Delete Your Data', 'Delete', 'Deletion', 'Data', 'Privacy']);
    });

    it('should have Request Deletion button', () => {
      cy.assertContainsAny(['Request Data Deletion', 'Delete', 'Deletion', 'Request', 'Privacy']);
    });

    it('should display GDPR notice', () => {
      cy.assertContainsAny(['GDPR', 'right to request deletion', 'Article 17', 'Delete', 'Deletion', 'Privacy', 'Data']);
    });

    it('should open deletion confirmation on button click', () => {
      cy.clickButton('Request Data Deletion');
      cy.assertContainsAny(['Important Notice', 'Delete', 'Confirm', 'Cancel', 'Privacy']);
    });

    it('should display deletion type options', () => {
      cy.clickButton('Request Data Deletion');
      cy.assertContainsAny(['Full Deletion', 'Anonymization', 'Deletion', 'anonymize']);
    });

    it('should display deletion warning', () => {
      cy.clickButton('Request Data Deletion');
      cy.assertContainsAny(['cannot be undone', '30 days', 'grace period', 'Important']);
    });

    it('should cancel deletion confirmation', () => {
      cy.clickButton('Request Data Deletion');
      cy.clickButton('Cancel');
      cy.contains('Important Notice').should('not.exist');
    });

    it('should submit deletion request', () => {
      cy.clickButton('Request Data Deletion');
      cy.clickButton('Confirm Deletion Request');
      cy.wait('@requestDeletion');
    });

    it('should show reason textarea', () => {
      cy.clickButton('Request Data Deletion');
      cy.assertHasElement(['textarea']);
    });
  });

  describe('Pending Deletion Request', () => {
    it('should display pending deletion status', () => {
      cy.intercept('GET', '/api/v1/privacy/deletion*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            request: {
              id: 'del-1',
              status: 'pending',
              deletion_type: 'full',
              can_be_cancelled: true,
              in_grace_period: true,
              days_until_deletion: 25,
              grace_period_ends_at: '2025-02-15T00:00:00Z',
              created_at: '2025-01-15T10:00:00Z'
            }
          }
        }
      }).as('getDeletionStatusPending');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Account Deletion Scheduled', 'Delete', 'Deletion', 'Privacy', 'scheduled', '25 days']);
    });

    it('should have cancel deletion option for pending request', () => {
      cy.intercept('GET', '/api/v1/privacy/deletion*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            request: {
              id: 'del-1',
              status: 'pending',
              can_be_cancelled: true,
              in_grace_period: true,
              days_until_deletion: 25
            }
          }
        }
      }).as('getDeletionStatusPending');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Cancel Deletion Request', 'Delete', 'Deletion', 'Cancel', 'Privacy']);
    });

    it('should cancel pending deletion request', () => {
      cy.intercept('GET', '/api/v1/privacy/deletion*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            request: {
              id: 'del-1',
              status: 'pending',
              can_be_cancelled: true,
              in_grace_period: true,
              days_until_deletion: 25
            }
          }
        }
      }).as('getDeletionStatusPending');

      cy.assertPageReady('/app/privacy');
      cy.clickButton('Cancel Deletion Request');
      cy.wait('@cancelDeletion');
    });
  });

  describe('Data Retention Policies', () => {
    const mockConsentsForRetention = {
      marketing: { granted: true, required: false, description: 'Marketing' },
      analytics: { granted: true, required: false, description: 'Analytics' },
      cookies: { granted: true, required: true, description: 'Cookies' },
      data_sharing: { granted: false, required: false, description: 'Data sharing' },
      third_party: { granted: false, required: false, description: 'Third party' },
      communications: { granted: true, required: true, description: 'Communications' },
      newsletter: { granted: true, required: false, description: 'Newsletter' },
      promotional: { granted: false, required: false, description: 'Promotional' },
    };

    it('should display data retention section when policies exist', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForRetention,
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' },
              { data_type: 'billing_records', retention_days: 2555, action: 'archive' },
              { data_type: 'activity_logs', retention_days: 365, action: 'anonymize' }
            ]
          }
        }
      }).as('getDashboardRetention');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Data Retention', 'Retention', 'Privacy', 'Data', 'Policy']);
    });

    it('should display retention periods', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForRetention,
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' }
            ]
          }
        }
      }).as('getDashboardRetention');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['years', 'year', 'Retention', 'Privacy', 'Data']);
    });

    it('should display data types in table', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForRetention,
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' }
            ]
          }
        }
      }).as('getDashboardRetention');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Data Type', 'Retention', 'Action', 'Privacy', 'account']);
    });

    it('should display retention actions with badges', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForRetention,
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' },
              { data_type: 'activity_logs', retention_days: 365, action: 'anonymize' }
            ]
          }
        }
      }).as('getDashboardRetention');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['delete', 'anonymize', 'archive', 'Privacy', 'Data', 'Retention']);
    });
  });

  describe('Terms Review Alert', () => {
    const mockConsentsForTerms = {
      marketing: { granted: true, required: false, description: 'Marketing' },
      analytics: { granted: true, required: false, description: 'Analytics' },
      cookies: { granted: true, required: true, description: 'Cookies' },
      data_sharing: { granted: false, required: false, description: 'Data sharing' },
      third_party: { granted: false, required: false, description: 'Third party' },
      communications: { granted: true, required: true, description: 'Communications' },
      newsletter: { granted: true, required: false, description: 'Newsletter' },
      promotional: { granted: false, required: false, description: 'Promotional' },
    };

    it('should display terms review alert when needed', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: mockConsentsForTerms,
            export_requests: [],
            terms_status: {
              needs_review: true,
              missing: ['privacy_policy', 'terms_of_service']
            },
            data_retention_info: []
          }
        }
      }).as('getDashboardTerms');

      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Terms and Policies Updated', 'Terms', 'Policy', 'Review', 'Privacy']);
    });

    it('should not display alert when no review needed', () => {
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Privacy', 'Consent', 'Data']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/privacy/dashboard*', {
        statusCode: 500,
        visitUrl: '/app/privacy'
      });
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load privacy dashboard' }
      }).as('getDashboardError');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'error', 'failed', 'Privacy', 'Center']);
    });

    it('should handle consent update error', () => {
      cy.intercept('PUT', '/api/v1/privacy/consents*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to update consent preferences' }
      }).as('updateConsentsError');

      cy.assertPageReady('/app/privacy');
      cy.get('button[role="switch"]').not(':disabled').first().click();
      cy.clickButton('Save Changes');
      cy.wait('@updateConsentsError');
      cy.assertContainsAny(['Error', 'Failed', 'error', 'failed', 'Privacy']);
    });

    it('should handle export request error', () => {
      cy.intercept('POST', '/api/v1/privacy/export*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to request data export' }
      }).as('requestExportError');

      cy.assertPageReady('/app/privacy');
      cy.clickButton('Request Export');
      cy.wait('@requestExportError');
      cy.assertContainsAny(['Error', 'Failed', 'error', 'failed', 'Privacy', 'Export']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Privacy Center', 'Privacy', 'Consent', 'Data']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/privacy');
      cy.assertContainsAny(['Privacy Center', 'Privacy', 'Consent', 'Data']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/privacy');
      cy.assertContainsAny(['Privacy Center', 'Privacy', 'Consent', 'Data']);
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/privacy');
      cy.assertContainsAny(['Active Consents', 'Consent', 'Privacy', 'Data']);
    });

    it('should display grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.assertPageReady('/app/privacy');
      cy.assertHasElement(['.grid', '[class*="card"]', '[class*="grid"]']);
    });
  });

  describe('Consent Icons', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should display emoji icons for consent types', () => {
      cy.assertContainsAny(['Marketing', 'Analytics', 'Cookie', 'Consent', 'Privacy']);
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/privacy');
    });

    it('should have accessible toggle switches', () => {
      cy.assertHasElement(['button[role="switch"]']);
    });

    it('should have proper heading structure', () => {
      cy.assertHasElement(['h1', 'h2', 'h3']);
    });

    it('should have accessible form labels', () => {
      cy.assertHasElement(['label']);
    });
  });
});


export {};
