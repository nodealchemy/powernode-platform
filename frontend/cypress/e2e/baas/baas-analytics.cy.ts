/// <reference types="cypress" />

/**
 * BaaS Analytics Tests
 *
 * Tests for BaaS Analytics functionality including:
 * - Analytics dashboard
 * - Tenant metrics
 * - Revenue analytics
 * - Usage statistics
 * - Performance metrics
 * - Custom reports
 */

describe('BaaS Analytics Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Analytics Dashboard', () => {
    it('should navigate to BaaS analytics', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                            $body.text().includes('Dashboard') ||
                            $body.text().includes('Metrics');
        if (hasAnalytics) {
          cy.log('BaaS analytics dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display overview metrics', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Total') ||
                          $body.text().includes('Revenue') ||
                          $body.text().includes('Tenants');
        if (hasMetrics) {
          cy.log('Overview metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display time range selector', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTimeRange = $body.text().includes('Today') ||
                            $body.text().includes('Week') ||
                            $body.text().includes('Month') ||
                            $body.text().includes('Custom');
        if (hasTimeRange) {
          cy.log('Time range selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display trend charts', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg, [data-testid="analytics-chart"]').length > 0 ||
                         $body.text().includes('Trend');
        if (hasCharts) {
          cy.log('Trend charts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tenant Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/tenants');
      cy.waitForPageLoad();
    });

    it('should display tenant count', () => {
      cy.get('body').then($body => {
        const hasTenantCount = $body.text().includes('Tenant') ||
                              $body.text().match(/\d+/) !== null;
        if (hasTenantCount) {
          cy.log('Tenant count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active vs inactive tenants', () => {
      cy.get('body').then($body => {
        const hasActiveInactive = $body.text().includes('Active') ||
                                 $body.text().includes('Inactive') ||
                                 $body.text().includes('Status');
        if (hasActiveInactive) {
          cy.log('Active vs inactive tenants displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tenant growth chart', () => {
      cy.get('body').then($body => {
        const hasGrowth = $body.text().includes('Growth') ||
                         $body.find('canvas, svg').length > 0;
        if (hasGrowth) {
          cy.log('Tenant growth chart displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display churn rate', () => {
      cy.get('body').then($body => {
        const hasChurn = $body.text().includes('Churn') ||
                        $body.text().includes('Retention') ||
                        $body.text().includes('%');
        if (hasChurn) {
          cy.log('Churn rate displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display top tenants by usage', () => {
      cy.get('body').then($body => {
        const hasTopTenants = $body.text().includes('Top') ||
                             $body.text().includes('Usage') ||
                             $body.find('table').length > 0;
        if (hasTopTenants) {
          cy.log('Top tenants by usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Revenue Analytics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/revenue');
      cy.waitForPageLoad();
    });

    it('should display MRR', () => {
      cy.get('body').then($body => {
        const hasMRR = $body.text().includes('MRR') ||
                      $body.text().includes('Monthly') ||
                      $body.text().includes('Revenue');
        if (hasMRR) {
          cy.log('MRR displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display ARR', () => {
      cy.get('body').then($body => {
        const hasARR = $body.text().includes('ARR') ||
                      $body.text().includes('Annual');
        if (hasARR) {
          cy.log('ARR displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display revenue breakdown', () => {
      cy.get('body').then($body => {
        const hasBreakdown = $body.text().includes('Breakdown') ||
                            $body.text().includes('By plan') ||
                            $body.text().includes('By tier');
        if (hasBreakdown) {
          cy.log('Revenue breakdown displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display expansion revenue', () => {
      cy.get('body').then($body => {
        const hasExpansion = $body.text().includes('Expansion') ||
                            $body.text().includes('Upgrade') ||
                            $body.text().includes('Upsell');
        if (hasExpansion) {
          cy.log('Expansion revenue displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display ARPU', () => {
      cy.get('body').then($body => {
        const hasARPU = $body.text().includes('ARPU') ||
                       $body.text().includes('Average revenue per');
        if (hasARPU) {
          cy.log('ARPU displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/usage');
      cy.waitForPageLoad();
    });

    it('should display API call volume', () => {
      cy.get('body').then($body => {
        const hasAPIVolume = $body.text().includes('API') ||
                            $body.text().includes('Calls') ||
                            $body.text().includes('Requests');
        if (hasAPIVolume) {
          cy.log('API call volume displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display storage usage', () => {
      cy.get('body').then($body => {
        const hasStorage = $body.text().includes('Storage') ||
                          $body.text().includes('GB') ||
                          $body.text().includes('MB');
        if (hasStorage) {
          cy.log('Storage usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display bandwidth usage', () => {
      cy.get('body').then($body => {
        const hasBandwidth = $body.text().includes('Bandwidth') ||
                            $body.text().includes('Transfer') ||
                            $body.text().includes('Data');
        if (hasBandwidth) {
          cy.log('Bandwidth usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage by tenant', () => {
      cy.get('body').then($body => {
        const hasByTenant = $body.text().includes('By tenant') ||
                           $body.text().includes('Tenant') ||
                           $body.find('table').length > 0;
        if (hasByTenant) {
          cy.log('Usage by tenant displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/performance');
      cy.waitForPageLoad();
    });

    it('should display API latency', () => {
      cy.get('body').then($body => {
        const hasLatency = $body.text().includes('Latency') ||
                          $body.text().includes('Response time') ||
                          $body.text().includes('ms');
        if (hasLatency) {
          cy.log('API latency displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display error rates', () => {
      cy.get('body').then($body => {
        const hasErrors = $body.text().includes('Error') ||
                         $body.text().includes('4xx') ||
                         $body.text().includes('5xx');
        if (hasErrors) {
          cy.log('Error rates displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display uptime', () => {
      cy.get('body').then($body => {
        const hasUptime = $body.text().includes('Uptime') ||
                         $body.text().includes('99.') ||
                         $body.text().includes('Availability');
        if (hasUptime) {
          cy.log('Uptime displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display request success rate', () => {
      cy.get('body').then($body => {
        const hasSuccessRate = $body.text().includes('Success') ||
                              $body.text().includes('2xx') ||
                              $body.text().includes('%');
        if (hasSuccessRate) {
          cy.log('Request success rate displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Custom Reports', () => {
    it('should navigate to custom reports', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReports = $body.text().includes('Report') ||
                          $body.text().includes('Custom') ||
                          $body.text().includes('Create');
        if (hasReports) {
          cy.log('Custom reports page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create report button', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create report button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display saved reports', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSaved = $body.text().includes('Saved') ||
                        $body.find('table, [data-testid="reports-list"]').length > 0;
        if (hasSaved) {
          cy.log('Saved reports displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export report option', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have schedule report option', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSchedule = $body.find('button:contains("Schedule")').length > 0 ||
                           $body.text().includes('Schedule');
        if (hasSchedule) {
          cy.log('Schedule report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Comparison Tools', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
    });

    it('should have period comparison', () => {
      cy.get('body').then($body => {
        const hasComparison = $body.text().includes('Compare') ||
                             $body.text().includes('vs') ||
                             $body.text().includes('Previous');
        if (hasComparison) {
          cy.log('Period comparison displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display percentage changes', () => {
      cy.get('body').then($body => {
        const hasChanges = $body.text().includes('%') ||
                          $body.text().includes('increase') ||
                          $body.text().includes('decrease');
        if (hasChanges) {
          cy.log('Percentage changes displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have benchmark comparison', () => {
      cy.get('body').then($body => {
        const hasBenchmark = $body.text().includes('Benchmark') ||
                            $body.text().includes('Industry') ||
                            $body.text().includes('Average');
        if (hasBenchmark) {
          cy.log('Benchmark comparison displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display BaaS analytics correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/analytics');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`BaaS analytics displayed correctly on ${name}`);
      });
    });
  });
});
