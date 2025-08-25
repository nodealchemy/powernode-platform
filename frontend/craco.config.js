const path = require('path');

module.exports = {
  webpack: {
    alias: {
      '@/shared': path.resolve(__dirname, 'src/shared'),
      '@/features': path.resolve(__dirname, 'src/features'),
      '@/pages': path.resolve(__dirname, 'src/pages'),
      '@/assets': path.resolve(__dirname, 'src/assets'),
      '@': path.resolve(__dirname, 'src'),
    },
    configure: (webpackConfig) => {
      // Suppress -ms-high-contrast deprecation warnings
      webpackConfig.ignoreWarnings = [
        /.*-ms-high-contrast.*deprecated.*/i,
        function(warning) {
          return warning.message && warning.message.includes('-ms-high-contrast');
        }
      ];
      return webpackConfig;
    },
  },
};