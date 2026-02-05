import { Page, Locator, expect } from '@playwright/test';
import { ROUTES, TEST_AGENT_TEAM } from '../../fixtures/test-data';

/**
 * AI Agent Teams Page Object Model
 *
 * Encapsulates agent team management interactions for Playwright tests.
 * Corresponds to manual testing Phase 5: Agent Teams
 */
export class AgentTeamsPage {
  readonly page: Page;
  readonly pageTitle: Locator;
  readonly teamCards: Locator;
  readonly createTeamButton: Locator;
  readonly statusFilter: Locator;
  readonly typeFilter: Locator;

  // Create Team Modal
  readonly nameInput: Locator;
  readonly descriptionInput: Locator;
  readonly typeSelect: Locator;
  readonly saveButton: Locator;
  readonly cancelButton: Locator;

  // Composition Health Banner
  readonly compositionHealthBanner: Locator;
  readonly compositionStatus: Locator;
  readonly compositionWarnings: Locator;
  readonly compositionRecommendations: Locator;

  // Role Profile Selector
  readonly roleProfileGrid: Locator;
  readonly roleProfileCards: Locator;
  readonly applyProfileButton: Locator;
  readonly customizeProfileButton: Locator;
  readonly profilePreview: Locator;

  // Review Config Section
  readonly reviewConfigSection: Locator;
  readonly reviewEnabledToggle: Locator;
  readonly reviewModeRadio: Locator;
  readonly qualityThresholdSlider: Locator;
  readonly maxRevisionsInput: Locator;

  // Trajectory Viewer
  readonly trajectoryList: Locator;
  readonly trajectoryCards: Locator;
  readonly trajectorySearch: Locator;
  readonly trajectoryTypeFilter: Locator;
  readonly trajectoryTimeline: Locator;
  readonly trajectoryChapters: Locator;

  // Review Panel
  readonly reviewPanel: Locator;
  readonly reviewFindings: Locator;
  readonly reviewQualityScore: Locator;
  readonly reviewCompletenessChecks: Locator;
  readonly approveButton: Locator;
  readonly rejectButton: Locator;
  readonly requestRevisionButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.pageTitle = page.locator('h1, [class*="title"]').first();
    this.teamCards = page.locator('[class*="card"], [class*="Card"], [data-testid*="team"]');
    this.createTeamButton = page.getByRole('button', { name: /create team/i });
    this.statusFilter = page.locator('select[name*="status"], [aria-label*="status"]');
    this.typeFilter = page.locator('select[name*="type"], [aria-label*="type"]');

