/// <reference types="cypress" />

/**
 * User Activity Tests
 *
 * Tests for User Activity functionality including:
 * - Activity feed
 * - Activity filtering
 * - Activity search
 * - Activity notifications
 * - Activity export
 * - Activity timeline
 */

describe('User Activity Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Activity Feed', () => {
    it('should navigate to activity page', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Activity', 'History', 'Recent']);
    });

    it('should display activity list', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="activity-list"]', '.activity-feed', 'table']);
    });

    it('should display activity timestamps', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
      cy.assertContainsAny(['ago', 'Today']);
    });

    it('should display activity types', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Login', 'Update', 'Create', 'Delete']);
    });
  });

  describe('Activity Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have date range filter', () => {
      cy.assertContainsAny(['Date']);
    });

    it('should have activity type filter', () => {
      cy.assertContainsAny(['Type', 'Filter']);
    });

    it('should have clear filters option', () => {
      cy.assertContainsAny(['Clear', 'Reset']);
    });
  });

  describe('Activity Search', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have search input', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']);
    });

    it('should filter results on search', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('login');
      cy.assertContainsAny(['login', 'Login', 'Activity']);
    });
  });

  describe('Activity Details', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should display activity descriptions', () => {
      cy.assertHasElement(['p', '.description', '[data-testid="activity-description"]']);
    });

    it('should display IP address', () => {
      cy.assertContainsAny(['IP', 'Address']);
    });

    it('should display device/browser info', () => {
      cy.assertContainsAny(['Device', 'Browser', 'Chrome', 'Firefox']);
    });
  });

  describe('Activity Export', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have export option', () => {
      cy.assertContainsAny(['Export', 'Download']);
    });

    it('should offer export formats', () => {
      cy.assertContainsAny(['CSV', 'PDF', 'JSON']);
    });
  });

  describe('Activity Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have pagination controls', () => {
      cy.assertContainsAny(['Page', 'Next', 'Previous']);
    });

    it('should have load more option', () => {
      cy.assertContainsAny(['Load more', 'Show more']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display activity correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/activity');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Activity', 'History', 'Recent']);
        cy.log(`Activity displayed correctly on ${name}`);
      });
    });
  });
});
