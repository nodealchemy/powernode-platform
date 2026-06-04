/**
 * Single isolation point for the @a2ui-sdk/react community SDK (A2UI v0.9).
 *
 * ALL A2UI feature code imports SDK bindings from HERE — never from
 * '@a2ui-sdk/react/0.9' directly — so the underlying renderer can be swapped
 * (e.g. for Google's official React A2UI renderer when it ships) by editing
 * this one file. The package is pinned exact at @a2ui-sdk/react@0.4.0; v0.9 is
 * a draft spec, so keeping the dependency surface tiny is deliberate.
 */
export {
  A2UIProvider,
  A2UIRenderer,
  ComponentRenderer,
  standardCatalog,
  useStringBinding,
  useDataBinding,
  useFormBinding,
  useDataModel,
  useValidation,
  useDispatchAction,
} from '@a2ui-sdk/react/0.9';

export type {
  A2UIMessage,
  A2UIAction,
  ActionHandler,
  Action,
  Catalog,
  CatalogComponent,
  CatalogComponents,
  ComponentDefinition,
  CreateSurfacePayload,
  UpdateComponentsPayload,
  UpdateDataModelPayload,
  DynamicString,
  DynamicValue,
} from '@a2ui-sdk/react/0.9';
