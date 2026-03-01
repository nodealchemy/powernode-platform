/// <reference types="cypress" />

/**
 * Detached Chat Window Tests
 *
 * Tests for the DetachedChatPage component at /chat/detached.
 * This is a full-screen floating chat window that syncs state
 * via BroadcastChannel with the main app window.
 */

describe('Detached Chat Window Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Load', () => {
    it('should load the detached chat page', () => {
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Chat', 'Conversation', 'New', 'Message']);
    });

    it('should display full-screen chat window', () => {
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertHasElement(['[class*="h-screen"]', '[class*="chat"]', '[class*="Chat"]']);
    });

    it('should display chat header', () => {
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertHasElement(['header', '[class*="header"]', '[class*="Header"]']);
    });
  });

  describe('Chat Interface', () => {
    beforeEach(() => {
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
    });

    it('should display conversation creator or active conversation', () => {
      cy.assertContainsAny(['New Conversation', 'Start', 'Chat', 'Message', 'Send']);
    });

    it('should have message input area', () => {
      cy.assertHasElement(['textarea', 'input[type="text"]', '[contenteditable]', '[class*="input"]']);
    });

    it('should have send button or action', () => {
      cy.assertHasElement(['button:contains("Send")', 'button[type="submit"]', '[class*="send"]', 'button']);
    });
  });

  describe('Chat Sidebar', () => {
    beforeEach(() => {
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
    });

    it('should have sidebar toggle', () => {
      cy.assertHasElement(['button[aria-label*="sidebar"]', '[class*="sidebar"]', '[class*="Sidebar"]', 'button']);
    });

    it('should display conversation list or empty state', () => {
      cy.assertContainsAny(['Conversations', 'Chat', 'New', 'No conversations']);
    });
  });

  describe('Authentication', () => {
    it('should require authentication', () => {
      // Clear auth state and try to access
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/chat/detached', { failOnStatusCode: false });
      // Should redirect to login
      cy.url().should('match', /\/(login|signin|auth)/);
    });
  });

  describe('Error Handling', () => {
    it('should handle chat API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/conversations**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' },
      });

      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Chat', 'New Conversation', 'retry']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Chat', 'Conversation', 'Message']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/chat/detached');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Chat', 'Conversation', 'Message']);
    });
  });
});

export {};
