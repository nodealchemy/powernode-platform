/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'jsdom',
  roots: ['<rootDir>/src'],
  testMatch: [
    '**/__tests__/**/*.{js,jsx,ts,tsx}',
    '**/*.{spec,test}.{js,jsx,ts,tsx}'
  ],
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.ts'],
  transform: {
    // Static assets -> stub module. Must be a transform (not just
    // moduleNameMapper) so it applies under --experimental-vm-modules.
    '\\.(png|jpg|jpeg|gif|webp|svg|ico)$': '<rootDir>/src/__mocks__/fileTransform.js',
    '^.+\\.(js|jsx|ts|tsx)$': ['babel-jest', {
      presets: [
        ['@babel/preset-env', { targets: { node: 'current' } }],
        ['@babel/preset-react', { runtime: 'automatic' }],
        '@babel/preset-typescript'
      ]
    }]
  },
  transformIgnorePatterns: [
    'node_modules/(?!(axios|react-router|react-router-dom|@remix-run)/)'
  ],
  moduleNameMapper: {
    '^@/test-utils$': '<rootDir>/src/test-utils.tsx',
    '^@/test-utils/(.*)$': '<rootDir>/src/test-utils/$1',
    '^@/shared/(.*)$': '<rootDir>/src/shared/$1',
    '^@/features/(.*)$': '<rootDir>/src/features/$1',
    '^@/pages/(.*)$': '<rootDir>/src/pages/$1',
    '^@/assets/(.*)$': '<rootDir>/src/assets/$1',
    // Catch-all fallback, mirroring tsconfig.json's own `"@/*": ["./src/*"]`:
    // the specific entries above exist for extension jest configs to
    // re-anchor individually (see business/marketing/etc. jest.config.js
    // comments), but core itself has top-level src dirs (e.g. src/services)
    // that only this catch-all resolves. Must come after the specific
    // entries have no effect on precedence (Jest tries patterns in order and
    // both forms resolve identically for shared/features/pages/assets), but
    // keeps the fallback from masking a future extension-specific override.
    '^@/(.*)$': '<rootDir>/src/$1',
    '^axios$': 'axios/dist/node/axios.cjs',
    '\\.(css|less|scss|sass)$': 'identity-obj-proxy',
    '@uiw/react-md-editor': '<rootDir>/src/__mocks__/@uiw/react-md-editor.js',
    'react-markdown': '<rootDir>/src/__mocks__/react-markdown.js'
  },
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/index.tsx',
    '!src/reportWebVitals.ts'
  ],
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/__mocks__/',
    '/src/setupTests.ts'
  ],
  testPathIgnorePatterns: [
    '/node_modules/',
    '/cypress/'
  ],
  watchPlugins: [
    'jest-watch-typeahead/filename',
    'jest-watch-typeahead/testname'
  ],
  resetMocks: true
};
