# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_attribution, class: "SupplyChain::Attribution" do
    association :account
    association :sbom_component, factory: :supply_chain_sbom_component
    association :license, factory: :supply_chain_license
    package_name { Faker::Internet.slug }
    package_version { Faker::App.semantic_version }
    requires_attribution { true }
    requires_license_copy { false }
    requires_source_disclosure { false }
    copyright_holder { nil }
    copyright_year { nil }
    license_text { nil }
    notice_text { nil }
    attribution_url { nil }
    metadata { {} }

    # Copyright traits
    trait :with_copyright do
      copyright_holder { Faker::Company.name }
      copyright_year { rand(2010..2024) }
    end

    trait :with_full_copyright do
      copyright_holder { Faker::Company.name }
      copyright_year { rand(2010..2024) }
      attribution_url { "https://github.com/#{Faker::Internet.slug}/#{package_name}" }
    end

    # License text traits
    trait :with_license_text do
      requires_license_copy { true }
      license_text do
        <<~LICENSE
          MIT License

          Copyright (c) #{copyright_year || 2024} #{copyright_holder || Faker::Company.name}

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
          FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
          AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
          LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
          OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
          SOFTWARE.
        LICENSE
      end
    end

    trait :with_apache_license_text do
      requires_license_copy { true }
      license_text do
        <<~LICENSE
          Apache License
          Version 2.0, January 2004
          http://www.apache.org/licenses/

          TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION
          ...
        LICENSE
      end
    end

    # Notice traits
    trait :with_notice do
      notice_text { "This software includes third-party components licensed under various open source licenses." }
    end

    trait :with_detailed_notice do
      notice_text do
        <<~NOTICE_TEXT
          NOTICE

          This product includes software developed by #{Faker::Company.name}.

          This software contains code derived from the following projects:
          - #{Faker::App.name}: Licensed under MIT
          - #{Faker::App.name}: Licensed under Apache 2.0

          Please see the LICENSE file for full license terms.
        NOTICE_TEXT
      end
    end

    # Requirement traits
    trait :attribution_required do
      requires_attribution { true }
      requires_license_copy { false }
      requires_source_disclosure { false }
    end

    trait :license_copy_required do
      requires_attribution { true }
      requires_license_copy { true }
      requires_source_disclosure { false }
    end

    trait :source_disclosure_required do
      requires_attribution { true }
      requires_license_copy { true }
      requires_source_disclosure { true }
    end

    trait :no_requirements do
      requires_attribution { false }
      requires_license_copy { false }
      requires_source_disclosure { false }
    end

    # Full attribution with all fields
    trait :complete do
      copyright_holder { Faker::Company.name }
      copyright_year { rand(2015..2024) }
      requires_attribution { true }
      requires_license_copy { true }
      requires_source_disclosure { false }
      attribution_url { "https://github.com/#{Faker::Internet.slug}/#{package_name}" }
      license_text do
        <<~LICENSE
          MIT License

          Copyright (c) #{copyright_year} #{copyright_holder}

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
      end
      notice_text { "This software includes the #{package_name} package." }
    end

    # License type specific traits
    trait :mit_attribution do
      requires_attribution { true }
      requires_license_copy { true }
      requires_source_disclosure { false }
      after(:build) do |attribution|
        attribution.license ||= create(:supply_chain_license, :permissive)
      end
    end

    trait :gpl_attribution do
      requires_attribution { true }
      requires_license_copy { true }
      requires_source_disclosure { true }
      after(:build) do |attribution|
        attribution.license ||= create(:supply_chain_license, :copyleft)
      end
    end

    # Metadata traits
    trait :with_metadata do
      metadata do
        {
          generated_at: Time.current.iso8601,
          source: "automated",
          verified: true
        }
      end
    end

    # Ecosystem-specific traits
    trait :npm_package do
      package_name { "@#{Faker::Internet.slug}/#{Faker::Hacker.noun.downcase.gsub(' ', '-')}" }
      metadata do
        {
          ecosystem: "npm",
          registry_url: "https://www.npmjs.com/package/#{package_name}"
        }
      end
    end

    trait :gem_package do
      package_name { Faker::Hacker.noun.downcase.gsub(' ', '_') }
      metadata do
        {
          ecosystem: "rubygems",
          registry_url: "https://rubygems.org/gems/#{package_name}"
        }
      end
    end

    trait :pypi_package do
      package_name { Faker::Hacker.noun.downcase.gsub(' ', '-') }
      metadata do
        {
          ecosystem: "pypi",
          registry_url: "https://pypi.org/project/#{package_name}"
        }
      end
    end
  end
end
