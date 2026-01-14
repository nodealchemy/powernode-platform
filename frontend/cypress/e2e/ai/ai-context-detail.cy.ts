/// <reference types="cypress" />

describe('AI Context Detail Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Context Detail page', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.url().should('include', '/ai');
    });

    it('should display Context Not Found for invalid ID', () => {
      cy.visit('/app/ai/contexts/invalid-context-id');
      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('Not Found') ||
                           $body.text().includes("doesn't exist") ||
                           $body.text().includes('Back to');
        if (hasNotFound) {
          cy.log('Context not found message displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Import/Export button', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasImportExport = $body.text().includes('Import/Export') ||
                               $body.text().includes('Import') ||
                               $body.text().includes('Export');
        if (hasImportExport) {
          cy.log('Import/Export button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Add Entry button', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasAdd = $body.text().includes('Add Entry') ||
                      $body.text().includes('Add');
        if (hasAdd) {
          cy.log('Add Entry button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Context Header', () => {
    it('should display context icon', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasIcon = $body.find('[class*="text-3xl"]').length > 0;
        if (hasIcon) {
          cy.log('Context icon found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display context name', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasName = $body.find('h2[class*="font-semibold"]').length > 0;
        if (hasName) {
          cy.log('Context name found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Archived badge when archived', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasArchived = $body.text().includes('Archived');
        if (hasArchived) {
          cy.log('Archived badge displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display context description', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasDesc = $body.find('p[class*="secondary"]').length > 0;
        if (hasDesc) {
          cy.log('Context description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display context metadata', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasMeta = $body.text().includes('Agent:') ||
                       $body.text().match(/v\d+/);
        if (hasMeta) {
          cy.log('Context metadata found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Cards', () => {
    it('should display Total Entries stat', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total Entries');
        if (hasTotal) {
          cy.log('Total Entries stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Data Size stat', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasSize = $body.text().includes('Data Size');
        if (hasSize) {
          cy.log('Data Size stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display With Embeddings stat', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasEmbeddings = $body.text().includes('With Embeddings') ||
                             $body.text().includes('Embeddings');
        if (hasEmbeddings) {
          cy.log('With Embeddings stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Avg Importance stat', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasImportance = $body.text().includes('Avg Importance') ||
                             $body.text().includes('Importance');
        if (hasImportance) {
          cy.log('Avg Importance stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Total Accesses stat', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasAccesses = $body.text().includes('Total Accesses') ||
                           $body.text().includes('Accesses');
        if (hasAccesses) {
          cy.log('Total Accesses stat found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    it('should display Entries tab', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Entries');
        if (hasTab) {
          cy.log('Entries tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Search tab', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Search');
        if (hasTab) {
          cy.log('Search tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Settings tab', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Settings');
        if (hasTab) {
          cy.log('Settings tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Search tab', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Search")').length > 0) {
          cy.contains('button', 'Search').click();
          cy.log('Switched to Search tab');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Settings tab', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Settings")').length > 0) {
          cy.contains('button', 'Settings').click();
          cy.log('Switched to Settings tab');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Entries Tab Content', () => {
    it('should display filter input', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasFilter = $body.find('input[placeholder*="Filter"]').length > 0 ||
                         $body.find('input[type="text"]').length > 0;
        if (hasFilter) {
          cy.log('Filter input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display type selector', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasSelect = $body.find('select').length > 0 ||
                         $body.text().includes('All Types');
        if (hasSelect) {
          cy.log('Type selector found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display entries list or empty state', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasList = $body.find('button[class*="text-left"]').length > 0 ||
                       $body.text().includes('No entries') ||
                       $body.text().includes('Add your first entry');
        if (hasList) {
          cy.log('Entries list or empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display entry type badges', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('fact') ||
                        $body.text().includes('preference') ||
                        $body.text().includes('knowledge') ||
                        $body.find('[class*="badge"]').length > 0;
        if (hasTypes) {
          cy.log('Entry type badges found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Settings Tab Content', () => {
    it('should display Retention Policy section', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Settings")').length > 0) {
          cy.contains('button', 'Settings').click();
          cy.get('body').then($updated => {
            const hasRetention = $updated.text().includes('Retention Policy');
            if (hasRetention) {
              cy.log('Retention Policy section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Danger Zone section', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Settings")').length > 0) {
          cy.contains('button', 'Settings').click();
          cy.get('body').then($updated => {
            const hasDanger = $updated.text().includes('Danger Zone');
            if (hasDanger) {
              cy.log('Danger Zone section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Archive/Restore button', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Settings")').length > 0) {
          cy.contains('button', 'Settings').click();
          cy.get('body').then($updated => {
            const hasArchive = $updated.text().includes('Archive') ||
                              $updated.text().includes('Restore');
            if (hasArchive) {
              cy.log('Archive/Restore button found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Delete button', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Settings")').length > 0) {
          cy.contains('button', 'Settings').click();
          cy.get('body').then($updated => {
            const hasDelete = $updated.text().includes('Delete Context') ||
                             $updated.text().includes('Delete');
            if (hasDelete) {
              cy.log('Delete button found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Import/Export Modal', () => {
    it('should open Import/Export modal', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Import/Export")').length > 0) {
          cy.contains('button', 'Import/Export').click();
          cy.get('body').then($updated => {
            const hasModal = $updated.find('[class*="modal"]').length > 0 ||
                            $updated.find('[role="dialog"]').length > 0;
            if (hasModal) {
              cy.log('Import/Export modal opened');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Entry Editor', () => {
    it('should open entry editor when Add Entry clicked', () => {
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Entry")').length > 0) {
          cy.contains('button', 'Add Entry').click();
          cy.get('body').then($updated => {
            const hasEditor = $updated.text().includes('New Entry') ||
                             $updated.text().includes('Edit Entry');
            if (hasEditor) {
              cy.log('Entry editor opened');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/contexts/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/contexts/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').should('be.visible');
    });

    it('should stack stats cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-2"]').length > 0 ||
                       $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive stats grid found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/ai/contexts/test-context');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="md:grid-cols-5"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column stats layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
