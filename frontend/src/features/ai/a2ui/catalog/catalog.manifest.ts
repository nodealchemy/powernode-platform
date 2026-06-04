/**
 * Canonical manifest of the A2UI component catalog this client renders.
 *
 * Single source of truth — intended to be shared by all three consumers so they
 * can never drift (the central design constraint of the hybrid approach):
 *   1. the client catalog (themedCatalog.ts) — what the renderer can render,
 *   2. the server validator + inline-catalog advertisement (Ruby mirror),
 *   3. the agent system-prompt injection (which component types the LLM may emit).
 *
 * `THEMED_COMPONENTS` have platform-themed wrappers; the remaining
 * `SUPPORTED_COMPONENTS` currently render via the SDK's standard catalog until
 * themed wrappers land in the next increment.
 */
export const A2UI_CATALOG_ID = 'powernode/a2ui/v0.9/themed';

export const THEMED_COMPONENTS = ['Text', 'Card', 'Column', 'Button'] as const;

export const SUPPORTED_COMPONENTS = [
  ...THEMED_COMPONENTS,
  'Row',
  'List',
  'Divider',
  'Image',
  'TextField',
  'CheckBox',
  'ChoicePicker',
  'Slider',
  'DateTimeInput',
  'Tabs',
  'Modal',
] as const;

export type SupportedComponent = (typeof SUPPORTED_COMPONENTS)[number];
