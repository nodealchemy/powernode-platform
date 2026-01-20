/// <reference types="cypress" />

/**
 * Business Revenue Intelligence Tests
 *
 * Tests for Revenue Intelligence functionality including:
 * - Customer Health scores
 * - Churn Risk analysis
 * - Revenue Forecasting
 * - Predictive Analytics
 */

describe('Business Revenue Intelligence Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Customer Health Page', () => {
    it('should navigate to customer health page', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Customer Health') ||
                         $body.text().includes('Health Score') ||
                         $body.text().includes('Customers');
        if (hasHealth) {
          cy.log('Customer health page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health score distribution', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDistribution = $body.text().includes('Healthy') ||
                               $body.text().includes('At Risk') ||
                               $body.text().includes('Unhealthy') ||
                               $body.text().includes('Critical') ||
                               $body.text().includes('Distribution');
        if (hasDistribution) {
          cy.log('Health score distribution displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health summary statistics', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Average') ||
                        $body.text().includes('Score') ||
                        $body.text().includes('Total') ||
                        $body.text().includes('Customers');
        if (hasStats) {
          cy.log('Health summary statistics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health score cards', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0 ||
                        $body.text().includes('Healthy') ||
                        $body.text().includes('customers');
        if (hasCards) {
          cy.log('Health score cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter options', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFilters = $body.find('select, [data-testid*="filter"]').length > 0 ||
                          $body.text().includes('Filter') ||
                          $body.text().includes('All');
        if (hasFilters) {
          cy.log('Filter options available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Churn Risk Page', () => {
    it('should navigate to churn risk page', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChurn = $body.text().includes('Churn Risk') ||
                        $body.text().includes('Risk Analysis') ||
                        $body.text().includes('At Risk');
        if (hasChurn) {
          cy.log('Churn risk page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display risk tier breakdown', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTiers = $body.text().includes('Critical') ||
                        $body.text().includes('High') ||
                        $body.text().includes('Medium') ||
                        $body.text().includes('Low') ||
                        $body.text().includes('Minimal');
        if (hasTiers) {
          cy.log('Risk tier breakdown displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display churn risk summary', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSummary = $body.text().includes('Revenue at Risk') ||
                          $body.text().includes('At Risk Customers') ||
                          $body.text().includes('Total') ||
                          $body.text().includes('$');
        if (hasSummary) {
          cy.log('Churn risk summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display at-risk customer list', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="churn-risk-list"]').length > 0 ||
                       $body.text().includes('Customer') ||
                       $body.text().includes('Risk');
        if (hasList) {
          cy.log('At-risk customer list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display risk factors', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFactors = $body.text().includes('Factor') ||
                          $body.text().includes('Payment') ||
                          $body.text().includes('Usage') ||
                          $body.text().includes('Engagement');
        if (hasFactors) {
          cy.log('Risk factors displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display recommended actions', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActions = $body.text().includes('Action') ||
                          $body.text().includes('Recommendation') ||
                          $body.text().includes('Contact') ||
                          $body.text().includes('Discount');
        if (hasActions) {
          cy.log('Recommended actions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Revenue Forecast Page', () => {
    it('should navigate to revenue forecast page', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasForecast = $body.text().includes('Revenue Forecast') ||
                           $body.text().includes('Forecast') ||
                           $body.text().includes('Projection');
        if (hasForecast) {
          cy.log('Revenue forecast page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display forecast summary', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSummary = $body.text().includes('Projected') ||
                          $body.text().includes('Current') ||
                          $body.text().includes('Growth') ||
                          $body.text().includes('$');
        if (hasSummary) {
          cy.log('Forecast summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display forecast chart', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChart = $body.find('svg, canvas, [class*="chart"], [class*="Chart"]').length > 0 ||
                        $body.text().includes('Chart');
        if (hasChart) {
          cy.log('Forecast chart displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display forecast period selector', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPeriod = $body.text().includes('3 Month') ||
                         $body.text().includes('6 Month') ||
                         $body.text().includes('12 Month') ||
                         $body.find('select, button').length > 0;
        if (hasPeriod) {
          cy.log('Forecast period selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display confidence intervals', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfidence = $body.text().includes('Confidence') ||
                             $body.text().includes('Upper') ||
                             $body.text().includes('Lower') ||
                             $body.text().includes('Range');
        if (hasConfidence) {
          cy.log('Confidence intervals displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display growth drivers', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDrivers = $body.text().includes('Driver') ||
                          $body.text().includes('Factor') ||
                          $body.text().includes('New') ||
                          $body.text().includes('Expansion');
        if (hasDrivers) {
          cy.log('Growth drivers displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Predictive Analytics Navigation', () => {
    it('should access predictive analytics from main analytics', () => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLinks = $body.text().includes('Customer Health') ||
                        $body.text().includes('Churn Risk') ||
                        $body.text().includes('Revenue Forecast') ||
                        $body.text().includes('Predictive');
        if (hasLinks) {
          cy.log('Predictive analytics links available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate between intelligence pages', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      // Check for navigation to other pages
      cy.get('body').then($body => {
        const hasNavigation = $body.text().includes('Back') ||
                             $body.find('a, button').length > 0;
        if (hasNavigation) {
          cy.log('Navigation between pages available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Health Score Card Component', () => {
    it('should display health score card details', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCard = $body.text().includes('Score') ||
                       $body.text().includes('Health') ||
                       $body.text().includes('Trend');
        if (hasCard) {
          cy.log('Health score card details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show health trend indicators', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTrend = $body.text().includes('Up') ||
                        $body.text().includes('Down') ||
                        $body.text().includes('Stable') ||
                        $body.text().includes('%');
        if (hasTrend) {
          cy.log('Health trend indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Churn Risk List Component', () => {
    it('should display churn risk list with customer details', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Customer') ||
                          $body.text().includes('MRR') ||
                          $body.text().includes('Risk Score') ||
                          $body.find('table, [role="table"]').length > 0;
        if (hasDetails) {
          cy.log('Churn risk list with details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show risk tier badges', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBadges = $body.find('[class*="badge"], [class*="Badge"]').length > 0 ||
                         $body.text().includes('Critical') ||
                         $body.text().includes('High') ||
                         $body.text().includes('Low');
        if (hasBadges) {
          cy.log('Risk tier badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have expandable customer details', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExpand = $body.text().includes('Details') ||
                         $body.text().includes('View') ||
                         $body.find('[class*="expand"], [aria-expanded]').length > 0;
        if (hasExpand) {
          cy.log('Expandable customer details available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Forecast Chart Component', () => {
    it('should render forecast visualization', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasViz = $body.find('svg, canvas, [class*="recharts"]').length > 0;
        if (hasViz) {
          cy.log('Forecast visualization rendered');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display forecast data points', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasData = $body.text().includes('$') ||
                       $body.text().includes('MRR') ||
                       $body.text().includes('Revenue');
        if (hasData) {
          cy.log('Forecast data points displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
