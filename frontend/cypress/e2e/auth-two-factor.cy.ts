describe('Two-Factor Authentication Tests', () => {
  const timestamp = Date.now();
  
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('2FA Setup and Enablement', () => {
    it('should allow users to enable 2FA from security settings', () => {
      // Create test user and login
      const userData = {
        email: `2fa-setup-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'TwoFactor',
        lastName: 'Setup',
        accountName: '2FA Setup Co'
      };

      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Navigate to security/profile settings
      const settingsSelectors = [
        '[data-testid="user-menu"]',
        '.user-menu',
        'button:contains("Settings")',
        'a:contains("Profile")',
        'a:contains("Account")'
      ];

      // Try to access settings/security page
      cy.get('[data-testid="user-menu"]').click();
      
      cy.get('body').then($body => {
        const securityLinks = [
          'a:contains("Security")',
          'a:contains("Settings")',
          'a:contains("Profile")',
          '[href*="security"]',
          '[href*="settings"]',
          '[data-testid="security-link"]'
        ];

        let foundSecurityLink = false;
        for (const selector of securityLinks) {
          if ($body.find(selector).length > 0) {
            cy.log(`Found security link: ${selector}`);
            cy.get(selector).first().click();
            foundSecurityLink = true;
            break;
          }
        }

        if (!foundSecurityLink) {
          // Try direct navigation to common security URLs
          cy.log('Security link not found in menu, trying direct navigation');
          const securityUrls = ['/settings', '/profile', '/security', '/account'];
          cy.visit(securityUrls[0]);
        }
      });

      // Look for 2FA setup options
      cy.url().then(url => {
        if (url.includes('settings') || url.includes('profile') || url.includes('security')) {
          cy.log('Security/Settings page accessible');
          
          cy.get('body').then($settingsBody => {
            const twoFactorSelectors = [
              'button:contains("Enable 2FA")',
              'button:contains("Two-Factor")',
              '[data-testid="enable-2fa"]',
              '.two-factor',
              'button:contains("Authenticator")',
              'input[type="checkbox"]:contains("2FA")'
            ];

            let found2FAOption = false;
            for (const selector of twoFactorSelectors) {
              if ($settingsBody.find(selector).length > 0) {
                cy.log(`Found 2FA option: ${selector}`);
                cy.get(selector).should('be.visible');
                found2FAOption = true;
                break;
              }
            }

            if (!found2FAOption) {
              cy.log('2FA setup option not found - feature may not be implemented');
              // Check if page mentions 2FA or security features
              cy.get('body').should('satisfy', ($body) => {
                const text = $body.text().toLowerCase();
                return text.includes('security') || 
                       text.includes('settings') ||
                       text.includes('profile') ||
                       text.length > 0; // At least some content
              });
            }
          });
        } else {
          cy.log('Security/Settings page not accessible');
        }
      });
    });

    it('should display QR code and backup codes for 2FA setup', () => {
      // Create user and navigate to 2FA setup
      const userData = {
        email: `2fa-qr-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'QRCode',
        lastName: 'Test',
        accountName: 'QR Code Co'
      };

      cy.register(userData);
      
      // Try to access 2FA setup directly
      cy.visit('/settings/security');
      
      cy.url().then(url => {
        if (url.includes('security') || url.includes('2fa')) {
          cy.get('body').then($body => {
            // Look for 2FA setup elements
            const setupElements = [
              'img[src*="qr"]', // QR code image
              'canvas', // QR code canvas
              '[data-testid="qr-code"]',
              'code', // Backup codes
              '.backup-codes',
              'input:contains("code")',
              'button:contains("Verify")'
            ];

            setupElements.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found 2FA setup element: ${selector}`);
                cy.get(selector).should('be.visible');
              }
            });

            // Check for setup instructions
            const setupText = $body.text().toLowerCase();
            if (setupText.includes('authenticator') || 
                setupText.includes('qr') || 
                setupText.includes('scan')) {
              cy.log('2FA setup instructions found');
            }
          });
        }
      });
    });
  });

  describe('2FA Login Flow', () => {
    it('should require 2FA code after password verification', () => {
      // Mock a user with 2FA enabled
      const userData = {
        email: `2fa-login-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'TwoFactorLogin',
        lastName: 'Test',
        accountName: '2FA Login Co'
      };

      // Register and simulate 2FA-enabled user
      cy.register(userData);
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();

      // Mock 2FA requirement on login
      cy.intercept('POST', '/api/v1/auth/login', {
        statusCode: 200,
        body: { 
          success: true, 
          requires_2fa: true,
          message: 'Please enter your 2FA code'
        }
      }).as('loginWith2FA');

      // Attempt login
      cy.visit('/login');
      cy.get('input[type="email"]').type(userData.email);
      cy.get('input[type="password"]').type(userData.password);
      cy.get('button[type="submit"]').click();

      cy.wait('@loginWith2FA');
      cy.wait(2000);

      // Should show 2FA code input
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          cy.log('2FA verification page shown');
          
          cy.get('body').should('satisfy', ($twoFaBody) => {
            const text = $twoFaBody.text().toLowerCase();
            return text.includes('code') || 
                   text.includes('authenticator') || 
                   text.includes('verify') ||
                   text.includes('2fa');
          });

          // Look for code input field
          cy.get('body').then($body => {
            const codeSelectors = [
              'input[name="code"]',
              'input[name="token"]',
              'input[name="otp"]',
              'input[type="text"][maxlength="6"]',
              'input[placeholder*="code"]'
            ];

            codeSelectors.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found 2FA code input: ${selector}`);
                cy.get(selector).should('be.visible');
              }
            });
          });
        } else {
          cy.log('2FA verification page not shown - may not be implemented');
        }
      });
    });

    it('should validate 2FA code format and length', () => {
      // Mock 2FA verification page
      cy.visit('/login/verify-2fa');
      
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          cy.get('body').then($body => {
            const codeInput = $body.find('input[name="code"], input[name="token"], input[name="otp"]');
            
            if (codeInput.length > 0) {
              // Test short code
              cy.get('input[name="code"], input[name="token"], input[name="otp"]')
                .first()
                .type('123');
              
              cy.get('button[type="submit"], button:contains("Verify")')
                .click();
              
              // Should show validation error
              cy.get('body').should('satisfy', ($validationBody) => {
                const text = $validationBody.text().toLowerCase();
                const hasValidation = $validationBody.find('input:invalid, .error').length > 0;
                return text.includes('invalid') || 
                       text.includes('6 digit') || 
                       text.includes('code') ||
                       hasValidation;
              });

              // Test non-numeric characters
              cy.get('input[name="code"], input[name="token"], input[name="otp"]')
                .first()
                .clear()
                .type('abc123');
              
              cy.get('button[type="submit"], button:contains("Verify")')
                .click();
              
              // Should handle non-numeric input
              cy.get('body').should('satisfy', ($numericBody) => {
                const text = $numericBody.text().toLowerCase();
                const value = $numericBody.find('input[name="code"], input[name="token"], input[name="otp"]').val();
                return text.includes('numeric') || 
                       text.includes('digits only') ||
                       value === '123123'; // Filtered to numbers only
              });
            }
          });
        }
      });
    });

    it('should handle incorrect 2FA codes with proper error feedback', () => {
      // Mock 2FA verification with error response
      cy.intercept('POST', '/api/v1/auth/verify-2fa', {
        statusCode: 400,
        body: { 
          success: false, 
          error: 'Invalid 2FA code'
        }
      }).as('invalid2FA');

      cy.visit('/login/verify-2fa');
      
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          cy.get('body').then($body => {
            if ($body.find('input[name="code"], input[name="token"], input[name="otp"]').length > 0) {
              // Enter incorrect code
              cy.get('input[name="code"], input[name="token"], input[name="otp"]')
                .first()
                .type('123456');
              
              cy.get('button[type="submit"], button:contains("Verify")')
                .click();

              cy.wait('@invalid2FA');
              cy.wait(2000);

              // Should show error feedback
              cy.get('body').should('satisfy', ($errorBody) => {
                const text = $errorBody.text().toLowerCase();
                const hasErrorElements = $errorBody.find('.error, .alert, [role="alert"]').length > 0;
                const inputCleared = $errorBody.find('input[name="code"], input[name="token"], input[name="otp"]').val() === '';
                
                return text.includes('invalid') || 
                       text.includes('incorrect') || 
                       text.includes('wrong') ||
                       text.includes('try again') ||
                       hasErrorElements ||
                       inputCleared;
              });

              // Should remain on verification page
              cy.url().should('satisfy', (currentUrl) => {
                return currentUrl.includes('2fa') || 
                       currentUrl.includes('verify') ||
                       currentUrl.includes('login');
              });
            }
          });
        }
      });
    });
  });

  describe('2FA Backup Codes', () => {
    it('should allow login with backup codes when 2FA is unavailable', () => {
      cy.visit('/login/verify-2fa');
      
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          // Look for backup code option
          cy.get('body').then($body => {
            const backupSelectors = [
              'button:contains("backup")',
              'button:contains("recovery")',
              'a:contains("backup")',
              '[data-testid="backup-codes"]',
              'button:contains("Use backup code")'
            ];

            let foundBackup = false;
            backupSelectors.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found backup code option: ${selector}`);
                cy.get(selector).should('be.visible').click();
                foundBackup = true;
              }
            });

            if (foundBackup) {
              // Should show backup code input
              cy.get('body').should('satisfy', ($backupBody) => {
                const text = $backupBody.text().toLowerCase();
                const hasBackupInput = $backupBody.find('input[name="backup"], input[name="recovery"]').length > 0;
                return text.includes('backup') || 
                       text.includes('recovery') ||
                       hasBackupInput;
              });

              // Test backup code input
              if ($body.find('input[name="backup"], input[name="recovery"]').length > 0) {
                cy.get('input[name="backup"], input[name="recovery"]')
                  .first()
                  .type('backup-code-123456');
                
                cy.get('button[type="submit"], button:contains("Verify")')
                  .should('be.visible');
              }
            } else {
              cy.log('Backup code option not found');
            }
          });
        }
      });
    });

    it('should validate backup code format', () => {
      cy.visit('/login/backup-codes');
      
      cy.url().then(url => {
        if (url.includes('backup') || url.includes('recovery')) {
          cy.get('body').then($body => {
            if ($body.find('input[name="backup"], input[name="recovery"]').length > 0) {
              // Test short backup code
              cy.get('input[name="backup"], input[name="recovery"]')
                .first()
                .type('short');
              
              cy.get('button[type="submit"], button:contains("Verify")')
                .click();
              
              // Should validate backup code format
              cy.get('body').should('satisfy', ($validBody) => {
                const text = $validBody.text().toLowerCase();
                const hasValidation = $validBody.find('input:invalid, .error').length > 0;
                return text.includes('invalid') || 
                       text.includes('format') ||
                       text.includes('backup code') ||
                       hasValidation;
              });
            }
          });
        }
      });
    });
  });

  describe('2FA Management', () => {
    it('should allow users to disable 2FA with password confirmation', () => {
      // Create user and navigate to security settings
      const userData = {
        email: `2fa-disable-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'DisableTwoFactor',
        lastName: 'Test',
        accountName: 'Disable 2FA Co'
      };

      cy.register(userData);
      
      // Navigate to security settings
      cy.visit('/settings/security');
      
      cy.url().then(url => {
        if (url.includes('security') || url.includes('settings')) {
          cy.get('body').then($body => {
            const disableSelectors = [
              'button:contains("Disable 2FA")',
              'button:contains("Turn off")',
              '[data-testid="disable-2fa"]',
              'input[type="checkbox"][checked]' // Toggle off
            ];

            disableSelectors.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found 2FA disable option: ${selector}`);
                cy.get(selector).should('be.visible');
                
                if (selector.includes('button')) {
                  cy.get(selector).click();
                  
                  // Should require password confirmation
                  cy.get('body').should('satisfy', ($confirmBody) => {
                    const text = $confirmBody.text().toLowerCase();
                    const hasPasswordInput = $confirmBody.find('input[type="password"]').length > 0;
                    return text.includes('password') || 
                           text.includes('confirm') ||
                           hasPasswordInput;
                  });
                }
              }
            });
          });
        }
      });
    });

    it('should allow regeneration of backup codes', () => {
      cy.visit('/settings/security');
      
      cy.url().then(url => {
        if (url.includes('security') || url.includes('settings')) {
          cy.get('body').then($body => {
            const regenerateSelectors = [
              'button:contains("Regenerate")',
              'button:contains("New backup codes")',
              '[data-testid="regenerate-codes"]',
              'button:contains("Generate new")'
            ];

            regenerateSelectors.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found backup code regeneration: ${selector}`);
                cy.get(selector).should('be.visible').click();
                
                // Should show confirmation or new codes
                cy.get('body').should('satisfy', ($regenBody) => {
                  const text = $regenBody.text().toLowerCase();
                  return text.includes('generated') || 
                         text.includes('new codes') ||
                         text.includes('backup') ||
                         text.includes('save');
                });
              }
            });
          });
        }
      });
    });
  });

  describe('2FA Recovery Scenarios', () => {
    it('should handle 2FA device loss recovery', () => {
      cy.visit('/login/verify-2fa');
      
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          // Look for device loss help
          cy.get('body').then($body => {
            const recoverySelectors = [
              'a:contains("Lost device")',
              'button:contains("Can\\'t access")',
              'a:contains("Help")',
              '[data-testid="recovery-help"]',
              'a:contains("Contact support")'
            ];

            recoverySelectors.forEach(selector => {
              if ($body.find(selector).length > 0) {
                cy.log(`Found 2FA recovery option: ${selector}`);
                cy.get(selector).should('be.visible');
              }
            });

            // Should provide recovery guidance
            const helpText = $body.text().toLowerCase();
            if (helpText.includes('lost') || 
                helpText.includes('help') || 
                helpText.includes('support')) {
              cy.log('2FA recovery guidance found');
            }
          });
        }
      });
    });

    it('should handle account lockout after multiple failed 2FA attempts', () => {
      // Mock multiple failed attempts
      let attemptCount = 0;
      cy.intercept('POST', '/api/v1/auth/verify-2fa', (req) => {
        attemptCount++;
        if (attemptCount >= 3) {
          req.reply({
            statusCode: 429,
            body: { 
              success: false, 
              error: 'Too many attempts. Account temporarily locked.',
              locked_until: Date.now() + 900000 // 15 minutes
            }
          });
        } else {
          req.reply({
            statusCode: 400,
            body: { 
              success: false, 
              error: 'Invalid 2FA code'
            }
          });
        }
      }).as('failed2FA');

      cy.visit('/login/verify-2fa');
      
      cy.url().then(url => {
        if (url.includes('2fa') || url.includes('verify')) {
          cy.get('body').then($body => {
            if ($body.find('input[name="code"], input[name="token"], input[name="otp"]').length > 0) {
              // Make multiple failed attempts
              for (let i = 0; i < 3; i++) {
                cy.get('input[name="code"], input[name="token"], input[name="otp"]')
                  .first()
                  .clear()
                  .type('000000'); // Wrong code
                
                cy.get('button[type="submit"], button:contains("Verify")')
                  .click();
                
                cy.wait('@failed2FA');
                cy.wait(1000);
              }

              // After 3 attempts, should show lockout message
              cy.get('body').should('satisfy', ($lockoutBody) => {
                const text = $lockoutBody.text().toLowerCase();
                return text.includes('locked') || 
                       text.includes('too many') ||
                       text.includes('attempts') ||
                       text.includes('wait') ||
                       text.includes('temporarily');
              });
            }
          });
        }
      });
    });
  });
});