import React from 'react';
import { Link } from 'react-router-dom';
import { ShieldCheckIcon } from '@heroicons/react/24/outline';

export const PublicFooter: React.FC = () => {
  return (
    <footer className="bg-theme-background-secondary text-theme-primary">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Main Footer Content */}
        <div className="py-16 border-b border-theme">
          <div className="grid lg:grid-cols-4 md:grid-cols-2 gap-8">
            {/* Company Info */}
            <div className="lg:col-span-1">
              <div className="flex items-center space-x-3 mb-6">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center bg-theme-interactive-primary">
                  <span className="text-white font-bold text-lg">P</span>
                </div>
                <div>
                  <h3 className="text-xl font-bold text-theme-primary">
                    Powernode
                  </h3>
                  <p className="text-xs text-theme-tertiary font-medium">Subscription Platform</p>
                </div>
              </div>
              <p className="text-theme-secondary text-sm leading-relaxed mb-6">
                Powerful subscription management platform designed to help businesses grow.
                Trusted by thousands of companies worldwide.
              </p>
              <div className="flex space-x-4">
                <button className="w-10 h-10 bg-theme-surface hover:bg-theme-surface-hover rounded-xl flex items-center justify-center transition-colors duration-200" title="Social Media" disabled>
                  <span className="text-lg">X</span>
                </button>
                <button className="w-10 h-10 bg-theme-surface hover:bg-theme-surface-hover rounded-xl flex items-center justify-center transition-colors duration-200" title="LinkedIn" disabled>
                  <span className="text-lg">in</span>
                </button>
                <button className="w-10 h-10 bg-theme-surface hover:bg-theme-surface-hover rounded-xl flex items-center justify-center transition-colors duration-200" title="Contact" disabled>
                  <span className="text-lg">@</span>
                </button>
              </div>
            </div>

            {/* Product Links */}
            <div>
              <h4 className="text-theme-primary font-semibold mb-6">Product</h4>
              <ul className="space-y-4">
                <li>
                  <Link to="/pages/features" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    Features
                  </Link>
                </li>
                <li>
                  <Link to="/plans" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    Pricing
                  </Link>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Integrations
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    API Documentation
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Security
                  </span>
                </li>
              </ul>
            </div>

            {/* Support Links */}
            <div>
              <h4 className="text-theme-primary font-semibold mb-6">Support</h4>
              <ul className="space-y-4">
                <li>
                  <Link to="/pages/help" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    Help Center
                  </Link>
                </li>
                <li>
                  <Link to="/pages/contact" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    Contact Us
                  </Link>
                </li>
                <li>
                  <Link to="/status" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    System Status
                  </Link>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Community
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Changelog
                  </span>
                </li>
              </ul>
            </div>

            {/* Company Links */}
            <div>
              <h4 className="text-theme-primary font-semibold mb-6">Company</h4>
              <ul className="space-y-4">
                <li>
                  <Link to="/pages/about" className="text-theme-secondary hover:text-theme-primary transition-colors duration-200 text-sm">
                    About Us
                  </Link>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Careers
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Press
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Partners
                  </span>
                </li>
                <li>
                  <span className="text-theme-quaternary text-sm cursor-not-allowed" title="Coming Soon">
                    Blog
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Footer Bottom */}
        <div className="py-8">
          <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
            <div className="flex flex-wrap items-center gap-6 text-sm text-theme-tertiary">
              <span>© 2024 Powernode. All rights reserved.</span>
              <div className="flex items-center space-x-6">
                <Link to="/pages/privacy" className="hover:text-theme-secondary transition-colors duration-200">
                  Privacy Policy
                </Link>
                <Link to="/pages/terms" className="hover:text-theme-secondary transition-colors duration-200">
                  Terms of Service
                </Link>
                <span className="text-theme-quaternary cursor-not-allowed" title="Coming Soon">
                  Cookie Policy
                </span>
              </div>
            </div>

            <div className="flex items-center space-x-6">
              <Link to="/status" className="flex items-center space-x-2 bg-theme-surface px-3 py-2 rounded-full hover:bg-theme-surface-hover transition-colors duration-200">
                <div className="w-2 h-2 bg-theme-success-solid rounded-full animate-pulse"></div>
                <span className="text-xs text-theme-secondary font-medium">All systems operational</span>
              </Link>
              <div className="flex items-center space-x-2 text-xs text-theme-tertiary">
                <ShieldCheckIcon className="h-4 w-4" />
                <span>SOC 2 Compliant</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
};
