// Jest transformer for static asset imports (png/jpg/svg/...).
//
// Under NODE_OPTIONS=--experimental-vm-modules, Jest's moduleNameMapper is not
// reliably applied to non-JS asset imports, so `import logo from './logo.png'`
// would otherwise try to parse the raw asset as a source module
// ("SyntaxError: Invalid or unexpected token"). A transform runs in both the
// CJS and ESM loaders, so converting the asset to a stub module here fixes
// asset-importing suites (e.g. LoginPage, Sidebar) regardless of loader.
module.exports = {
  process() {
    return { code: 'module.exports = "test-file-stub";' };
  },
  getCacheKey() {
    return 'a2ui-fileTransform-v1';
  },
};