    // Modal inputs
    this.nameInput = page.locator('input[name="name"], input[placeholder*="name" i]');
    this.descriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.typeSelect = page.locator('select[name="type"], [name="team_type"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
    this.cancelButton = page.getByRole('button', { name: /cancel/i });

    // Composition Health Banner
    this.compositionHealthBanner = page.locator('[data-testid="composition-health"], [class*="composition-health"], [class*="CompositionHealth"]');
    this.compositionStatus = page.locator('[data-testid="composition-status"], [class*="composition-health"] [class*="status"], [class*="CompositionHealth"] [class*="badge"]');
    this.compositionWarnings = page.locator('[data-testid="composition-warnings"], [class*="composition-health"] [class*="warning"]');
    this.compositionRecommendations = page.locator('[data-testid="composition-recommendations"], [class*="composition-health"] [class*="recommendation"]');

    // Role Profile Selector
    this.roleProfileGrid = page.locator('[data-testid="role-profile-grid"], [class*="profile-grid"], [class*="RoleProfileSelector"]');
    this.roleProfileCards = page.locator('[data-testid*="profile-card"], [class*="profile-card"], [class*="ProfileCard"]');
    this.applyProfileButton = page.getByRole('button', { name: /apply profile/i });
    this.customizeProfileButton = page.getByRole('button', { name: /customize/i });
    this.profilePreview = page.locator('[data-testid="profile-preview"], [class*="profile-preview"], [class*="ProfilePreview"]');

    // Review Config Section
    this.reviewConfigSection = page.locator('[data-testid="review-config"], [class*="review-config"], details:has-text("Review Configuration")');
    this.reviewEnabledToggle = page.locator('[data-testid="review-enabled"], input[type="checkbox"]:near(:text("Enable automatic reviews"))');
    this.reviewModeRadio = page.locator('[data-testid="review-mode"], [name="review_mode"]');
    this.qualityThresholdSlider = page.locator('[data-testid="quality-threshold"], input[type="range"]:near(:text("Quality"))');
    this.maxRevisionsInput = page.locator('[data-testid="max-revisions"], input[type="number"]:near(:text("revision"))');

    // Trajectory Viewer
    this.trajectoryList = page.locator('[data-testid="trajectory-list"], [class*="trajectory-list"], [class*="TrajectoryList"]');
    this.trajectoryCards = page.locator('[data-testid*="trajectory-card"], [class*="trajectory-card"], [class*="TrajectoryCard"]');
    this.trajectorySearch = page.locator('[data-testid="trajectory-search"] input, input[placeholder*="search" i]:near(:text("Trajector"))');
    this.trajectoryTypeFilter = page.locator('[data-testid="trajectory-type-filter"], select:near(:text("Type")), button:has-text("All Types")');
    this.trajectoryTimeline = page.locator('[data-testid="trajectory-timeline"], [class*="trajectory-timeline"], [class*="timeline"]');
    this.trajectoryChapters = page.locator('[data-testid*="chapter"], [class*="chapter-card"], [class*="ChapterCard"]');

    // Review Panel
    this.reviewPanel = page.locator('[data-testid="review-panel"], [class*="review-panel"], [class*="ReviewPanel"]');
    this.reviewFindings = page.locator('[data-testid="review-findings"], [class*="review-panel"] [class*="finding"], [class*="ReviewPanel"] [class*="finding"]');
    this.reviewQualityScore = page.locator('[data-testid="review-quality-score"], [class*="review-panel"] [class*="score"], [class*="quality-score"]');
    this.reviewCompletenessChecks = page.locator('[data-testid="completeness-checks"], [class*="completeness"], [class*="review-panel"] [class*="check"]');
    this.approveButton = page.getByRole('button', { name: /approve/i });
    this.rejectButton = page.getByRole('button', { name: /reject/i });
    this.requestRevisionButton = page.getByRole('button', { name: /request revision|revision/i });
  }

  /**
   * Navigate to agent teams page
   */
  async goto() {
    await this.page.goto(ROUTES.agentTeams);
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
    await expect(this.page.locator('body')).toContainText(/team/i);
  }

  /**
   * Click create team button
   */
  async clickCreateTeam() {
    await this.createTeamButton.click();
  }

  /**
   * Verify create modal is open
   */
  async verifyCreateModalOpen() {
    await expect(
      this.page.locator('[role="dialog"], [class*="modal"]')
    ).toBeVisible();
  }

  /**
   * Fill create team form
   */
  async fillTeamForm(data: Partial<typeof TEST_AGENT_TEAM> = TEST_AGENT_TEAM) {
    if (data.name) {
      await this.nameInput.fill(data.name);
    }
    if (data.description) {
      await this.descriptionInput.fill(data.description);
    }
    // Type select may need special handling
  }

  /**
   * Save team form
   */
  async saveTeam() {
    await this.saveButton.click();
  }

  /**
   * Create a new agent team
   */
  async createTeam(data: Partial<typeof TEST_AGENT_TEAM> = TEST_AGENT_TEAM) {
    await this.clickCreateTeam();
    await this.verifyCreateModalOpen();
    await this.fillTeamForm(data);
    await this.saveTeam();
  }

  /**
   * Get team card by name
   */
  getTeamCard(name: string): Locator {
    return this.page.locator(`[class*="card"]:has-text("${name}"), [class*="Card"]:has-text("${name}")`);
  }

