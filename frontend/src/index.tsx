import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';
import reportWebVitals from './reportWebVitals';
import { initializeDOMErrorHandling } from '@/shared/utils/domErrorHandler';
import { loadRuntimeExtensions } from '@/shared/services/extensionLoader';
import { logger } from '@/shared/utils/logger';

// Initialize DOM error handling as early as possible
initializeDOMErrorHandling();

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

// Load runtime (dedicated-module) extension frontends BEFORE the first render,
// so any public routes an extension registers exist before App resolves the
// catch-all `*` route — the same invariant the eager glob path already
// guarantees for baked-in extensions (which register synchronously when App is
// imported above, hence before this runs).
//
// Bounded by a timeout so a slow or broken extension endpoint can never block
// boot: on timeout we render anyway. loadRuntimeExtensions() isolates and
// swallows per-extension failures internally, so this only guards a hung fetch.
const RUNTIME_EXT_TIMEOUT_MS = 5000;

async function bootstrap(): Promise<void> {
  try {
    await Promise.race([
      loadRuntimeExtensions(),
      new Promise<void>((resolve) => setTimeout(resolve, RUNTIME_EXT_TIMEOUT_MS)),
    ]);
  } catch (err) {
    logger.error('Runtime extension loading failed; rendering without them', err);
  }
  root.render(<App />);
}

void bootstrap();

// If you want to start measuring performance in your app, pass a function
// to log results or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals();
