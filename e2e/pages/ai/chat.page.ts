import { Page, Locator, expect } from '@playwright/test';

/**
 * AI Chat Page Object Model — Unified Popup Chat System
 *
 * The chat is now accessible via:
 * - Floating widget (bottom-right button)
 * - Navigation item (dispatches CustomEvent to open maximized)
 * - Agent detail "Chat" button (opens maximized with agent)
 *
 * Modes: floating (compact), maximized (full + sidebar + split-view), detached (popup)
 */
export class ChatPagePOM {
  readonly page: Page;

  // Floating widget
  readonly floatingWidget: Locator;

  // Chat window (any mode)
  readonly chatWindow: Locator;
  readonly chatMaximized: Locator;

  // Header controls
  readonly headerTitle: Locator;
  readonly sidebarToggle: Locator;
  readonly actionsMenu: Locator;
  readonly maximizeButton: Locator;
  readonly minimizeButton: Locator;
  readonly detachButton: Locator;
  readonly closeButton: Locator;

  // Sidebar (maximized/detached only)
  readonly sidebar: Locator;
  readonly sidebarSearch: Locator;
  readonly sidebarConversations: Locator;
  readonly sidebarNewChat: Locator;

  // Tabs
  readonly tabBar: Locator;
  readonly tabs: Locator;
  readonly newTabButton: Locator;

  // Split panels (maximized/detached only)
  readonly splitPanelContainer: Locator;
  readonly panels: Locator;
  readonly panelDividers: Locator;

  // Tab context menu
  readonly tabContextMenu: Locator;

  constructor(page: Page) {
    this.page = page;

    // Floating widget trigger
    this.floatingWidget = page.locator('[data-testid="floating-chat-widget"], button[title="Open AI Chat"]');

    // Chat window containers
    this.chatWindow = page.locator('[class*="bg-theme-background"][class*="rounded-xl"]').first();
    this.chatMaximized = page.locator('[data-testid="chat-maximized"]');

    // Header
    this.headerTitle = page.locator('.text-sm.font-semibold.text-theme-primary').first();
    this.sidebarToggle = page.locator('button[title="Hide sidebar"], button[title="Show sidebar"]');
    this.actionsMenu = page.locator('button[title="Conversation actions"]');
    this.maximizeButton = page.locator('button[title="Maximize"]');
    this.minimizeButton = page.locator('button[title="Restore"]');
    this.detachButton = page.locator('button[title="Pop out"]');
    this.closeButton = page.locator('button[title="Close"]');

    // Sidebar
    this.sidebar = page.locator('[data-testid="chat-sidebar"], [class*="ChatWindowSidebar"]').first();
    this.sidebarSearch = page.locator('input[placeholder*="Search" i]');
    this.sidebarConversations = page.locator('[class*="cursor-pointer"][class*="transition-colors"]');
    this.sidebarNewChat = page.locator('button:has-text("New Chat")');

    // Tabs
    this.tabBar = page.locator('[class*="border-b"][class*="bg-theme-surface"]');
    this.tabs = page.locator('button[data-tab-id]');
    this.newTabButton = page.locator('button[title="New conversation"]');

    // Split panels
    this.splitPanelContainer = page.locator('[data-testid="split-panel-container"]');
    this.panels = page.locator('[data-testid^="split-panel-"]');
    this.panelDividers = page.locator('[class*="col-resize"], [style*="col-resize"]');

    // Tab context menu
    this.tabContextMenu = page.locator('[data-testid="tab-context-menu"]');
  }

  /** Open chat via floating widget click */
  async openFloating() {
    await this.floatingWidget.click();
    await this.page.waitForTimeout(300);
  }

  /** Open chat maximized via nav dispatch */
  async openMaximized() {
    await this.page.evaluate(() => {
      window.dispatchEvent(new CustomEvent('powernode:open-chat-maximized'));
    });
    await this.page.waitForTimeout(500);
  }

  /** Maximize from floating mode */
  async maximize() {
    await this.maximizeButton.click();
    await this.page.waitForTimeout(300);
  }

  /** Close the chat window */
  async close() {
    await this.closeButton.click();
    await this.page.waitForTimeout(200);
  }

  /** Toggle sidebar visibility */
  async toggleSidebar() {
    await this.sidebarToggle.click();
    await this.page.waitForTimeout(200);
  }

  /** Check if maximized overlay is visible */
  async isMaximized(): Promise<boolean> {
    return (await this.chatMaximized.count()) > 0;
  }

  /** Check if sidebar is visible */
  async isSidebarVisible(): Promise<boolean> {
    return (await this.sidebar.count()) > 0;
  }

  /** Get tab count */
  async getTabCount(): Promise<number> {
    return await this.tabs.count();
  }

  /** Get panel count */
  async getPanelCount(): Promise<number> {
    return await this.panels.count();
  }

  /** Right-click a tab to open context menu */
  async rightClickTab(index: number) {
    const tab = this.tabs.nth(index);
    await tab.click({ button: 'right' });
    await this.page.waitForTimeout(200);
  }

  /** Click "Split Right" in tab context menu */
  async splitRight() {
    await this.page.locator('button:has-text("Split Right")').click();
    await this.page.waitForTimeout(300);
  }

  /** Open actions menu and click an action */
  async clickAction(actionName: string) {
    await this.actionsMenu.click();
    await this.page.waitForTimeout(200);
    await this.page.locator(`button:has-text("${actionName}")`).click();
    await this.page.waitForTimeout(200);
  }
}
