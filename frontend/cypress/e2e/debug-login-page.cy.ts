describe('Debug Login Page Structure', () => {
  it('should examine the actual login page structure', () => {
    cy.clearAppData();
    cy.visit('/login');
    
    // Log the entire page structure
    cy.get('body').then($body => {
      console.log('=== LOGIN PAGE ANALYSIS ===');
      console.log('Page title:', $body.find('title').text() || document.title);
      console.log('Page URL:', window.location.href);
      console.log('Body text (first 200 chars):', $body.text().substring(0, 200));
      
      // Find all forms
      const forms = $body.find('form');
      console.log('Number of forms found:', forms.length);
      
      // Find all inputs
      const inputs = $body.find('input');
      console.log('Number of inputs found:', inputs.length);
      
      inputs.each((index, input) => {
        const $input = Cypress.$(input);
        console.log(`Input ${index}:`, {
          type: $input.attr('type'),
          name: $input.attr('name'),
          id: $input.attr('id'),
          placeholder: $input.attr('placeholder'),
          className: $input.attr('class')
        });
      });
      
      // Find all buttons
      const buttons = $body.find('button');
      console.log('Number of buttons found:', buttons.length);
      
      buttons.each((index, button) => {
        const $button = Cypress.$(button);
        console.log(`Button ${index}:`, {
          type: $button.attr('type'),
          text: $button.text(),
          className: $button.attr('class'),
          disabled: $button.prop('disabled')
        });
      });
    });
    
    // Wait a moment to see if anything loads dynamically
    cy.wait(2000);
    
    // Check again after potential async loading
    cy.get('body').then($body => {
      console.log('=== AFTER 2 SECOND DELAY ===');
      const inputs = $body.find('input');
      console.log('Inputs after delay:', inputs.length);
      
      const buttons = $body.find('button');
      console.log('Buttons after delay:', buttons.length);
      
      // Look specifically for email and password inputs
      const emailInputs = $body.find('input[type="email"], input[name="email"]');
      const passwordInputs = $body.find('input[type="password"], input[name="password"]');
      
      console.log('Email inputs found:', emailInputs.length);
      console.log('Password inputs found:', passwordInputs.length);
      
      if (emailInputs.length === 0) {
        console.log('❌ NO EMAIL INPUT FOUND');
        console.log('Available input types:', Array.from(inputs).map(i => Cypress.$(i).attr('type')));
      }
      
      if (passwordInputs.length === 0) {
        console.log('❌ NO PASSWORD INPUT FOUND');
      }
      
      // Check if we're actually on a login page
      const bodyText = $body.text().toLowerCase();
      const hasLoginText = bodyText.includes('login') || bodyText.includes('sign in');
      console.log('Has login-related text:', hasLoginText);
      
      if (!hasLoginText) {
        console.log('❌ PAGE DOES NOT APPEAR TO BE LOGIN PAGE');
        console.log('Current URL:', window.location.href);
        console.log('Page appears to be:', bodyText.substring(0, 100));
      }
    });
  });

  it('should test actual login attempt to see real error behavior', () => {
    cy.clearAppData();
    cy.visit('/login');
    
    // Wait for page to load
    cy.get('body').should('be.visible');
    
    // Try to find and use the actual login form
    cy.get('body').then($body => {
      const emailInputs = $body.find('input[type="email"], input[name="email"]');
      const passwordInputs = $body.find('input[type="password"], input[name="password"]');
      
      if (emailInputs.length > 0 && passwordInputs.length > 0) {
        console.log('✅ Found login form elements');
        
        // Fill with wrong credentials
        cy.get(emailInputs.first()).type('wrong@example.com');
        cy.get(passwordInputs.first()).type('wrongpassword');
        
        // Find submit button
        const submitButtons = $body.find('button[type="submit"], button:contains("Login"), button:contains("Sign")');
        
        if (submitButtons.length > 0) {
          console.log('✅ Found submit button');
          
          // Intercept the login request to see what actually happens
          cy.intercept('POST', '/api/v1/**').as('loginRequest');
          
          cy.get(submitButtons.first()).click();
          
          // Wait for request and log response
          cy.wait('@loginRequest', { timeout: 10000 }).then((interception) => {
            console.log('=== LOGIN REQUEST DETAILS ===');
            console.log('URL:', interception.request.url);
            console.log('Method:', interception.request.method);
            console.log('Request body:', interception.request.body);
            console.log('Response status:', interception.response?.statusCode);
            console.log('Response body:', interception.response?.body);
          });
          
          // Check what happens after submit
          cy.wait(3000);
          cy.url().then(url => {
            console.log('URL after login attempt:', url);
          });
          
          cy.get('body').then($afterBody => {
            console.log('=== AFTER LOGIN ATTEMPT ===');
            console.log('Body text (first 200 chars):', $afterBody.text().substring(0, 200));
            
            // Look for any error elements that might exist
            const possibleErrorElements = [
              '.error', '.alert', '.notification', '.message', '.toast',
              '[role="alert"]', '.text-red', '.text-danger', '.invalid',
              '.form-error', '.field-error'
            ];
            
            possibleErrorElements.forEach(selector => {
              const elements = $afterBody.find(selector);
              if (elements.length > 0) {
                console.log(`Found ${selector}:`, elements.length, elements.text());
              }
            });
            
            // Check form state
            const emailValue = $afterBody.find('input[type="email"], input[name="email"]').val();
            const passwordValue = $afterBody.find('input[type="password"], input[name="password"]').val();
            
            console.log('Email field value after submit:', emailValue);
            console.log('Password field value after submit:', passwordValue);
          });
          
        } else {
          console.log('❌ NO SUBMIT BUTTON FOUND');
        }
        
      } else {
        console.log('❌ LOGIN FORM NOT FOUND');
        console.log('Email inputs:', emailInputs.length);
        console.log('Password inputs:', passwordInputs.length);
      }
    });
  });
});