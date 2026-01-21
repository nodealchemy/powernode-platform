# frozen_string_literal: true

# Seed common SPDX licenses for the Supply Chain License Management module

puts "Seeding SPDX licenses..."

licenses = [
  # Permissive Licenses
  {
    spdx_id: "MIT",
    name: "MIT License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/MIT",
    description: "A short and simple permissive license",
    license_text: <<~LICENSE
      MIT License

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    LICENSE
  },
  {
    spdx_id: "Apache-2.0",
    name: "Apache License 2.0",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/Apache-2.0",
    description: "A permissive license with patent grant"
  },
  {
    spdx_id: "BSD-2-Clause",
    name: "BSD 2-Clause \"Simplified\" License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/BSD-2-Clause",
    description: "A permissive license with minimal restrictions"
  },
  {
    spdx_id: "BSD-3-Clause",
    name: "BSD 3-Clause \"New\" or \"Revised\" License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/BSD-3-Clause",
    description: "A permissive license with non-endorsement clause"
  },
  {
    spdx_id: "ISC",
    name: "ISC License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/ISC",
    description: "A permissive license similar to MIT"
  },
  {
    spdx_id: "Unlicense",
    name: "The Unlicense",
    category: "public_domain",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://unlicense.org/",
    description: "A public domain dedication"
  },
  {
    spdx_id: "CC0-1.0",
    name: "Creative Commons Zero v1.0 Universal",
    category: "public_domain",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://creativecommons.org/publicdomain/zero/1.0/",
    description: "A public domain dedication for works"
  },
  {
    spdx_id: "0BSD",
    name: "BSD Zero Clause License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/0BSD",
    description: "A public domain equivalent license"
  },
  {
    spdx_id: "Zlib",
    name: "zlib License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/Zlib",
    description: "A permissive license with minimal requirements"
  },
  {
    spdx_id: "WTFPL",
    name: "Do What The F*ck You Want To Public License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "http://www.wtfpl.net/",
    description: "An extremely permissive license"
  },

  # Weak Copyleft Licenses
  {
    spdx_id: "LGPL-2.1-only",
    name: "GNU Lesser General Public License v2.1 only",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/lgpl-2.1.html",
    description: "Weak copyleft for library linking"
  },
  {
    spdx_id: "LGPL-3.0-only",
    name: "GNU Lesser General Public License v3.0 only",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/lgpl-3.0.html",
    description: "Weak copyleft for library linking"
  },
  {
    spdx_id: "MPL-2.0",
    name: "Mozilla Public License 2.0",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/MPL-2.0",
    description: "File-level copyleft license"
  },
  {
    spdx_id: "EPL-2.0",
    name: "Eclipse Public License 2.0",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.eclipse.org/legal/epl-2.0/",
    description: "Weak copyleft from Eclipse Foundation"
  },
  {
    spdx_id: "CDDL-1.0",
    name: "Common Development and Distribution License 1.0",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/CDDL-1.0",
    description: "Weak copyleft from Sun Microsystems"
  },

  # Strong Copyleft Licenses
  {
    spdx_id: "GPL-2.0-only",
    name: "GNU General Public License v2.0 only",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/gpl-2.0.html",
    description: "Strong copyleft requiring source disclosure"
  },
  {
    spdx_id: "GPL-3.0-only",
    name: "GNU General Public License v3.0 only",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/gpl-3.0.html",
    description: "Strong copyleft with patent provisions"
  },
  {
    spdx_id: "GPL-2.0-or-later",
    name: "GNU General Public License v2.0 or later",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/gpl-2.0.html",
    description: "Strong copyleft with upgrade option"
  },
  {
    spdx_id: "GPL-3.0-or-later",
    name: "GNU General Public License v3.0 or later",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/gpl-3.0.html",
    description: "Strong copyleft with upgrade option"
  },

  # Network Copyleft Licenses
  {
    spdx_id: "AGPL-3.0-only",
    name: "GNU Affero General Public License v3.0 only",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: true,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/agpl-3.0.html",
    description: "Network copyleft requiring source disclosure"
  },
  {
    spdx_id: "AGPL-3.0-or-later",
    name: "GNU Affero General Public License v3.0 or later",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: true,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.gnu.org/licenses/agpl-3.0.html",
    description: "Network copyleft with upgrade option"
  },
  {
    spdx_id: "SSPL-1.0",
    name: "Server Side Public License, v 1",
    category: "copyleft",
    is_copyleft: true,
    is_strong_copyleft: true,
    is_network_copyleft: true,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://www.mongodb.com/licensing/server-side-public-license",
    description: "Strong network copyleft from MongoDB"
  },

  # Proprietary / Unknown
  {
    spdx_id: "NOASSERTION",
    name: "No License Assertion",
    category: "unknown",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    description: "License information not available"
  },
  {
    spdx_id: "NONE",
    name: "No License (All Rights Reserved)",
    category: "proprietary",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    description: "Proprietary with all rights reserved"
  },

  # Additional Common Licenses
  {
    spdx_id: "CC-BY-4.0",
    name: "Creative Commons Attribution 4.0 International",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://creativecommons.org/licenses/by/4.0/",
    description: "Attribution required for use"
  },
  {
    spdx_id: "CC-BY-SA-4.0",
    name: "Creative Commons Attribution Share Alike 4.0 International",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://creativecommons.org/licenses/by-sa/4.0/",
    description: "Attribution with share alike"
  },
  {
    spdx_id: "Python-2.0",
    name: "Python License 2.0",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.python.org/psf/license/",
    description: "Python Software Foundation License"
  },
  {
    spdx_id: "Artistic-2.0",
    name: "Artistic License 2.0",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/Artistic-2.0",
    description: "Perl Foundation license"
  },
  {
    spdx_id: "BSL-1.0",
    name: "Boost Software License 1.0",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.boost.org/LICENSE_1_0.txt",
    description: "Boost C++ library license"
  },
  {
    spdx_id: "PostgreSQL",
    name: "PostgreSQL License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.postgresql.org/about/licence/",
    description: "PostgreSQL database license"
  },
  {
    spdx_id: "Ruby",
    name: "Ruby License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://www.ruby-lang.org/en/about/license.txt",
    description: "Ruby programming language license"
  },
  {
    spdx_id: "OpenSSL",
    name: "OpenSSL License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: false,
    is_deprecated: false,
    url: "https://www.openssl.org/source/license.html",
    description: "OpenSSL project license"
  },
  {
    spdx_id: "MS-PL",
    name: "Microsoft Public License",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/MS-PL",
    description: "Microsoft permissive license"
  },
  {
    spdx_id: "MS-RL",
    name: "Microsoft Reciprocal License",
    category: "weak_copyleft",
    is_copyleft: true,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://opensource.org/licenses/MS-RL",
    description: "Microsoft weak copyleft license"
  },
  {
    spdx_id: "Unicode-DFS-2016",
    name: "Unicode License Agreement - Data Files and Software (2016)",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://www.unicode.org/license.html",
    description: "Unicode Consortium license"
  },
  {
    spdx_id: "BlueOak-1.0.0",
    name: "Blue Oak Model License 1.0.0",
    category: "permissive",
    is_copyleft: false,
    is_strong_copyleft: false,
    is_network_copyleft: false,
    is_osi_approved: true,
    is_deprecated: false,
    url: "https://blueoakcouncil.org/license/1.0.0",
    description: "Modern permissive license"
  }
]

licenses.each do |license_data|
  license = SupplyChain::License.find_or_initialize_by(spdx_id: license_data[:spdx_id])
  license.assign_attributes(license_data)
  license.save!
  print "."
end

puts "\nSeeded #{licenses.count} SPDX licenses."
