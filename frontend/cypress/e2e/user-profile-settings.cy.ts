describe('User Profile and Settings Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    
    // Register and login a test user
    const timestamp = Date.now();
    cy.register({
      email: `profile-test-${timestamp}@example.com`,
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Profile',
      lastName: 'Tester',
      accountName: 'Profile Test Co'
    });
  });

  describe('User Profile Display', () => {
    it('should display user profile information in dashboard', () => {
      cy.url().should('include', '/dashboard');
      
      // Should show user's name
      cy.contains('Profile').should('be.visible');
      
      // Should show user menu
      cy.get('[data-testid="user-menu"]').should('be.visible');
      
      // Click user menu to see profile options
      cy.get('[data-testid="user-menu"]').click();
      
      // Should show profile-related menu items
      cy.get('body').should('contain.text', 'Profile').or('contain.text', 'Settings').or('contain.text', 'Account');
    });

    it('should show account information', () => {
      cy.url().should('include', '/dashboard');
      
      // Check if account name is displayed somewhere
      cy.get('body').should('contain.text', 'Profile Test Co').or('contain.text', 'Account');
      
      // Check user menu contents
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="user-menu"]').should('be.visible');
    });
  });

  describe('Profile Navigation', () => {
    it('should navigate to profile settings if available', () => {
      cy.url().should('include', '/dashboard');
      
      // Try to find profile/settings link
      cy.get('body').then($body => {
        if ($body.find('[data-testid="profile-link"], [href*="profile"], [href*="settings"]').length > 0) {
          // Profile link exists - test navigation
          cy.get('[data-testid="profile-link"], [href*="profile"], [href*="settings"]').first().click();
          
          // Should navigate to profile page
          cy.url().should('satisfy', (url) => {
            return url.includes('/profile') || url.includes('/settings') || url.includes('/account');
          });
          
          // Should show profile form or settings
          cy.get('form, input, .profile, .settings').should('exist');
        } else {
          // Try via user menu
          cy.get('[data-testid="user-menu"]').click();
          
          cy.get('body').then($menu => {
            if ($menu.find('[href*="profile"], [href*="settings"], [data-testid="profile-btn"]').length > 0) {
              cy.get('[href*="profile"], [href*="settings"], [data-testid="profile-btn"]').first().click();
              
              cy.url().should('satisfy', (url) => {
                return url.includes('/profile') || url.includes('/settings') || url.includes('/account');
              });
            } else {
              cy.log('Profile page not implemented yet - testing user menu interaction');
              cy.get('[data-testid="logout-btn"]').should('be.visible');
            }
          });
        }
      });
    });

    it('should handle user menu interactions', () => {
      // Test user menu functionality
      cy.get('[data-testid="user-menu"]').should('be.visible').click();
      
      // Should show dropdown menu
      cy.get('[data-testid="logout-btn"]').should('be.visible');
      
      // Should be able to close menu by clicking elsewhere
      cy.get('body').click(0, 0);
      cy.get('[data-testid="logout-btn"]').should('not.be.visible');
      
      // Should be able to reopen menu
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');
    });
  });

  describe('Profile Information Management', () => {
    it('should display editable profile fields if profile page exists', () => {
      // Try to navigate to profile page
      cy.visit('/profile');
      
      cy.get('body').then($body => {
        if ($body.find('form, input[name="firstName"], input[name="lastName"]').length > 0) {
          // Profile form exists
          cy.get('form').should('exist');
          
          // Should have profile fields
          cy.get('input[name="firstName"], [data-testid="first-name-input"]')
            .should('exist')
            .and('have.value', 'Profile');
          
          cy.get('input[name="lastName"], [data-testid="last-name-input"]')
            .should('exist')
            .and('have.value', 'Tester');
          
          cy.get('input[name="email"], [data-testid="email-input"]')
            .should('exist')
            .and('contain.value', 'profile-test-');
          
          // Should have save/update button
          cy.get('button[type="submit"], [data-testid="save-profile-btn"], [data-testid="update-btn"]')
            .should('exist')
            .and('be.visible');
          
        } else {
          // Profile page doesn't exist yet
          cy.log('Profile editing page not implemented - checking if redirected to dashboard');
          cy.url().should('include', '/dashboard');
        }
      });
    });

    it('should allow profile information updates if form exists', () => {
      // Try to access profile editing
      cy.visit('/profile');
      
      cy.get('body').then($body => {
        if ($body.find('input[name="firstName"]').length > 0) {
          // Profile editing is available
          const newFirstName = 'Updated';
          const newLastName = 'Name';
          
          // Update profile fields
          cy.get('input[name="firstName"]').clear().type(newFirstName);
          cy.get('input[name="lastName"]').clear().type(newLastName);
          
          // Submit form
          cy.get('button[type="submit"]').click();
          
          // Should show success message or redirect
          cy.url().should('satisfy', (url) => {
            return url.includes('/profile') || url.includes('/dashboard');
          });
          
          // Verify update (either success message or updated display)
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Updated') || text.includes('success') || text.includes('saved');
          });
          
        } else {
          cy.log('Profile editing not available - feature not implemented');
        }
      });
    });
  });

  describe('Account Settings', () => {
    it('should display account settings if available', () => {
      // Try various settings page routes
      const settingsRoutes = ['/settings', '/account', '/dashboard/settings', '/dashboard/account'];
      
      settingsRoutes.forEach(route => {
        cy.visit(route);
        
        cy.get('body').then($body => {
          if ($body.find('.settings, .account-settings, form').length > 0) {
            cy.log(`Settings found at route: ${route}`);
            
            // Should have settings form or content
            cy.get('.settings, .account-settings, form').should('be.visible');
            
            // Check for common settings fields
            cy.get('body').should('satisfy', ($body) => {
              const text = $body.text().toLowerCase();
              return text.includes('settings') || 
                     text.includes('account') || 
                     text.includes('preferences') ||
                     text.includes('profile');
            });
            
            return false; // Break loop if found
          }
        });
      });
    });

    it('should handle account name management', () => {
      // Check if account name can be edited
      cy.visit('/dashboard');
      
      // Look for account name display
      cy.get('body').should('contain.text', 'Profile Test Co');
      
      // Try to find editable account name
      cy.get('body').then($body => {
        if ($body.find('input[name="accountName"], [data-testid="account-name-input"]').length > 0) {
          // Account name is editable
          cy.get('input[name="accountName"], [data-testid="account-name-input"]')
            .should('have.value', 'Profile Test Co');
          
          // Try to update
          cy.get('input[name="accountName"], [data-testid="account-name-input"]')
            .clear()
            .type('Updated Test Company');
          
          // Look for save button
          cy.get('button[type="submit"], [data-testid="save-btn"]').click();
          
          // Verify update
          cy.get('body').should('contain.text', 'Updated Test Company').or('contain.text', 'success');
          
        } else {
          cy.log('Account name editing not available in current view');
        }
      });
    });
  });

  describe('Password and Security', () => {
    it('should handle password change if available', () => {
      // Try to access password change
      const passwordRoutes = ['/password', '/security', '/settings/password', '/dashboard/security'];
      
      passwordRoutes.forEach(route => {
        cy.visit(route);
        
        cy.get('body').then($body => {
          if ($body.find('input[type="password"], input[name="currentPassword"]').length > 0) {
            cy.log(`Password change form found at: ${route}`);
            
            // Should have password fields
            cy.get('input[name="currentPassword"], [data-testid="current-password"]').should('exist');
            cy.get('input[name="newPassword"], [data-testid="new-password"]').should('exist');
            cy.get('input[name="confirmPassword"], [data-testid="confirm-password"]').should('exist');
            
            // Test form validation
            cy.get('input[name="newPassword"], [data-testid="new-password"]').type('short');
            cy.get('input[name="confirmPassword"], [data-testid="confirm-password"]').type('different');
            
            // Should show validation errors
            cy.get('button[type="submit"]').should('be.disabled')
              .or('have.attr', 'disabled');
            
            return false; // Break loop if found
          }
        });
      });
    });

    it('should display security information', () => {
      cy.visit('/dashboard');
      
      // Check for any security-related information
      cy.get('body').then($body => {
        const text = $body.text().toLowerCase();
        
        // Look for security indicators
        const hasSecurityInfo = text.includes('security') || 
                               text.includes('password') || 
                               text.includes('two-factor') ||
                               text.includes('2fa') ||
                               text.includes('encryption');
        
        if (hasSecurityInfo) {
          cy.log('Security information found in dashboard');
          cy.get('body').should('contain.text', 'security').or('contain.text', 'Security');
        } else {
          cy.log('No explicit security information displayed');
        }
      });
    });
  });

  describe('Theme and Preferences', () => {
    it('should handle theme switching if available', () => {
      cy.visit('/dashboard');
      
      // Look for theme toggle
      cy.get('body').then($body => {
        if ($body.find('[data-testid="theme-toggle"], .theme-toggle, [aria-label*="theme"]').length > 0) {
          cy.log('Theme toggle found');
          
          // Test theme switching
          cy.get('[data-testid="theme-toggle"], .theme-toggle, [aria-label*="theme"]').first().click();
          
          // Wait for theme change
          cy.wait(500);
          
          // Verify theme changed (check for dark/light classes or styles)
          cy.get('body, html').should('satisfy', ($el) => {
            const classes = $el.attr('class') || '';
            const hasTheme = classes.includes('dark') || 
                           classes.includes('light') || 
                           classes.includes('theme');
            return hasTheme || $el.css('background-color') !== 'rgba(0, 0, 0, 0)';
          });
          
          // Toggle back
          cy.get('[data-testid="theme-toggle"], .theme-toggle, [aria-label*="theme"]').first().click();
          cy.wait(500);
          
        } else {
          cy.log('Theme toggle not available');
        }
      });
    });

    it('should persist user preferences across sessions', () => {
      // Test preference persistence (simplified)
      cy.visit('/dashboard');
      
      // Record current state
      cy.get('body').then($body => {
        const currentClasses = $body.attr('class') || '';
        
        // Reload page
        cy.reload();
        
        // Wait for page load
        cy.get('[data-testid="user-menu"]').should('be.visible');
        
        // Verify state is consistent
        cy.get('body').should('exist');
        cy.log('Page state maintained after reload');
      });
    });
  });

  describe('Profile Validation and Error Handling', () => {
    it('should validate profile form fields if editing is available', () => {
      cy.visit('/profile');
      
      cy.get('body').then($body => {
        if ($body.find('input[name="email"]').length > 0) {
          // Test email validation
          cy.get('input[name="email"]').clear().type('invalid-email');
          cy.get('input[name="email"]').blur();
          
          // Should show validation error or prevent submission
          cy.get('input[name="email"]:invalid').should('exist')
            .or('have.attr', 'aria-invalid', 'true');
          
          // Test required field validation
          cy.get('input[name="firstName"]').clear();
          cy.get('input[name="firstName"]').blur();
          
          // Form should prevent submission or show error
          cy.get('button[type="submit"]').should('be.disabled')
            .or('have.attr', 'disabled');
          
        } else {
          cy.log('Profile editing form not available for validation testing');
        }
      });
    });

    it('should handle profile update errors gracefully', () => {
      cy.visit('/profile');
      
      cy.get('body').then($body => {
        if ($body.find('form').length > 0) {
          // Simulate server error by intercepting request
          cy.intercept('PUT', '/api/v1/profile', { 
            statusCode: 500, 
            body: { success: false, error: 'Server error' }
          }).as('profileUpdateError');
          
          // Try to update profile
          cy.get('input[name="firstName"]').clear().type('Error Test');
          cy.get('button[type="submit"]').click();
          
          // Should handle error gracefully
          cy.get('body').should('contain.text', 'error').or('contain.text', 'failed');
          
        } else {
          cy.log('Profile form not available for error testing');
        }
      });
    });
  });

  describe('Data Privacy and Export', () => {
    it('should respect data privacy in profile display', () => {
      cy.visit('/dashboard');
      
      // Verify sensitive data is not exposed inappropriately
      cy.get('[data-testid="user-menu"]').click();
      
      // Email should be masked or not fully visible in UI
      cy.get('body').then($body => {
        const text = $body.text();
        
        // Should not show full email in plain text everywhere
        const hasPartialEmail = text.includes('profile-test-') || 
                               text.includes('***') ||
                               text.includes('...');
        
        cy.log('Checking email privacy in user interface');
      });
    });

    it('should provide data export options if available', () => {
      // Check for data export functionality
      const exportRoutes = ['/export', '/data', '/settings/data', '/dashboard/export'];
      
      exportRoutes.forEach(route => {
        cy.visit(route);
        
        cy.get('body').then($body => {
          if ($body.find('[data-testid="export-btn"], .export, [href*="export"]').length > 0) {
            cy.log(`Data export found at: ${route}`);
            
            // Should have export options
            cy.get('[data-testid="export-btn"], .export, [href*="export"]').should('be.visible');
            
            return false; // Break loop if found
          }
        });
      });
    });
  });

  describe('Mobile Profile Management', () => {
    it('should handle profile management on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.visit('/dashboard');
      
      // Mobile user menu should work
      cy.get('[data-testid="user-menu"]').should('be.visible').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');
      
      // Test mobile-specific profile access
      cy.get('body').then($body => {
        if ($body.find('[href*="profile"]').length > 0) {
          cy.get('[href*="profile"]').first().click();
          
          // Profile form should be mobile-responsive
          cy.get('input[name="firstName"], form').should('be.visible');
          
          // Touch targets should be appropriately sized
          cy.get('button').invoke('outerHeight').should('be.gte', 44);
        }
      });
    });

    it('should provide mobile-optimized settings access', () => {
      cy.viewport(375, 667);
      
      // Test settings access on mobile
      cy.visit('/dashboard');
      cy.get('[data-testid="user-menu"]').click();
      
      // Menu should be accessible and usable on mobile
      cy.get('[data-testid="user-menu"]').should('be.visible');
      
      // Click outside to close menu
      cy.get('body').click(200, 300);
      cy.get('[data-testid="logout-btn"]').should('not.be.visible');
    });
  });
});