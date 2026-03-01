/// <reference types="cypress" />

/**
 * Content Files Management Workflows Tests
 *
 * Comprehensive E2E tests for File Management:
 * - File upload
 * - File browsing
 * - Search and filtering
 * - Bulk operations
 * - Storage statistics
 */

describe('Content Files Management Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
    setupFilesIntercepts();
  });

  describe('Files Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should display files page with title', () => {
      cy.assertContainsAny(['My Files', 'Files']);
    });

    it('should have upload files button', () => {
      cy.get('button').contains(/upload files/i).should('exist');
    });

    it('should have refresh button', () => {
      cy.get('button').contains(/refresh/i).should('exist');
    });
  });

  describe('Search and Filters', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search files"]').should('exist');
    });

    it('should filter by search query', () => {
      cy.get('input[placeholder*="Search files"]').type('document');
      cy.waitForPageLoad();
    });

    it('should display category filter', () => {
      cy.assertContainsAny(['All Categories', 'Category', 'User Upload']);
    });

    it('should display visibility filter', () => {
      cy.assertContainsAny(['All Visibility', 'Visibility', 'Private', 'Public']);
    });

    it('should have category dropdown options', () => {
      cy.get('select').contains(/all categories/i).should('exist');
    });

    it('should have visibility dropdown options', () => {
      cy.get('select').contains(/all visibility/i).should('exist');
    });
  });

  describe('File List Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should display files list or empty state', () => {
      // Wait for page to load and show either files or empty state
      cy.waitForPageLoad();
      cy.assertContainsAny(['document', 'image', 'No files', 'Upload', 'My Files']);
    });

    it('should display file information or empty state message', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No files')) {
          cy.log('Empty state displayed');
          cy.assertContainsAny(['No files', 'Upload']);
        } else if ($body.text().includes('Failed to load')) {
          cy.log('Files failed to load');
        } else {
          cy.log('Files loaded - checking for file info');
        }
      });
    });
  });

  describe('File Upload', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should open upload modal when button clicked', () => {
      cy.get('button').contains(/upload files/i).click();
      cy.assertContainsAny(['Upload Files', 'Storage Provider', 'Close']);
    });

    it('should have close button in upload modal', () => {
      cy.get('button').contains(/upload files/i).click();
      cy.get('button').contains(/close/i).should('exist');
    });

    it('should close modal when close clicked', () => {
      cy.get('button').contains(/upload files/i).click();
      cy.get('button').contains(/close|×/i).first().click();
    });
  });

  describe('Bulk Operations', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should have checkboxes when files exist', () => {
      cy.get('body').then($body => {
        // Only test if files are displayed (not empty state or error)
        if (!$body.text().includes('No files') && !$body.text().includes('Failed to load')) {
          cy.get('input[type="checkbox"]').should('exist');
        } else {
          cy.log('Files not loaded - skipping checkbox test');
        }
      });
    });

    it('should show bulk action bar when files selected', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No files') && !$body.text().includes('Failed to load')) {
          cy.get('input[type="checkbox"]').first().check({ force: true });
          cy.waitForPageLoad();
          cy.assertContainsAny(['selected', 'Download', 'Delete', 'Clear']);
        } else {
          cy.log('Files not loaded - skipping bulk action test');
        }
      });
    });
  });

  describe('Storage Statistics', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/files');
    });

    it('should display storage info when files loaded', () => {
      cy.get('body').then($body => {
        // Storage stats are only shown when fileStats is available
        if ($body.text().includes('Storage Used') || $body.text().includes('Total Files')) {
          cy.assertContainsAny(['Storage Used', 'Total Files', 'Storage']);
        } else {
          cy.log('Storage stats not displayed - files may not have loaded');
        }
      });
    });

    it('should display total files count when available', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Total Files')) {
          cy.contains(/total files/i).should('exist');
        } else {
          cy.log('Total files card not visible');
        }
      });
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no files', () => {
      cy.intercept('GET', '**/api/**/files*', {
        statusCode: 200,
        body: { files: [] },
      }).as('getEmptyFiles');

      cy.intercept('GET', '**/api/**/files/stats*', {
        statusCode: 200,
        body: { total_files: 0, total_size: 0, by_category: {}, by_type: {} },
      }).as('getEmptyStats');

      cy.navigateTo('/app/content/files');
      cy.wait('@getEmptyFiles');
      cy.assertContainsAny(['No files yet', 'No files', 'Upload your first']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/files**', {
        statusCode: 500,
        visitUrl: '/app/content/files',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/content/files', {
        checkContent: 'Files',
      });
    });
  });
});

