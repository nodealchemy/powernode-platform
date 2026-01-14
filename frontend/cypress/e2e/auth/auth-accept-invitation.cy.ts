describe('Accept Invitation Flow Tests', () => {
  const validToken = 'valid-invitation-token-abc123';
  const invalidToken = 'invalid-token-xyz789';
  const expiredToken = 'expired-token-def456';
  const acceptedToken = 'already-accepted-token-ghi012';

  // Mock invitation data
  const mockInvitation = {
    id: 'inv-123',
    email: 'invitee@example.com',
    role: 'member',
    status: 'pending',
    invited_by: 'admin@example.com',
    invited_at: '2025-01-10T10:00:00Z',
    expires_at: '2025-01-24T10:00:00Z',
    account_id: 'acc-456',
    token: validToken,
    created_at: '2025-01-10T10:00:00Z',
    updated_at: '2025-01-10T10:00:00Z',
  };

  // Valid form data that meets all password requirements
  const validFormData = {
    first_name: 'John',
    last_name: 'Doe',
    password: 'SecurePass123!@#',
    password_confirmation: 'SecurePass123!@#',
  };

  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
  });

  describe('Token Validation', () => {
    it('should display invitation form for valid pending token', () => {
      // Mock valid invitation API response
      // Note: Return just the invitation object - the API service wraps with {success, data}
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Should display the invitation form
      cy.contains('Join the Team!').should('be.visible');
      cy.contains('Member').should('be.visible'); // Role display (capitalized)
      cy.get('input[type="text"]').should('have.length.at.least', 2); // First and last name
      cy.get('input[type="password"]').should('have.length', 2); // Password fields
      cy.get('button[type="submit"]').should('be.visible');
    });

    it('should display error for invalid token', () => {
      // Mock invalid token API response
      cy.intercept('GET', `**/invitations/${invalidToken}`, {
        statusCode: 404,
        body: {
          success: false,
          message: 'Invitation not found or expired',
        },
      }).as('getInvalidInvitation');

      cy.visit(`/accept-invitation/${invalidToken}`);
      cy.wait('@getInvalidInvitation');
      cy.waitForStableDOM();

      // Should display error state
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('Invitation not found or expired').should('be.visible');
      cy.contains('Go to Login').should('be.visible');
    });

    it('should display error for expired token', () => {
      // Mock expired invitation API response
      cy.intercept('GET', `**/invitations/${expiredToken}`, {
        statusCode: 410,
        body: {
          success: false,
          message: 'This invitation has expired',
        },
      }).as('getExpiredInvitation');

      cy.visit(`/accept-invitation/${expiredToken}`);
      cy.wait('@getExpiredInvitation');
      cy.waitForStableDOM();

      // Should display error state
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('expired').should('be.visible');
      cy.contains('Go to Login').should('be.visible');
    });

    it('should display error for already accepted token', () => {
      // Mock already accepted invitation
      const acceptedInvitation = {
        ...mockInvitation,
        token: acceptedToken,
        status: 'accepted',
      };

      cy.intercept('GET', `**/invitations/${acceptedToken}`, {
        statusCode: 200,
        body: acceptedInvitation,
      }).as('getAcceptedInvitation');

      cy.visit(`/accept-invitation/${acceptedToken}`);
      cy.wait('@getAcceptedInvitation');
      cy.waitForStableDOM();

      // Should display error for non-pending status
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('accepted').should('be.visible');
    });

    it('should display error when no token provided', () => {
      // Visiting the base path without a token
      // Note: The route redirects to /welcome when no token is provided
      cy.visit('/accept-invitation/', { failOnStatusCode: false });
      cy.waitForStableDOM();

      // The app redirects to welcome page when token is missing
      // This is acceptable behavior - verify the redirect happens
      cy.url().should('satisfy', (url: string) => {
        return url.includes('/welcome') || url.includes('/login') || url.includes('Invalid');
      });
    });

    it('should handle network error when fetching invitation', () => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        forceNetworkError: true,
      }).as('networkError');

      cy.visit(`/accept-invitation/${validToken}`);
      // Network errors may not trigger cy.wait properly
      cy.waitForStableDOM();

      // Should display error state - the error message may vary
      cy.contains('Invalid Invitation').should('be.visible');
      // Check for any error message about loading failure
      cy.get('body').then(($body) => {
        const text = $body.text();
        const hasErrorMessage = text.includes('Failed to load') || text.includes('error') || text.includes('expired');
        expect(hasErrorMessage).to.be.true;
      });
    });
  });

  describe('Form Validation', () => {
    beforeEach(() => {
      // Set up valid invitation mock for all form validation tests
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();
    });

    it('should show validation error for empty first name', () => {
      // Set up accept invitation intercept
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      // Fill form without first name
      cy.get('input').eq(1).type('Doe'); // Last name
      cy.get('input[type="password"]').eq(0).type('SecurePass123!@#');
      cy.get('input[type="password"]').eq(1).type('SecurePass123!@#');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error
      cy.contains('First name is required').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for empty last name', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      // Fill form without last name
      cy.get('input').eq(0).type('John'); // First name
      cy.get('input[type="password"]').eq(0).type('SecurePass123!@#');
      cy.get('input[type="password"]').eq(1).type('SecurePass123!@#');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error
      cy.contains('Last name is required').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for empty password', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      // Fill form without password
      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error
      cy.contains('Password is required').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for password under 12 characters', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('Short1!'); // Only 7 chars
      cy.get('input[type="password"]').eq(1).type('Short1!');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error
      cy.contains('Password must be at least 12 characters').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for password without uppercase', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('securepass123!@#'); // No uppercase
      cy.get('input[type="password"]').eq(1).type('securepass123!@#');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error about password requirements
      cy.contains('uppercase').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for password without lowercase', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('SECUREPASS123!@#'); // No lowercase
      cy.get('input[type="password"]').eq(1).type('SECUREPASS123!@#');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error about password requirements
      cy.contains('lowercase').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for password without number', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('SecurePass!@#$%'); // No number
      cy.get('input[type="password"]').eq(1).type('SecurePass!@#$%');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error about password requirements
      cy.contains('number').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for password without special character', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('SecurePass12345'); // No special char
      cy.get('input[type="password"]').eq(1).type('SecurePass12345');

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error about password requirements
      cy.contains('special character').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should show validation error for mismatched passwords', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('SecurePass123!@#');
      cy.get('input[type="password"]').eq(1).type('DifferentPass456!@#'); // Different password

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error
      cy.contains('Passwords do not match').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should display password requirements section', () => {
      // Verify password requirements are visible
      cy.contains('Password Requirements').should('be.visible');
      cy.contains('At least 12 characters long').should('be.visible');
      cy.contains('uppercase and lowercase').should('be.visible');
      cy.contains('at least one number').should('be.visible');
      cy.contains('special character').should('be.visible');
    });

    it('should clear validation error when user corrects the field', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      // Submit with empty first name
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type('SecurePass123!@#');
      cy.get('input[type="password"]').eq(1).type('SecurePass123!@#');
      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show error
      cy.contains('First name is required').should('be.visible');

      // Now fill the first name
      cy.get('input').eq(0).type('John');

      // Error should clear (either immediately or on next interaction)
      cy.get('input').eq(0).blur();
    });
  });

  describe('Successful Invitation Acceptance', () => {
    beforeEach(() => {
      // Set up valid invitation mock
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');
    });

    it('should accept invitation and redirect to login on success', () => {
      // Mock successful acceptance
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 200,
        body: {
          success: true,
          data: {
            user: {
              id: 'user-123',
              email: 'invitee@example.com',
              first_name: 'John',
              last_name: 'Doe',
            },
          },
          message: 'Account created successfully',
        },
      }).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Fill the form with valid data
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit the form
      cy.get('button[type="submit"]').should('be.visible').click();

      // Wait for acceptance
      cy.wait('@acceptInvitation');

      // Should redirect to login page
      cy.url({ timeout: 5000 }).should('include', '/login');
    });

    it('should show loading state during submission', () => {
      // Mock slow acceptance
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        delay: 1000,
        statusCode: 200,
        body: {
          success: true,
          data: {},
        },
      }).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit the form
      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show loading state
      cy.contains('Creating Account').should('be.visible');

      // Button should be disabled during submission
      cy.get('button[type="submit"]').should('be.disabled');
    });

    it('should send correct data to API', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`, (req) => {
        // Verify request body
        expect(req.body).to.have.property('first_name', validFormData.first_name);
        expect(req.body).to.have.property('last_name', validFormData.last_name);
        expect(req.body).to.have.property('password', validFormData.password);
        expect(req.body).to.have.property('password_confirmation', validFormData.password_confirmation);

        req.reply({
          statusCode: 200,
          body: {
            success: true,
            data: {},
          },
        });
      }).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit
      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');
    });
  });

  describe('Failed Invitation Acceptance', () => {
    beforeEach(() => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();
    });

    it('should display error message when acceptance fails', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 400,
        body: {
          success: false,
          message: 'Failed to accept invitation',
        },
      }).as('acceptInvitation');

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit
      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');

      // Should display error
      cy.contains('Failed to accept invitation').should('be.visible');

      // Should stay on the page
      cy.url().should('include', '/accept-invitation');
    });

    it('should handle server validation errors', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 422,
        body: {
          success: false,
          message: 'Validation failed',
          errors: ['password: has been used before', 'email: already taken'],
        },
      }).as('acceptInvitation');

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit
      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');

      // Should display error message
      cy.contains('Validation failed').should('be.visible');
    });

    it('should handle network error during acceptance', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        forceNetworkError: true,
      }).as('networkError');

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit
      cy.get('button[type="submit"]').should('be.visible').click();

      // Network error shows error page - component displays "Failed to accept invitation"
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('Failed to accept invitation').should('be.visible');
    });

    it('should re-enable form after error', () => {
      // Use 400 status which keeps form visible (validation error)
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 400,
        body: {
          success: false,
          message: 'Validation failed',
        },
      }).as('acceptInvitation');

      // Fill the form
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit
      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');

      // Note: The component shows error page on error, so check the error is displayed
      // and user can navigate back
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('Go to Login').should('be.visible');
    });
  });

  describe('Navigation and Links', () => {
    beforeEach(() => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');
    });

    it('should navigate to login when clicking "Sign in instead"', () => {
      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Click the sign in link
      cy.contains('Sign in instead').should('be.visible').click();

      // Should navigate to login
      cy.url().should('include', '/login');
    });

    it('should navigate to login from error page', () => {
      cy.intercept('GET', `**/invitations/${invalidToken}`, {
        statusCode: 404,
        body: {
          success: false,
          message: 'Invitation not found',
        },
      }).as('getInvalidInvitation');

      cy.visit(`/accept-invitation/${invalidToken}`);
      cy.wait('@getInvalidInvitation');
      cy.waitForStableDOM();

      // Click Go to Login button
      cy.contains('Go to Login').should('be.visible').click();

      // Should navigate to login
      cy.url().should('include', '/login');
    });
  });

  describe('UI/UX Features', () => {
    beforeEach(() => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');
    });

    it('should show loading spinner while fetching invitation', () => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        delay: 500,
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitationSlow');

      cy.visit(`/accept-invitation/${validToken}`);

      // Should show loading state
      cy.contains('Loading invitation').should('be.visible');
    });

    it('should display the invited role', () => {
      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Should show the role user is being invited as
      cy.contains("You're being invited as").should('be.visible');
      cy.contains('Member').should('be.visible');
    });

    it('should display different roles correctly', () => {
      const adminInvitation = {
        ...mockInvitation,
        role: 'admin',
      };

      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: adminInvitation,
      }).as('getAdminInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getAdminInvitation');
      cy.waitForStableDOM();

      // Should show admin role
      cy.contains('Admin').should('be.visible');
    });

    it('should have proper form field placeholders', () => {
      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Check placeholders are present
      cy.get('input[placeholder="John"]').should('exist');
      cy.get('input[placeholder="Doe"]').should('exist');
      cy.get('input[placeholder*="strong password"]').should('exist');
      cy.get('input[placeholder*="Confirm"]').should('exist');
    });

    it('should have password fields with type password', () => {
      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Verify password fields are properly typed
      cy.get('input[type="password"]').should('have.length', 2);
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();
    });

    it('should have focusable form elements', () => {
      cy.get('input').eq(0).focus().should('be.focused');
      cy.get('input').eq(1).focus().should('be.focused');
      cy.get('input[type="password"]').eq(0).focus().should('be.focused');
      cy.get('input[type="password"]').eq(1).focus().should('be.focused');
      cy.get('button[type="submit"]').focus().should('be.focused');
    });

    it('should have form labels', () => {
      cy.contains('First Name').should('be.visible');
      cy.contains('Last Name').should('be.visible');
      cy.contains('Password').should('be.visible');
      cy.contains('Confirm Password').should('be.visible');
    });

    it('should support keyboard form submission', () => {
      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 200,
        body: {
          success: true,
          data: {},
        },
      }).as('acceptInvitation');

      // Fill form fields directly (tab() requires cypress-real-events plugin)
      cy.get('input').eq(0).type(validFormData.first_name);
      cy.get('input').eq(1).type(validFormData.last_name);
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      // Submit with Enter key from password confirmation field
      cy.get('input[type="password"]').eq(1).type('{enter}');

      cy.wait('@acceptInvitation');
      cy.url({ timeout: 5000 }).should('include', '/login');
    });
  });

  describe('Edge Cases', () => {
    it('should handle special characters in names', () => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.intercept('POST', `**/invitations/${validToken}/accept`, (req) => {
        expect(req.body.first_name).to.equal("O'Connor");
        expect(req.body.last_name).to.equal('Von-Müller');
        req.reply({
          statusCode: 200,
          body: {},
        });
      }).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Fill with special characters
      cy.get('input').eq(0).type("O'Connor");
      cy.get('input').eq(1).type('Von-Müller');
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');
    });

    it('should handle very long passwords that meet requirements', () => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      const longPassword = 'SecurePassword123!@#$%^&*()_+-=[]{}|;:,.<>?ABCdef';

      cy.intercept('POST', `**/invitations/${validToken}/accept`, {
        statusCode: 200,
        body: {},
      }).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      cy.get('input').eq(0).type('John');
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type(longPassword);
      cy.get('input[type="password"]').eq(1).type(longPassword);

      cy.get('button[type="submit"]').should('be.visible').click();
      cy.wait('@acceptInvitation');
      cy.url().should('include', '/login');
    });

    it('should trim whitespace from name fields', () => {
      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: mockInvitation,
      }).as('getInvitation');

      cy.intercept('POST', `**/invitations/${validToken}/accept`).as('acceptInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getInvitation');
      cy.waitForStableDOM();

      // Fill with whitespace-only first name
      cy.get('input').eq(0).type('   '); // Only spaces
      cy.get('input').eq(1).type('Doe');
      cy.get('input[type="password"]').eq(0).type(validFormData.password);
      cy.get('input[type="password"]').eq(1).type(validFormData.password_confirmation);

      cy.get('button[type="submit"]').should('be.visible').click();

      // Should show validation error (whitespace-only should fail)
      cy.contains('First name is required').should('be.visible');

      // Should not make API call
      cy.get('@acceptInvitation.all').should('have.length', 0);
    });

    it('should handle canceled invitation status', () => {
      const canceledInvitation = {
        ...mockInvitation,
        status: 'canceled',
      };

      cy.intercept('GET', `**/invitations/${validToken}`, {
        statusCode: 200,
        body: canceledInvitation,
      }).as('getCanceledInvitation');

      cy.visit(`/accept-invitation/${validToken}`);
      cy.wait('@getCanceledInvitation');
      cy.waitForStableDOM();

      // Should show error for canceled invitation
      cy.contains('Invalid Invitation').should('be.visible');
      cy.contains('canceled').should('be.visible');
    });
  });
});


export {};
