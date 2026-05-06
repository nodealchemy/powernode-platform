// Extension-side Jest config. Extends the parent platform's config with
// extension-specific paths so the marketing extension's frontend tests
// can run with the same jsdom + babel + jest-dom setup the parent uses.
//
// Usage: from extensions/marketing/frontend/, run
//   npx --prefix ../../../frontend jest --config=jest.config.js
//
// Mirrors extensions/system/frontend/jest.config.js (Phase 10.7 frontend
// test infra pattern). Without this file, parent jest's roots only cover
// frontend/src — extension test files at extensions/marketing/.../*.test.tsx
// would never run.

const path = require('path');
const parent = require('../../../frontend/jest.config.js');

const PARENT_ROOT = path.resolve(__dirname, '../../../frontend');

module.exports = {
  ...parent,
  rootDir: __dirname,
  roots: ['<rootDir>/src'],
  // Reuse parent's setup file (jest-dom matchers + TextEncoder/TextDecoder polyfill)
  setupFilesAfterEnv: [path.join(PARENT_ROOT, 'src/setupTests.ts')],
  moduleNameMapper: {
    ...parent.moduleNameMapper,
    // Parent platform aliases need to resolve via parent root
    '^@/test-utils$': path.join(PARENT_ROOT, 'src/test-utils.tsx'),
    '^@/test-utils/(.*)$': path.join(PARENT_ROOT, 'src/test-utils/$1'),
    '^@/shared/(.*)$': path.join(PARENT_ROOT, 'src/shared/$1'),
    '^@/features/(.*)$': path.join(PARENT_ROOT, 'src/features/$1'),
    '^@/pages/(.*)$': path.join(PARENT_ROOT, 'src/pages/$1'),
    '^@/assets/(.*)$': path.join(PARENT_ROOT, 'src/assets/$1'),
    // Extension's own src
    '^@marketing/(.*)$': '<rootDir>/src/$1',
    // Asset / module mocks live in parent
    '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    '\\.(svg|png|jpg|jpeg|gif|webp)$': path.join(PARENT_ROOT, 'src/__mocks__/fileMock.js'),
    '@uiw/react-md-editor': path.join(PARENT_ROOT, 'src/__mocks__/@uiw/react-md-editor.js'),
    'react-markdown': path.join(PARENT_ROOT, 'src/__mocks__/react-markdown.js'),
  },
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
  ],
  testPathIgnorePatterns: ['/node_modules/'],
};
