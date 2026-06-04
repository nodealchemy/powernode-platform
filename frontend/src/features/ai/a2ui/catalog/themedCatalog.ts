import { standardCatalog } from '../sdk/a2uiSdk';
import type { Catalog } from '../sdk/a2uiSdk';
import { A2uiText } from './components/A2uiText';
import { A2uiCard } from './components/A2uiCard';
import { A2uiColumn } from './components/A2uiColumn';
import { A2uiButton } from './components/A2uiButton';

/**
 * Hybrid catalog: reuse the SDK runtime + its standard catalog, but override the
 * listed component types with platform-themed wrappers (theme classes only).
 * Component types NOT overridden here fall through to the SDK's standard
 * implementations until their themed wrappers land — see catalog.manifest.ts.
 */
export const themedCatalog: Catalog = {
  ...standardCatalog,
  components: {
    ...standardCatalog.components,
    Text: A2uiText,
    Card: A2uiCard,
    Column: A2uiColumn,
    Button: A2uiButton,
  },
};