  /**
   * Verify team card exists
   */
  async verifyTeamExists(name: string) {
    const card = this.getTeamCard(name);
    await expect(card).toBeVisible();
  }

  /**
   * Click execute on a team
   */
  async clickExecute(teamName: string) {
    const card = this.getTeamCard(teamName);
    const executeButton = card.getByRole('button', { name: /execute|run/i });
    await executeButton.click();
  }

  /**
   * Enter team execution task
   */
  async enterExecutionTask(task: string) {
    const taskInput = this.page.locator('textarea[placeholder*="task" i], input[placeholder*="task" i], textarea').first();
    await taskInput.fill(task);
  }

  /**
   * Submit team execution
   */
  async submitExecution() {
    const submitButton = this.page.getByRole('button', { name: /execute|run|start/i });
    await submitButton.click();
  }

  /**
   * Wait for team execution to start
   */
  async waitForExecutionStart() {
    await this.page.waitForSelector('[class*="execution"], [class*="running"], :text("Running")', {
      timeout: 30000,
    });
  }

  /**
   * Verify execution monitor is visible
   */
  async verifyExecutionMonitor() {
    await expect(
      this.page.locator('[class*="monitor"], [class*="execution-status"]')
    ).toBeVisible();
  }

  /**
   * Verify agent-by-agent progress
   */
  async verifyAgentProgress() {
    // Look for individual agent status indicators
    await expect(
      this.page.locator('[class*="agent-status"], [class*="step"]')
    ).toBeVisible();
  }

  /**
   * Wait for team execution to complete
   */
  async waitForExecutionComplete() {
    await this.page.waitForSelector(':text("Completed"), :text("Success"), [class*="complete"]', {
      timeout: 180000, // 3 minutes for multi-agent execution
    });
  }

  /**
   * Click edit on a team
   */
  async clickEdit(teamName: string) {
    const card = this.getTeamCard(teamName);
    const editButton = card.getByRole('button', { name: /edit/i });
    await editButton.click();
  }

  /**
   * Click delete on a team
   */
  async clickDelete(teamName: string) {
    const card = this.getTeamCard(teamName);
    const deleteButton = card.getByRole('button', { name: /delete/i });
    await deleteButton.click();
  }

  /**
   * Confirm deletion
   */
  async confirmDelete() {
    const confirmButton = this.page.getByRole('button', { name: /confirm|yes|delete/i });
    await confirmButton.click();
  }

  /**
   * Filter by status
   */
  async filterByStatus(status: string) {
    await this.statusFilter.click();
    await this.page.locator(`:text("${status}")`).click();
  }

  /**
   * Filter by type
   */
  async filterByType(type: 'Hierarchical' | 'Mesh' | 'Sequential' | 'Parallel') {
    await this.typeFilter.click();
    await this.page.locator(`:text("${type}")`).click();
  }

  /**
   * Verify empty state is shown
   */
  async verifyEmptyState() {
    await expect(
      this.page.locator(':text("No teams"), :text("Create Team"), :text("Get started")')
    ).toBeVisible();
  }

  /**
   * Get count of team cards
   */
  async getTeamCount(): Promise<number> {
    return await this.teamCards.count();
  }

  /**
   * Verify team type options exist
   */
  async verifyTypeOptions() {
    await expect(
      this.page.locator(':text("Hierarchical"), :text("Sequential"), :text("Parallel")')
    ).toBeVisible();
  }

  // --- Composition Health Methods ---

  async verifyCompositionHealthVisible() {
    await expect(this.compositionHealthBanner).toBeVisible();
  }

  async getCompositionStatus(): Promise<string> {
    return await this.compositionStatus.textContent() || '';
  }

  async verifyCompositionWarnings(expectedCount?: number) {
    if (expectedCount !== undefined) {
      const warnings = await this.compositionWarnings.locator('li, [class*="warning"]').count();
      expect(warnings).toBeGreaterThanOrEqual(expectedCount);
    }
    await expect(this.compositionWarnings).toBeVisible();
  }

