import React, { memo } from 'react';
import { useStringBinding } from '../../sdk/a2uiSdk';
import type { DynamicString } from '../../sdk/a2uiSdk';

/**
 * Themed A2UI `Text` component. Mirrors the SDK's standard TextComponent
 * (resolves the dynamic `text` binding, maps `variant` to an element + classes)
 * but renders with platform theme classes only.
 */
const VARIANT_CLASS: Record<string, string> = {
  h1: 'text-2xl font-bold text-theme-primary',
  h2: 'text-xl font-semibold text-theme-primary',
  h3: 'text-lg font-semibold text-theme-primary',
  h4: 'text-base font-semibold text-theme-primary',
  h5: 'text-sm font-semibold text-theme-primary',
  caption: 'text-xs text-theme-secondary',
  body: 'text-sm text-theme-primary',
};

const VARIANT_TAG: Record<string, string> = {
  h1: 'h1',
  h2: 'h2',
  h3: 'h3',
  h4: 'h4',
  h5: 'h5',
  caption: 'span',
  body: 'p',
};

interface A2uiTextProps {
  surfaceId: string;
  text?: DynamicString;
  variant?: string;
  weight?: number;
}

export const A2uiText = memo(function A2uiText({ surfaceId, text, variant = 'body', weight }: A2uiTextProps) {
  const resolved = useStringBinding(surfaceId, text, '');
  const className = VARIANT_CLASS[variant] ?? VARIANT_CLASS.body;
  const Tag = (VARIANT_TAG[variant] ?? 'p') as React.ElementType;
  return (
    <Tag className={className} style={weight ? { flexGrow: weight } : undefined}>
      {resolved}
    </Tag>
  );
});

A2uiText.displayName = 'A2ui.Text';
