# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_license, class: "SupplyChain::License" do
    sequence(:spdx_id) { |n| "License-#{n}.0" }
    sequence(:name) { |n| "Test License #{n}" }
    category { "permissive" }
    is_osi_approved { true }
    is_copyleft { false }
    is_strong_copyleft { false }
    is_network_copyleft { false }
    is_deprecated { false }
    url { "https://opensource.org/licenses/MIT" }
    compatibility { {} }
    detection_patterns { [] }
    metadata { {} }

    # Permissive license traits
    trait :permissive do
      category { "permissive" }
      is_copyleft { false }
      is_strong_copyleft { false }
      is_network_copyleft { false }
    end

    trait :mit do
      spdx_id { "MIT" }
      name { "MIT License" }
      category { "permissive" }
      is_osi_approved { true }
      url { "https://opensource.org/licenses/MIT" }
    end

    trait :apache_2 do
      spdx_id { "Apache-2.0" }
      name { "Apache License 2.0" }
      category { "permissive" }
      is_osi_approved { true }
      url { "https://opensource.org/licenses/Apache-2.0" }
    end

    trait :bsd_3_clause do
      spdx_id { "BSD-3-Clause" }
      name { "BSD 3-Clause License" }
      category { "permissive" }
      is_osi_approved { true }
      url { "https://opensource.org/licenses/BSD-3-Clause" }
    end

    # Copyleft license traits
    trait :copyleft do
      category { "copyleft" }
      is_copyleft { true }
      is_strong_copyleft { true }
      is_network_copyleft { false }
    end

    trait :network_copyleft do
      category { "copyleft" }
      is_copyleft { true }
      is_strong_copyleft { true }
      is_network_copyleft { true }
    end

    trait :gpl_3 do
      spdx_id { "GPL-3.0-only" }
      name { "GNU General Public License v3.0 only" }
      category { "copyleft" }
      is_osi_approved { true }
      is_copyleft { true }
      is_strong_copyleft { true }
      url { "https://opensource.org/licenses/GPL-3.0" }
    end

    trait :agpl_3 do
      spdx_id { "AGPL-3.0-only" }
      name { "GNU Affero General Public License v3.0" }
      category { "copyleft" }
      is_osi_approved { true }
      is_copyleft { true }
      is_strong_copyleft { true }
      is_network_copyleft { true }
      url { "https://opensource.org/licenses/AGPL-3.0" }
    end

    # Weak copyleft license traits
    trait :weak_copyleft do
      category { "weak_copyleft" }
      is_copyleft { true }
      is_strong_copyleft { false }
      is_network_copyleft { false }
    end

    trait :lgpl_3 do
      spdx_id { "LGPL-3.0-only" }
      name { "GNU Lesser General Public License v3.0 only" }
      category { "weak_copyleft" }
      is_osi_approved { true }
      is_copyleft { true }
      is_strong_copyleft { false }
      url { "https://opensource.org/licenses/LGPL-3.0" }
    end

    trait :mpl_2 do
      spdx_id { "MPL-2.0" }
      name { "Mozilla Public License 2.0" }
      category { "weak_copyleft" }
      is_osi_approved { true }
      is_copyleft { true }
      is_strong_copyleft { false }
      url { "https://opensource.org/licenses/MPL-2.0" }
    end

    # Public domain traits
    trait :public_domain do
      category { "public_domain" }
      is_copyleft { false }
      is_strong_copyleft { false }
      is_network_copyleft { false }
    end

    trait :cc0 do
      spdx_id { "CC0-1.0" }
      name { "Creative Commons Zero v1.0 Universal" }
      category { "public_domain" }
      is_osi_approved { false }
      url { "https://creativecommons.org/publicdomain/zero/1.0/" }
    end

    trait :unlicense do
      spdx_id { "Unlicense" }
      name { "The Unlicense" }
      category { "public_domain" }
      is_osi_approved { true }
      url { "https://unlicense.org/" }
    end

    # Proprietary license traits
    trait :proprietary do
      spdx_id { "LicenseRef-Proprietary" }
      name { "Proprietary License" }
      category { "proprietary" }
      is_osi_approved { false }
      is_copyleft { false }
    end

    # Other traits
    trait :deprecated do
      is_deprecated { true }
    end

    trait :not_osi_approved do
      is_osi_approved { false }
    end

    trait :with_compatibility do
      compatibility { { "compatible_with" => [ "MIT", "Apache-2.0", "BSD-3-Clause" ] } }
    end

    trait :with_detection_patterns do
      detection_patterns { [ "MIT License", "Permission is hereby granted" ] }
    end

    trait :unknown do
      spdx_id { "LicenseRef-Unknown" }
      name { "Unknown License" }
      category { "unknown" }
      is_osi_approved { false }
    end
  end
end
