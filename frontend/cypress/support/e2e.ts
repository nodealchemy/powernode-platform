// ***********************************************************
// This example support/e2e.ts is processed and
// loaded automatically before your test files.
//
// This is a great place to put global configuration and
// behavior that modifies Cypress.
//
// You can change the location of this file or turn off
// automatically serving support files with the
// 'supportFile' configuration option.
//
// You can read more here:
// https://on.cypress.io/configuration
// ***********************************************************

// Import commands.js using ES2015 syntax:
import './commands';
import './wait-utilities';
import './login-commands';
import './navigation-commands';
import './form-commands';
import './testing-commands';
import './supply-chain-commands';

// Alternatively you can use CommonJS syntax:
// require('./commands')

// Hide fetch/XHR logs in Cypress command log for cleaner output
const app = window.top;
if (app && !app.document.head.querySelector('[data-hide-command-log-request]')) {
  const style = app.document.createElement('style');
  style.innerHTML = '.command-name-request, .command-name-xhr { display: none }';
  style.setAttribute('data-hide-command-log-request', '');
  app.document.head.appendChild(style);
}

// Set up global error handling
Cypress.on('uncaught:exception', (err, _runnable) => {
  // Returning false here prevents Cypress from failing the test
  // for certain expected errors
  if (err.message.includes('ResizeObserver loop limit exceeded')) {
    return false;
  }
  
  if (err.message.includes('Script error')) {
    return false;
  }
  
  return true;
});