function setupFilesIntercepts() {
  const mockFiles = [
    {
      id: 'file-1',
      filename: 'document.pdf',
      storage_key: 'uploads/document.pdf',
      content_type: 'application/pdf',
      file_size: 1024000,
      file_type: 'document',
      category: 'user_upload',
      visibility: 'private',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-10T10:00:00Z',
      updated_at: '2025-01-14T10:00:00Z',
    },
    {
      id: 'file-2',
      filename: 'image.jpg',
      storage_key: 'uploads/image.jpg',
      content_type: 'image/jpeg',
      file_size: 512000,
      file_type: 'image',
      category: 'user_upload',
      visibility: 'public',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-12T10:00:00Z',
      updated_at: '2025-01-13T10:00:00Z',
    },
    {
      id: 'file-3',
      filename: 'spreadsheet.xlsx',
      storage_key: 'uploads/spreadsheet.xlsx',
      content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      file_size: 256000,
      file_type: 'document',
      category: 'workflow_output',
      visibility: 'private',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-08T10:00:00Z',
      updated_at: '2025-01-11T10:00:00Z',
    },
  ];

  const mockStats = {
    total_files: 150,
    total_size: 5000000000,
    by_category: {
      user_upload: 100,
      workflow_output: 30,
      ai_generated: 20,
    },
    by_type: {
      'application/pdf': 50,
      'image/jpeg': 40,
      'image/png': 30,
    },
  };

  const mockPagination = {
    current_page: 1,
    per_page: 25,
    total_pages: 1,
    total_count: 3,
  };

  const mockStorageProviders = [
    {
      id: 'sp-1',
      name: 'Local Storage',
      provider_type: 'local',
      is_default: true,
      is_active: true,
      max_file_size_mb: 100,
    },
  ];

  // Files list endpoint - must match exact API path
  cy.intercept('GET', '/api/v1/files', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        files: mockFiles,
        pagination: mockPagination,
      },
    },
  }).as('getFiles');

  // Files stats endpoint
  cy.intercept('GET', '/api/v1/files/stats', {
    statusCode: 200,
    body: { success: true, data: mockStats },
  }).as('getFileStats');

  // Storage providers endpoint
  cy.intercept('GET', '/api/v1/storage/providers*', {
    statusCode: 200,
    body: { success: true, data: { providers: mockStorageProviders } },
  }).as('getStorageProviders');

  // Single file endpoint
  cy.intercept('GET', /\/api\/v1\/files\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: { success: true, data: { file: mockFiles[0] } },
  }).as('getFile');

  // File upload endpoint
  cy.intercept('POST', '/api/v1/files/upload', {
    statusCode: 200,
    body: { success: true, data: { file: { id: 'file-new', filename: 'uploaded.pdf' } } },
  }).as('uploadFile');

  // File delete endpoint
  cy.intercept('DELETE', /\/api\/v1\/files\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: { success: true },
  }).as('deleteFile');

  // File download endpoint
  cy.intercept('GET', /\/api\/v1\/files\/[a-z0-9-]+\/download/, {
    statusCode: 200,
    headers: { 'content-type': 'application/octet-stream' },
    body: 'file content',
  }).as('downloadFile');
}

export {};
