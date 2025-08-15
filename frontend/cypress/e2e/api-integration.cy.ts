describe('API Integration Tests', () => {
  const timestamp = Date.now();

  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Authentication API', () => {
    it('should handle registration API correctly', () => {
      const userData = {
        email: `api-reg-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Registration',
        accountName: 'API Registration Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };

      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData
      }).then((response) => {
        expect([200, 201]).to.include(response.status);
        expect(response.body.success).to.be.true;
        expect(response.body.user).to.exist;
        expect(response.body.user.email).to.eq(userData.email);
        expect(response.body.user.firstName).to.eq(userData.firstName);
        expect(response.body.user.lastName).to.eq(userData.lastName);
        expect(response.body.access_token).to.exist;
        expect(response.body.refresh_token).to.exist;
        
        // User should be email verified automatically in test mode
        expect(response.body.user.emailVerified).to.be.true;
        
        // Account information should be included
        expect(response.body.account).to.exist;
        expect(response.body.account.name).to.eq(userData.accountName);
        
        // Subscription should be created
        expect(response.body.subscription).to.exist;
        expect(response.body.subscription.plan.id).to.eq(userData.planId);
      });
    });

    it('should handle login API correctly', () => {
      const userData = {
        email: `api-login-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Login',
        accountName: 'API Login Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };

      // First register a user
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData
      }).then(() => {
        // Then login
        cy.request({
          method: 'POST',
          url: `${Cypress.env('apiUrl')}/auth/login`,
          body: {
            email: userData.email,
            password: userData.password
          }
        }).then((response) => {
          expect(response.status).to.eq(200);
          expect(response.body.success).to.be.true;
          expect(response.body.user.email).to.eq(userData.email);
          expect(response.body.access_token).to.exist;
          expect(response.body.refresh_token).to.exist;
        });
      });
    });

    it('should handle current user API correctly', () => {
      const userData = {
        email: `api-me-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Me',
        accountName: 'API Me Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };

      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData
      }).then((response) => {
        const token = response.body.access_token;
        
        // Test the /me endpoint
        cy.request({
          method: 'GET',
          url: `${Cypress.env('apiUrl')}/auth/me`,
          headers: {
            Authorization: `Bearer ${token}`
          }
        }).then((meResponse) => {
          expect(meResponse.status).to.eq(200);
          expect(meResponse.body.success).to.be.true;
          expect(meResponse.body.user.email).to.eq(userData.email);
          expect(meResponse.body.user.firstName).to.eq(userData.firstName);
          expect(meResponse.body.account).to.exist;
        });
      });
    });

    it('should handle logout API correctly', () => {
      const userData = {
        email: `api-logout-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Logout',
        accountName: 'API Logout Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };

      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData
      }).then((response) => {
        const token = response.body.access_token;
        
        // Test logout
        cy.request({
          method: 'POST',
          url: `${Cypress.env('apiUrl')}/auth/logout`,
          headers: {
            Authorization: `Bearer ${token}`
          }
        }).then((logoutResponse) => {
          expect([200, 204]).to.include(logoutResponse.status);
          
          // Token should no longer work
          cy.request({
            method: 'GET',
            url: `${Cypress.env('apiUrl')}/auth/me`,
            headers: {
              Authorization: `Bearer ${token}`
            },
            failOnStatusCode: false
          }).then((meResponse) => {
            expect(meResponse.status).to.eq(401);
          });
        });
      });
    });
  });

  describe('Plans API', () => {
    it('should fetch public plans correctly', () => {
      cy.request({
        method: 'GET',
        url: `${Cypress.env('apiUrl')}/public/plans`
      }).then((response) => {
        expect(response.status).to.eq(200);
        expect(response.body.success).to.be.true;
        expect(response.body.data.plans).to.be.an('array');
        expect(response.body.data.plans.length).to.be.greaterThan(0);
        
        // Each plan should have required fields
        response.body.data.plans.forEach((plan: any) => {
          expect(plan.id).to.exist;
          expect(plan.name).to.exist;
          expect(plan.price_cents).to.exist;
          expect(plan.currency).to.exist;
          expect(plan.billing_cycle).to.exist;
          expect(plan.is_public).to.be.true;
        });
      });
    });

    it('should handle invalid plan ID in registration', () => {
      const userData = {
        email: `invalid-plan-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Invalid',
        lastName: 'Plan',
        accountName: 'Invalid Plan Co',
        planId: 'invalid-plan-id',
        billingCycle: 'monthly'
      };

      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData,
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.be.oneOf([400, 404, 422]);
        expect(response.body.success).to.be.false;
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid email format', () => {
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: {
          email: 'invalid-email',
          password: 'Qx7#mK9@pL2$nZ6%',
          firstName: 'Invalid',
          lastName: 'Email',
          accountName: 'Invalid Email Co',
          planId: '01989991-0039-7f0f-ae0b-702330e26324',
          billingCycle: 'monthly'
        },
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.be.oneOf([400, 422]);
        expect(response.body.success).to.be.false;
        expect(response.body.error).to.contain('email');
      });
    });

    it('should handle weak passwords', () => {
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: {
          email: `weak-pass-${timestamp}@example.com`,
          password: '123',
          firstName: 'Weak',
          lastName: 'Password',
          accountName: 'Weak Password Co',
          planId: '01989991-0039-7f0f-ae0b-702330e26324',
          billingCycle: 'monthly'
        },
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.eq(422);
        expect(response.body.success).to.be.false;
        expect(response.body.error).to.contain('Password');
      });
    });

    it('should handle duplicate email registration', () => {
      const userData = {
        email: `duplicate-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Duplicate',
        lastName: 'User',
        accountName: 'Duplicate Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };

      // Register first user
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/register`,
        body: userData
      }).then(() => {
        // Try to register again with same email
        cy.request({
          method: 'POST',
          url: `${Cypress.env('apiUrl')}/auth/register`,
          body: {
            ...userData,
            firstName: 'Another',
            accountName: 'Another Co'
          },
          failOnStatusCode: false
        }).then((response) => {
          expect(response.status).to.eq(422);
          expect(response.body.success).to.be.false;
          expect(response.body.error).to.contain('already been taken');
        });
      });
    });

    it('should handle invalid login credentials', () => {
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/login`,
        body: {
          email: 'nonexistent@example.com',
          password: 'wrongpassword'
        },
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.be.oneOf([401, 422]);
        expect(response.body.success).to.be.false;
      });
    });

    it('should handle unauthorized requests', () => {
      cy.request({
        method: 'GET',
        url: `${Cypress.env('apiUrl')}/auth/me`,
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.eq(401);
      });

      cy.request({
        method: 'GET',
        url: `${Cypress.env('apiUrl')}/auth/me`,
        headers: {
          Authorization: 'Bearer invalid-token'
        },
        failOnStatusCode: false
      }).then((response) => {
        expect(response.status).to.eq(401);
      });
    });
  });

  describe('API Response Format', () => {
    it('should have consistent response format', () => {
      cy.request({
        method: 'GET',
        url: `${Cypress.env('apiUrl')}/public/plans`
      }).then((response) => {
        expect(response.body).to.have.property('success');
        expect(response.body).to.have.property('data');
        expect(response.body.success).to.be.true;
      });
    });

    it('should include proper error format', () => {
      cy.request({
        method: 'POST',
        url: `${Cypress.env('apiUrl')}/auth/login`,
        body: {
          email: 'invalid',
          password: 'invalid'
        },
        failOnStatusCode: false
      }).then((response) => {
        expect(response.body).to.have.property('success');
        expect(response.body).to.have.property('error');
        expect(response.body.success).to.be.false;
      });
    });
  });

  describe('API Performance', () => {
    it('should respond within reasonable time', () => {
      const startTime = Date.now();
      
      cy.request({
        method: 'GET',
        url: `${Cypress.env('apiUrl')}/public/plans`
      }).then((response) => {
        const responseTime = Date.now() - startTime;
        cy.log(`API response time: ${responseTime}ms`);
        
        expect(responseTime).to.be.lessThan(5000);
        expect(response.status).to.eq(200);
      });
    });

    it('should handle concurrent requests', () => {
      const requests = Array.from({ length: 5 }, (_, i) => 
        cy.request({
          method: 'GET',
          url: `${Cypress.env('apiUrl')}/public/plans`
        })
      );

      Promise.all(requests).then((responses) => {
        responses.forEach((response) => {
          expect(response.status).to.eq(200);
          expect(response.body.success).to.be.true;
        });
      });
    });
  });
});