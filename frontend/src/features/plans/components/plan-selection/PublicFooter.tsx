import React from 'react';
import { Link } from 'react-router-dom';
import { ShieldCheckIcon } from '@heroicons/react/24/outline';

export const PublicFooter: React.FC = () => {
  return (
    <footer className="bg-gradient-to-r from-slate-900 via-slate-800 to-slate-900 text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Main Footer Content */}
        <div className="py-16 border-b border-slate-700/50">
          <div className="grid lg:grid-cols-4 md:grid-cols-2 gap-8">
            {/* Company Info */}
            <div className="lg:col-span-1">
              <div className="flex items-center space-x-3 mb-6">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: 'linear-gradient(135deg, #3b82f6, #8b5cf6)' }}>
                  <span className="text-white font-bold text-lg">P</span>
                </div>
                <div>
                  <h3 className="text-xl font-bold bg-gradient-to-r from-white to-slate-200 bg-clip-text text-transparent">
                    Powernode
                  </h3>
                  <p className="text-xs text-slate-400 font-medium">Subscription Platform</p>
                </div>
              </div>
              <p className="text-slate-300 text-sm leading-relaxed mb-6">
                Powerful subscription management platform designed to help businesses grow.
                Trusted by thousands of companies worldwide.
              </p>
              <div className="flex space-x-4">
                <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="Social Media" disabled>
                  <span className="text-lg">X</span>
                </button>
                <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="LinkedIn" disabled>
                  <span className="text-lg">in</span>
                </button>
                <button className="w-10 h-10 bg-slate-800 hover:bg-slate-700 rounded-xl flex items-center justify-center transition-colors duration-200" title="Contact" disabled>
                  <span className="text-lg">@</span>
                </button>
              </div>
            </div>

            {/* Product Links */}
            <div>
              <h4 className="text-white font-semibold mb-6">Product</h4>
              <ul className="space-y-4">
                <li>
                  <Link to="/plans" className="text-slate-300 hover:text-white transition-colors duration-200 text-sm">
                    Features
                  </Link>
                </li>
                <li>
                  <Link to="/plans" className="text-slate-300 hover:text-white transition-colors duration-200 text-sm">
                    Pricing
                  </Link>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Integrations
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    API Documentation
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Security
                  </button>
                </li>
              </ul>
            </div>

            {/* Support Links */}
            <div>
              <h4 className="text-white font-semibold mb-6">Support</h4>
              <ul className="space-y-4">
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Help Center
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Contact Us
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    System Status
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Community
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Changelog
                  </button>
                </li>
              </ul>
            </div>

            {/* Company Links */}
            <div>
              <h4 className="text-white font-semibold mb-6">Company</h4>
              <ul className="space-y-4">
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    About Us
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Careers
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Press
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Partners
                  </button>
                </li>
                <li>
                  <button className="text-slate-300 hover:text-white transition-colors duration-200 text-sm" disabled>
                    Blog
                  </button>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Footer Bottom */}
        <div className="py-8">
          <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
            <div className="flex flex-wrap items-center gap-6 text-sm text-slate-400">
              <span>© 2024 Powernode. All rights reserved.</span>
              <div className="flex items-center space-x-6">
                <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                  Privacy Policy
                </button>
                <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                  Terms of Service
                </button>
                <button className="hover:text-slate-300 transition-colors duration-200" disabled>
                  Cookie Policy
                </button>
              </div>
            </div>

            <div className="flex items-center space-x-6">
              <div className="flex items-center space-x-2 bg-slate-800/50 px-3 py-2 rounded-full">
                <div className="w-2 h-2 bg-theme-success rounded-full animate-pulse"></div>
                <span className="text-xs text-slate-300 font-medium">All systems operational</span>
              </div>
              <div className="flex items-center space-x-2 text-xs text-slate-400">
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
