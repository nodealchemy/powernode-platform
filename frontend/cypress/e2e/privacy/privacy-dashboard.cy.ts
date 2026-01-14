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
    cy.setupPrivacyIntercepts();
    cy.setupApiIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Privacy Dashboard page', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains(/Privacy|Consent|Data/).should('exist');
    });

    it('should display page title', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('Privacy Center').should('be.visible');
    });

    it('should display page description', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains(/privacy settings|manage.*data/i).should('be.visible');
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should display Active Consents stat', () => {
      cy.contains('Active Consents').should('be.visible');
    });

    it('should display Data Exports stat', () => {
      cy.contains('Data Exports').should('be.visible');
    });

    it('should display Terms Status stat', () => {
      cy.contains('Terms Status').should('be.visible');
    });

    it('should display stats cards with icons', () => {
      // Check for the stats card grid
      cy.get('.grid').first().within(() => {
        cy.get('[class*="rounded-lg"]').should('have.length.at.least', 3);
      });
    });
  });

  describe('Consent Management', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should display consent management section', () => {
      cy.contains('Consent Preferences').should('be.visible');
    });

    it('should display consent toggles', () => {
      cy.get('button[role="switch"]').should('have.length.at.least', 1);
    });

    it('should display consent type labels', () => {
      cy.contains('Marketing Communications').should('be.visible');
      cy.contains('Usage Analytics').should('be.visible');
    });

    it('should display consent descriptions', () => {
      cy.contains('Manage how your data is used').should('be.visible');
    });

    it('should toggle consent preference', () => {
      cy.intercept('PUT', '/api/v1/privacy/consents').as('updateConsents');

      // Find a non-required toggle and click it
      cy.get('button[role="switch"]').not(':disabled').first()
        .should('be.visible')
        .click();

      // Should show Save Changes button after toggle
      cy.contains('Save Changes').should('be.visible');
    });

    it('should save consent changes', () => {
      cy.intercept('PUT', '/api/v1/privacy/consents').as('updateConsents');

      // Toggle a consent
      cy.get('button[role="switch"]').not(':disabled').first()
        .should('be.visible')
        .click();

      // Click Save Changes
      cy.contains('Save Changes').should('be.visible').click();

      // Wait for API call
      cy.wait('@updateConsents');
    });

    it('should display privacy rights info', () => {
      cy.contains('Your Privacy Rights').should('be.visible');
      cy.contains(/withdraw consent|Required consents/i).should('be.visible');
    });

    it('should show Required badge for required consents', () => {
      cy.contains('Required').should('be.visible');
    });

    it('should disable toggle for required consents', () => {
      // Required consents should have disabled toggles
      cy.get('button[role="switch"]:disabled').should('have.length.at.least', 1);
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should display data export section', () => {
      cy.contains('Data Export').should('be.visible');
      cy.contains('Download a copy of your personal data').should('be.visible');
    });

    it('should have Request Export button', () => {
      cy.contains('button', 'Request Export').should('be.visible');
    });

    it('should display export format options', () => {
      cy.get('select').should('contain', 'JSON');
    });

    it('should select different export formats', () => {
      cy.get('select').select('csv');
      cy.get('select').should('have.value', 'csv');

      cy.get('select').select('zip');
      cy.get('select').should('have.value', 'zip');
    });

    it('should request data export', () => {
      cy.intercept('POST', '/api/v1/privacy/export').as('requestExport');

      cy.contains('button', 'Request Export').should('be.visible').click();

      cy.wait('@requestExport');
    });

    it('should show requesting state', () => {
      cy.intercept('POST', '/api/v1/privacy/export', {
        delay: 1000,
        statusCode: 200,
        body: {
          success: true,
          request: { id: 'test-id', status: 'pending', format: 'json' }
        }
      }).as('requestExport');

      cy.contains('button', 'Request Export').click();
      cy.contains('Requesting...').should('be.visible');
    });
  });

  describe('Data Export History', () => {
    it('should display recent exports section when exports exist', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing emails' },
              cookies: { granted: true, required: true, description: 'Essential cookies' }
            },
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
      }).as('getDashboard');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Recent Exports').should('be.visible');
      cy.contains('JSON Export').should('be.visible');
    });

    it('should have download button for completed exports', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
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
      }).as('getDashboard');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('button', 'Download').should('be.visible');
    });

    it('should show processing status for pending exports', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
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
      }).as('getDashboard');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Processing...').should('be.visible');
    });
  });

  describe('Data Deletion', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should display data deletion section', () => {
      cy.contains('Delete Your Data').should('be.visible');
      cy.contains('Request permanent deletion').should('be.visible');
    });

    it('should have Request Deletion button', () => {
      cy.contains('button', 'Request Data Deletion').should('be.visible');
    });

    it('should display GDPR notice', () => {
      cy.contains(/GDPR Article 17|right to request deletion/i).should('be.visible');
    });

    it('should open deletion confirmation on button click', () => {
      cy.contains('button', 'Request Data Deletion').click();

      // Should show confirmation form
      cy.contains('Important Notice').should('be.visible');
      cy.contains('Deletion Type').should('be.visible');
    });

    it('should display deletion type options', () => {
      cy.contains('button', 'Request Data Deletion').click();

      cy.contains('Full Deletion').should('be.visible');
      cy.contains('Anonymization').should('be.visible');
    });

    it('should display deletion warning', () => {
      cy.contains('button', 'Request Data Deletion').click();

      cy.contains(/cannot be undone|30 days/i).should('be.visible');
    });

    it('should cancel deletion confirmation', () => {
      cy.contains('button', 'Request Data Deletion').click();
      cy.contains('Important Notice').should('be.visible');

      cy.contains('button', 'Cancel').click();

      cy.contains('Important Notice').should('not.exist');
    });

    it('should submit deletion request', () => {
      cy.intercept('POST', '/api/v1/privacy/deletion').as('requestDeletion');

      cy.contains('button', 'Request Data Deletion').click();
      cy.contains('button', 'Confirm Deletion Request').should('be.visible').click();

      cy.wait('@requestDeletion');
    });

    it('should show reason textarea', () => {
      cy.contains('button', 'Request Data Deletion').click();

      cy.get('textarea[placeholder*="Help us improve"]').should('be.visible');
    });
  });

  describe('Pending Deletion Request', () => {
    it('should display pending deletion status', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: {
          success: true,
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
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('Account Deletion Scheduled').should('be.visible');
      cy.contains('25 days').should('be.visible');
    });

    it('should have cancel deletion option for pending request', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: {
          success: true,
          request: {
            id: 'del-1',
            status: 'pending',
            can_be_cancelled: true,
            in_grace_period: true,
            days_until_deletion: 25
          }
        }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('button', 'Cancel Deletion Request').should('be.visible');
    });

    it('should cancel pending deletion request', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: {
          success: true,
          request: {
            id: 'del-1',
            status: 'pending',
            can_be_cancelled: true,
            in_grace_period: true,
            days_until_deletion: 25
          }
        }
      }).as('getDeletionStatus');
      cy.intercept('DELETE', '/api/v1/privacy/deletion/*').as('cancelDeletion');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('button', 'Cancel Deletion Request').click();

      cy.wait('@cancelDeletion');
    });
  });

  describe('Data Retention Policies', () => {
    it('should display data retention section when policies exist', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' },
              { data_type: 'billing_records', retention_days: 2555, action: 'archive' },
              { data_type: 'activity_logs', retention_days: 365, action: 'anonymize' }
            ]
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Data Retention Policies').should('be.visible');
    });

    it('should display retention periods', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' }
            ]
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('5 years').should('be.visible');
    });

    it('should display data types in table', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' }
            ]
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Data Type').should('be.visible');
      cy.contains('Retention Period').should('be.visible');
      cy.contains('Action').should('be.visible');
    });

    it('should display retention actions with badges', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: [
              { data_type: 'account_data', retention_days: 1825, action: 'delete' },
              { data_type: 'activity_logs', retention_days: 365, action: 'anonymize' }
            ]
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('delete').should('be.visible');
      cy.contains('anonymize').should('be.visible');
    });
  });

  describe('Terms Review Alert', () => {
    it('should display terms review alert when needed', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: {
              needs_review: true,
              missing: ['privacy_policy', 'terms_of_service']
            },
            data_retention_info: []
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Terms and Policies Updated').should('be.visible');
      cy.contains(/privacy policy|terms of service/i).should('be.visible');
    });

    it('should not display alert when no review needed', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {
              marketing: { granted: true, required: false, description: 'Marketing' }
            },
            export_requests: [],
            terms_status: {
              needs_review: false,
              missing: []
            },
            data_retention_info: []
          }
        }
      }).as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');

      cy.visit('/app/privacy');
      cy.wait('@getDashboard');
      cy.waitForPageLoad();

      cy.contains('Terms and Policies Updated').should('not.exist');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getDashboardError');

      cy.visit('/app/privacy');
      cy.wait('@getDashboardError');

      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load privacy dashboard' }
      }).as('getDashboardError');

      cy.visit('/app/privacy');
      cy.wait('@getDashboardError');

      cy.contains(/Error|Failed/i).should('be.visible');
    });

    it('should handle consent update error', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('PUT', '/api/v1/privacy/consents', {
        statusCode: 500,
        body: { success: false, error: 'Failed to update consent preferences' }
      }).as('updateConsentsError');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.get('button[role="switch"]').not(':disabled').first().click();
      cy.contains('Save Changes').click();

      cy.wait('@updateConsentsError');
      cy.contains(/Error|Failed/i).should('be.visible');
    });

    it('should handle export request error', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('POST', '/api/v1/privacy/export', {
        statusCode: 500,
        body: { success: false, error: 'Failed to request data export' }
      }).as('requestExportError');

      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('button', 'Request Export').click();

      cy.wait('@requestExportError');
      cy.contains(/Error|Failed/i).should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/privacy/dashboard', {
        delay: 2000,
        statusCode: 200,
        body: {
          success: true,
          data: {
            consents: {},
            export_requests: [],
            terms_status: { needs_review: false, missing: [] },
            data_retention_info: []
          }
        }
      }).as('getDashboardSlow');

      cy.visit('/app/privacy');

      // Should show loading spinner
      cy.get('[class*="animate-spin"]').should('be.visible');

      // Then content should load
      cy.wait('@getDashboardSlow');
      cy.contains('Privacy Center').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.intercept('GET', '/api/v1/privacy/deletion', {
        statusCode: 200,
        body: { success: true, request: null }
      }).as('getDeletionStatus');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('Privacy Center').should('be.visible');
      cy.contains('Consent Preferences').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      cy.contains('Privacy Center').should('be.visible');
      cy.get('.grid').should('be.visible');
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      // Stats should be visible and stacked
      cy.contains('Active Consents').should('be.visible');
    });

    it('should display grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/privacy');
      cy.waitForPageLoad();

      // Check for grid layout
      cy.get('.grid.grid-cols-1.md\\:grid-cols-3').should('be.visible');
    });
  });

  describe('Consent Icons', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should display emoji icons for consent types', () => {
      // These emojis are defined in the ConsentManager component
      cy.get('body').should('contain', '📢'); // marketing
      cy.get('body').should('contain', '📊'); // analytics
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/privacy/dashboard').as('getDashboard');
      cy.visit('/app/privacy');
      cy.waitForPageLoad();
    });

    it('should have accessible toggle switches', () => {
      cy.get('button[role="switch"]').each(($switch) => {
        cy.wrap($switch).should('have.attr', 'aria-checked');
      });
    });

    it('should have proper heading structure', () => {
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible form labels', () => {
      cy.get('label').should('have.length.at.least', 1);
    });
  });
});


export {};
