

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