  async verifyCompositionRecommendations() {
    await expect(this.compositionRecommendations).toBeVisible();
  }

  // --- Role Profile Methods ---

  async selectRoleProfile(profileName: string) {
    const profileCard = this.roleProfileCards.filter({ hasText: profileName });
    await profileCard.click();
  }

  async verifyProfilePreview(profileName: string) {
    await expect(this.profilePreview).toContainText(profileName);
  }

  async applySelectedProfile() {
    await this.applyProfileButton.click();
  }

  async getRoleProfileCount(): Promise<number> {
    return await this.roleProfileCards.count();
  }

  // --- Review Config Methods ---

  async openReviewConfigSection() {
    const section = this.page.locator('details:has-text("Review Configuration"), summary:has-text("Review Configuration")');
    if (await section.count() > 0) {
      await section.first().click();
    }
  }

  async toggleAutoReview(enable: boolean) {
    const checkbox = this.reviewEnabledToggle;
    const isChecked = await checkbox.isChecked();
    if (isChecked !== enable) {
      await checkbox.click();
    }
  }

  async selectReviewMode(mode: 'blocking' | 'shadow') {
    const radio = this.page.locator(`input[value="${mode}"], label:has-text("${mode}") input`);
    await radio.first().click();
  }

  async setQualityThreshold(value: number) {
    await this.qualityThresholdSlider.fill(String(value));
  }

  async setMaxRevisions(value: number) {
    await this.maxRevisionsInput.fill(String(value));
  }

  // --- Trajectory Methods ---

  async navigateToTrajectories() {
    const trajLink = this.page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")');
    await trajLink.first().click();
    await this.page.waitForLoadState('networkidle');
  }

  async searchTrajectories(query: string) {
    await this.trajectorySearch.fill(query);
    await this.page.waitForTimeout(500);
  }

  async filterTrajectoryType(type: string) {
    await this.trajectoryTypeFilter.click();
    await this.page.locator(`:text("${type}")`).first().click();
  }

  async openTrajectory(title: string) {
    const card = this.trajectoryCards.filter({ hasText: title });
    await card.click();
    await this.page.waitForLoadState('networkidle');
  }

  async verifyTrajectoryTimeline() {
    await expect(this.trajectoryTimeline).toBeVisible();
  }

  async verifyChapterCount(expected: number) {
    const chapters = await this.trajectoryChapters.count();
    expect(chapters).toBe(expected);
  }

  async expandChapter(chapterTitle: string) {
    const chapter = this.trajectoryChapters.filter({ hasText: chapterTitle });
    await chapter.click();
  }

  async verifyChapterContent(chapterTitle: string) {
    const chapter = this.trajectoryChapters.filter({ hasText: chapterTitle });
    await expect(chapter.locator('[class*="content"], p')).toBeVisible();
  }

  async getTrajectoryCount(): Promise<number> {
    return await this.trajectoryCards.count();
  }

  // --- Review Panel Methods ---

  async verifyReviewPanelVisible() {
    await expect(this.reviewPanel).toBeVisible();
  }

  async getReviewQualityScore(): Promise<string> {
    return await this.reviewQualityScore.textContent() || '';
  }

  async verifyFindingsCount(expected: number) {
    const findings = await this.reviewFindings.count();
    expect(findings).toBe(expected);
  }

  async verifyCompletenessChecks() {
    await expect(this.reviewCompletenessChecks).toBeVisible();
  }

  async approveReview(notes?: string) {
    if (notes) {
      await this.page.locator('textarea[name*="notes"], textarea[placeholder*="notes" i]').fill(notes);
    }
    await this.approveButton.click();
  }

  async rejectReview(reason: string) {
    await this.page.locator('textarea[name*="reason"], textarea[placeholder*="reason" i]').fill(reason);
    await this.rejectButton.click();
  }

  async requestRevision(notes?: string) {
    if (notes) {
      await this.page.locator('textarea[name*="notes"], textarea[placeholder*="notes" i]').fill(notes);
    }
    await this.requestRevisionButton.click();
  }
}
