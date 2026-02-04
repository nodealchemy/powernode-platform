import { Page, Locator, expect } from '@playwright/test';
import { ROUTES } from '../../fixtures/test-data';

/**
 * AI Monitoring Page Object Model
 *
 * Encapsulates monitoring dashboard interactions for Playwright tests.
 * Corresponds to manual testing Phase 10: Monitoring
 */
export class MonitoringPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly overviewTab: Locator;
  readonly providersTab: Locator;
  readonly agentsTab: Locator;
  readonly workflowsTab: Locator;
  readonly alertsTab: Locator;
  readonly realTimeToggle: Locator;
  readonly refreshButton: Locator;
  readonly timeRangeSelector: Locator;
  readonly statusIndicator: Locator;
  readonly overviewCards: Locator;
  readonly alertBadge: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();

    // Tab navigation
    this.overviewTab = page.locator('[role="tab"]:has-text("Overview"), button:has-text("Overview")');
    this.providersTab = page.locator('[role="tab"]:has-text("Providers"), button:has-text("Providers")');
    this.agentsTab = page.locator('[role="tab"]:has-text("Agents"), button:has-text("Agents")');
    this.workflowsTab = page.locator('[role="tab"]:has-text("Workflows"), button:has-text("Workflows")');
    this.alertsTab = page.locator('[role="tab"]:has-text("Alerts"), button:has-text("Alerts")');

    // Controls
    this.realTimeToggle = page.getByRole('button', { name: /real-time|enable|disable/i });
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.timeRangeSelector = page.locator('select, button:has-text("1h"), button:has-text("24h"), button:has-text("7d")');

    // Status
    this.statusIndicator = page.locator('[class*="status"], [class*="connection"]');
    this.overviewCards = page.locator('[class*="card"], [class*="Card"], [class*="stat"]');
    this.alertBadge = page.locator('[class*="badge"], [class*="count"]');
  }

  /**
   * Navigate to monitoring page
   */
  async goto() {
    await this.page.goto(ROUTES.monitoring);
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for page to be ready
   */
  async waitForReady() {
    await this.page.waitForSelector('main, [role="main"]', { timeout: 10000 });
  }

  /**
   * Verify page loaded successfully
   */
  async verifyPageLoaded() {
    await expect(this.page.locator('body')).toContainText(/monitoring/i);
  }

  /**
   * Verify overview dashboard is displayed
   */
  async verifyOverviewDashboard() {
    await expect(this.overviewCards.first()).toBeVisible();
  }

  /**
   * Click overview tab
   */
  async clickOverviewTab() {
    await this.overviewTab.click();
  }

  /**
   * Click providers tab
   */
  async clickProvidersTab() {
    await this.providersTab.click();
  }

  /**
   * Verify provider health grid is displayed
   */
  async verifyProviderHealthGrid() {
    await expect(
      this.page.locator('[class*="provider"], [class*="health"], [class*="grid"]')
    ).toBeVisible();
  }

  /**
   * Click agents tab
   */
  async clickAgentsTab() {
    await this.agentsTab.click();
  }

  /**
   * Verify agent performance metrics
   */
  async verifyAgentMetrics() {
    await expect(
      this.page.locator('[class*="agent"], [class*="metric"], [class*="performance"]')
    ).toBeVisible();
  }

  /**
   * Click alerts tab
   */
  async clickAlertsTab() {
    await this.alertsTab.click();
  }

  /**
   * Verify alert list is displayed
   */
  async verifyAlertList() {
    await expect(
      this.page.locator('[class*="alert"], :text("No alerts"), [class*="warning"], [class*="critical"]')
    ).toBeVisible();
  }

  /**
   * Get alert count from badge
   */
  async getAlertCount(): Promise<number> {
    const badge = this.alertsTab.locator('[class*="badge"], [class*="count"]');
    const text = await badge.textContent();
    return parseInt(text || '0', 10);
  }

  /**
   * Toggle real-time updates
   */
  async toggleRealTime() {
    await this.realTimeToggle.click();
  }

  /**
   * Verify real-time updates are enabled
   */
  async verifyRealTimeEnabled() {
    await expect(
      this.page.locator(':text("Real-time"), :text("Live"), [class*="live"]')
    ).toBeVisible();
  }

  /**
   * Select time range
   */
  async selectTimeRange(range: '1h' | '24h' | '7d' | '30d') {
    const rangeButton = this.page.locator(`button:has-text("${range}")`);
    await rangeButton.click();
  }

  /**
   * Refresh data
   */
  async refresh() {
    await this.refreshButton.click();
  }

  /**
   * Verify connection status
   */
  async verifyConnectionStatus() {
    await expect(
      this.page.locator(':text("Connected"), :text("Online"), [class*="connected"]')
    ).toBeVisible();
  }

  /**
   * Verify last update timestamp
   */
  async verifyLastUpdateTimestamp() {
    await expect(
      this.page.locator(':text("Updated"), :text("ago"), [class*="timestamp"]')
    ).toBeVisible();
  }

  /**
   * Verify system health score
   */
  async verifyHealthScore() {
    await expect(
      this.page.locator('[class*="health"], :text("%"), :text("Score")')
    ).toBeVisible();
  }

  // === Circuit Breaker Monitoring ===

  /**
   * Navigate to circuit breaker section
   */
  async goToCircuitBreakers() {
    const circuitBreakerLink = this.page.locator(':text("Circuit Breaker"), a[href*="circuit"]');
    await circuitBreakerLink.click();
  }

  /**
   * Verify circuit breaker cards are displayed
   */
  async verifyCircuitBreakerCards() {
    await expect(
      this.page.locator('[class*="circuit"], [class*="breaker"]')
    ).toBeVisible();
  }

  /**
   * Verify closed (healthy) state
   */
  async verifyCircuitBreakerClosed() {
    await expect(
      this.page.locator(':text("Healthy"), :text("Closed"), [class*="green"]')
    ).toBeVisible();
  }

  /**
   * Verify open (failed) state
   */
  async verifyCircuitBreakerOpen() {
    await expect(
      this.page.locator(':text("Failed"), :text("Open"), [class*="red"]')
    ).toBeVisible();
  }

  /**
   * Verify half-open (testing) state
   */
  async verifyCircuitBreakerHalfOpen() {
    await expect(
      this.page.locator(':text("Testing"), :text("Half-Open"), [class*="yellow"]')
    ).toBeVisible();
  }

  /**
   * Reset a circuit breaker
   */
  async resetCircuitBreaker(name: string) {
    const breakerCard = this.page.locator(`[class*="circuit"]:has-text("${name}")`);
    const resetButton = breakerCard.getByRole('button', { name: /reset/i });
    await resetButton.click();
  }

  /**
   * Verify success rate is displayed
   */
  async verifySuccessRate() {
    await expect(
      this.page.locator('[class*="success-rate"], :text("Success Rate"), :text("%")')
    ).toBeVisible();
  }

  /**
   * Verify response time is displayed
   */
  async verifyResponseTime() {
    await expect(
      this.page.locator('[class*="response-time"], :text("Response Time"), :text("ms")')
    ).toBeVisible();
  }
}
