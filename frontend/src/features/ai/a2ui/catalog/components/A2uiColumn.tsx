import { memo } from 'react';
import { ComponentRenderer } from '../../sdk/a2uiSdk';

/**
 * Themed A2UI `Column` layout — renders an array of child component ids in a
 * vertical flex stack. (The template-iteration child form is handled by the
 * SDK standard catalog until the themed wrapper supports it.)
 */
interface A2uiColumnProps {
  surfaceId: string;
  children?: unknown;
  weight?: number;
}

export const A2uiColumn = memo(function A2uiColumn({ surfaceId, children, weight }: A2uiColumnProps) {
  const style = weight ? { flexGrow: weight } : undefined;
  if (Array.isArray(children)) {
    return (
      <div className="flex flex-col gap-3" style={style}>
        {children.map((id) => (
          <ComponentRenderer key={String(id)} surfaceId={surfaceId} componentId={String(id)} />
        ))}
      </div>
    );
  }
  return <div className="flex flex-col gap-3" style={style} />;
});

A2uiColumn.displayName = 'A2ui.Column';
