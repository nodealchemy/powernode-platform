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
  },
};