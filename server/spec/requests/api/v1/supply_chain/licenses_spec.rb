# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Licenses", type: :request do
  # Note: Licenses controller does NOT require authentication - it's a reference data endpoint

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/licenses" do
    let!(:mit_license) do
      create(:supply_chain_license, :permissive,
             spdx_id: "MIT",
             name: "MIT License",
             category: "permissive",
             is_osi_approved: true,
             is_copyleft: false,
             is_deprecated: false)
    end

    let!(:gpl_license) do
      create(:supply_chain_license, :copyleft,
             spdx_id: "GPL-3.0-only",
             name: "GNU General Public License v3.0",
             category: "copyleft",
             is_osi_approved: true,
             is_copyleft: true,
             is_strong_copyleft: true,
             is_deprecated: false)
    end

    let!(:agpl_license) do
      create(:supply_chain_license, :network_copyleft,
             spdx_id: "AGPL-3.0-only",
             name: "GNU Affero General Public License v3.0",
             category: "copyleft",
             is_osi_approved: true,
             is_copyleft: true,
             is_strong_copyleft: true,
             is_network_copyleft: true,
             is_deprecated: false)
    end

    let!(:deprecated_license) do
      create(:supply_chain_license,
             spdx_id: "GPL-2.0",
             name: "GNU General Public License v2.0",
             category: "copyleft",
             is_copyleft: true,
             is_deprecated: true)
    end

    context "without authentication" do
      it "returns all licenses successfully" do
        get "/api/v1/supply_chain/licenses", as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json["success"]).to be true
        expect(json["data"]["licenses"]).to be_an(Array)
        expect(json["data"]["licenses"].length).to be >= 3
      end
    end

    context "with category filter" do
      it "filters by permissive category" do
        get "/api/v1/supply_chain/licenses?category=permissive", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["category"] == "permissive" }).to be true
        expect(licenses.any? { |l| l["spdx_id"] == "MIT" }).to be true
      end

      it "filters by copyleft category" do
        get "/api/v1/supply_chain/licenses?category=copyleft", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["category"] == "copyleft" }).to be true
        expect(licenses.any? { |l| l["spdx_id"] == "GPL-3.0-only" }).to be true
      end
    end

    context "with osi_approved filter" do
      it "returns only OSI approved licenses" do
        create(:supply_chain_license,
               spdx_id: "Custom-1.0",
               name: "Custom License",
               category: "proprietary",
               is_osi_approved: false)

        get "/api/v1/supply_chain/licenses?osi_approved=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["is_osi_approved"] == true }).to be true
      end
    end

    context "with copyleft filter" do
      it "returns only copyleft licenses" do
        get "/api/v1/supply_chain/licenses?copyleft=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["is_copyleft"] == true }).to be true
        expect(licenses.any? { |l| l["spdx_id"] == "GPL-3.0-only" }).to be true
        expect(licenses.none? { |l| l["spdx_id"] == "MIT" }).to be true
      end
    end

    context "with strong_copyleft filter" do
      it "returns only strong copyleft licenses" do
        get "/api/v1/supply_chain/licenses?strong_copyleft=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["is_strong_copyleft"] == true }).to be true
        expect(licenses.any? { |l| l["spdx_id"] == "GPL-3.0-only" }).to be true
      end
    end

    context "with network_copyleft filter" do
      it "returns only network copyleft licenses" do
        get "/api/v1/supply_chain/licenses?network_copyleft=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["is_network_copyleft"] == true }).to be true
        expect(licenses.any? { |l| l["spdx_id"] == "AGPL-3.0-only" }).to be true
      end
    end

    context "with include_deprecated filter" do
      it "excludes deprecated licenses by default" do
        get "/api/v1/supply_chain/licenses", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.none? { |l| l["is_deprecated"] == true }).to be true
        expect(licenses.none? { |l| l["spdx_id"] == "GPL-2.0" }).to be true
      end

      it "includes deprecated licenses when requested" do
        get "/api/v1/supply_chain/licenses?include_deprecated=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.any? { |l| l["spdx_id"] == "GPL-2.0" }).to be true
      end
    end

    context "with search query" do
      it "searches by SPDX ID" do
        get "/api/v1/supply_chain/licenses?q=MIT", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.any? { |l| l["spdx_id"] == "MIT" }).to be true
      end

      it "searches by name" do
        get "/api/v1/supply_chain/licenses?q=GNU%20General", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.any? { |l| l["name"].include?("GNU General") }).to be true
      end

      it "performs case-insensitive search" do
        get "/api/v1/supply_chain/licenses?q=mit", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.any? { |l| l["spdx_id"] == "MIT" }).to be true
      end
    end

    context "with multiple filters combined" do
      it "combines category and osi_approved filters" do
        get "/api/v1/supply_chain/licenses?category=copyleft&osi_approved=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["category"] == "copyleft" && l["is_osi_approved"] == true }).to be true
      end

      it "combines search with filters" do
        get "/api/v1/supply_chain/licenses?q=GPL&osi_approved=true", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]

        expect(licenses.all? { |l| l["is_osi_approved"] == true }).to be true
        expect(licenses.all? { |l| l["spdx_id"].include?("GPL") || l["name"].include?("GPL") }).to be true
      end
    end

    context "with pagination" do
      it "returns paginated results" do
        get "/api/v1/supply_chain/licenses?page=1&per_page=2", as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["licenses"].length).to be <= 2
        expect(json["data"]["meta"]).to include(
          "current_page",
          "total_pages",
          "total_count",
          "per_page"
        )
      end

      it "includes correct pagination metadata" do
        get "/api/v1/supply_chain/licenses?page=1&per_page=2", as: :json

        expect_success_response
        json = json_response
        meta = json["data"]["meta"]

        expect(meta["current_page"]).to eq(1)
        expect(meta["per_page"]).to eq(2)
        expect(meta["total_count"]).to be >= 3
      end
    end

    context "response structure" do
      it "returns licenses in alphabetical order by name" do
        get "/api/v1/supply_chain/licenses", as: :json

        expect_success_response
        json = json_response
        licenses = json["data"]["licenses"]
        names = licenses.map { |l| l["name"] }

        expect(names).to eq(names.sort)
      end

      it "includes all expected fields in license data" do
        get "/api/v1/supply_chain/licenses", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["licenses"].first

        expect(license).to include(
          "id",
          "spdx_id",
          "name",
          "category",
          "is_osi_approved",
          "is_copyleft",
          "is_strong_copyleft",
          "is_network_copyleft",
          "is_deprecated",
          "risk_level",
          "url"
        )
      end

      it "does not include detailed fields in list response" do
        get "/api/v1/supply_chain/licenses", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["licenses"].first

        expect(license).not_to include(
          "description",
          "license_text",
          "requires_attribution",
          "requires_license_copy",
          "requires_source_disclosure",
          "compatibility"
        )
      end
    end
  end

  describe "GET /api/v1/supply_chain/licenses/:id" do
    let!(:mit_license) do
      create(:supply_chain_license, :permissive,
             spdx_id: "MIT",
             name: "MIT License",
             category: "permissive",
             is_osi_approved: true,
             description: "A permissive license",
             license_text: "Permission is hereby granted...",
             url: "https://opensource.org/licenses/MIT",
             compatibility: { "compatible_with" => ["Apache-2.0", "GPL-3.0-only"] })
    end

    context "without authentication" do
      it "returns license details successfully" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["license"]["id"]).to eq(mit_license.id)
        expect(json["data"]["license"]["spdx_id"]).to eq("MIT")
      end
    end

    context "by UUID" do
      it "returns license details by UUID" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["id"]).to eq(mit_license.id)
        expect(license["name"]).to eq("MIT License")
      end
    end

    context "by SPDX ID" do
      it "returns license details by SPDX ID" do
        get "/api/v1/supply_chain/licenses/MIT", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["spdx_id"]).to eq("MIT")
        expect(license["name"]).to eq("MIT License")
      end
    end

    context "response structure" do
      it "includes all basic fields" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license).to include(
          "id",
          "spdx_id",
          "name",
          "category",
          "is_osi_approved",
          "is_copyleft",
          "is_strong_copyleft",
          "is_network_copyleft",
          "is_deprecated",
          "risk_level",
          "url"
        )
      end

      it "includes detailed fields in show response" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license).to include(
          "description",
          "license_text",
          "requires_attribution",
          "requires_license_copy",
          "requires_source_disclosure",
          "compatibility"
        )
      end

      it "sets requires_attribution correctly for permissive license" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["requires_attribution"]).to be true
        expect(license["requires_license_copy"]).to be false
        expect(license["requires_source_disclosure"]).to be false
      end

      it "includes compatibility information" do
        get "/api/v1/supply_chain/licenses/#{mit_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["compatibility"]).to be_a(Hash)
        expect(license["compatibility"]["compatible_with"]).to include("Apache-2.0", "GPL-3.0-only")
      end
    end

    context "with copyleft license" do
      let!(:gpl_license) do
        create(:supply_chain_license, :copyleft,
               spdx_id: "GPL-3.0-only",
               name: "GNU General Public License v3.0",
               category: "copyleft",
               is_copyleft: true,
               is_strong_copyleft: true)
      end

      it "sets requires_source_disclosure correctly" do
        get "/api/v1/supply_chain/licenses/#{gpl_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["requires_attribution"]).to be true
        expect(license["requires_license_copy"]).to be true
        expect(license["requires_source_disclosure"]).to be true
        expect(license["risk_level"]).to eq("high")
      end
    end

    context "with network copyleft license" do
      let!(:agpl_license) do
        create(:supply_chain_license, :network_copyleft,
               spdx_id: "AGPL-3.0-only",
               name: "GNU Affero General Public License v3.0",
               category: "copyleft",
               is_copyleft: true,
               is_strong_copyleft: true,
               is_network_copyleft: true)
      end

      it "sets risk_level to critical" do
        get "/api/v1/supply_chain/licenses/#{agpl_license.id}", as: :json

        expect_success_response
        json = json_response
        license = json["data"]["license"]

        expect(license["is_network_copyleft"]).to be true
        expect(license["requires_source_disclosure"]).to be true
        expect(license["risk_level"]).to eq("critical")
      end
    end

    context "error cases" do
      it "returns 404 for non-existent UUID" do
        get "/api/v1/supply_chain/licenses/00000000-0000-0000-0000-000000000000", as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for non-existent SPDX ID" do
        get "/api/v1/supply_chain/licenses/NONEXISTENT-LICENSE", as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/supply_chain/licenses/categories" do
    let!(:mit_license) { create(:supply_chain_license, :permissive, category: "permissive") }
    let!(:gpl_license) { create(:supply_chain_license, :copyleft, category: "copyleft") }
    let!(:gpl2_license) { create(:supply_chain_license, :copyleft, category: "copyleft") }
    let!(:lgpl_license) { create(:supply_chain_license, category: "weak_copyleft") }

    context "without authentication" do
      it "returns all license categories successfully" do
        get "/api/v1/supply_chain/licenses/categories", as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["categories"]).to be_an(Array)
        expect(json["data"]["categories"].length).to eq(SupplyChain::License::CATEGORIES.length)
      end
    end

    context "response structure" do
      it "includes category details with counts" do
        get "/api/v1/supply_chain/licenses/categories", as: :json

        expect_success_response
        json = json_response
        categories = json["data"]["categories"]

        category = categories.first
        expect(category).to include("id", "name", "count")
      end

      it "returns correct counts for each category" do
        get "/api/v1/supply_chain/licenses/categories", as: :json

        expect_success_response
        json = json_response
        categories = json["data"]["categories"]

        permissive = categories.find { |c| c["id"] == "permissive" }
        copyleft = categories.find { |c| c["id"] == "copyleft" }
        weak_copyleft = categories.find { |c| c["id"] == "weak_copyleft" }

        expect(permissive["count"]).to be >= 1
        expect(copyleft["count"]).to be >= 2
        expect(weak_copyleft["count"]).to be >= 1
      end

      it "humanizes category names" do
        get "/api/v1/supply_chain/licenses/categories", as: :json

        expect_success_response
        json = json_response
        categories = json["data"]["categories"]

        weak_copyleft = categories.find { |c| c["id"] == "weak_copyleft" }
        expect(weak_copyleft["name"]).to eq("Weak copyleft")
      end

      it "includes all standard categories" do
        get "/api/v1/supply_chain/licenses/categories", as: :json

        expect_success_response
        json = json_response
        categories = json["data"]["categories"]
        category_ids = categories.map { |c| c["id"] }

        SupplyChain::License::CATEGORIES.each do |expected_category|
          expect(category_ids).to include(expected_category)
        end
      end
    end
  end

  describe "POST /api/v1/supply_chain/licenses/check_compatibility" do
    let!(:mit_license) do
      create(:supply_chain_license, :permissive,
             spdx_id: "MIT",
             name: "MIT License",
             category: "permissive",
             is_copyleft: false)
    end

    let!(:apache_license) do
      create(:supply_chain_license,
             spdx_id: "Apache-2.0",
             name: "Apache License 2.0",
             category: "permissive",
             is_copyleft: false)
    end

    let!(:gpl_license) do
      create(:supply_chain_license, :copyleft,
             spdx_id: "GPL-3.0-only",
             name: "GNU General Public License v3.0",
             category: "copyleft",
             is_copyleft: true,
             is_strong_copyleft: true)
    end

    let!(:lgpl_license) do
      create(:supply_chain_license,
             spdx_id: "LGPL-3.0-only",
             name: "GNU Lesser General Public License v3.0",
             category: "weak_copyleft",
             is_copyleft: true,
             is_strong_copyleft: false)
    end

    let!(:agpl_license) do
      create(:supply_chain_license, :network_copyleft,
             spdx_id: "AGPL-3.0-only",
             name: "GNU Affero General Public License v3.0",
             category: "copyleft",
             is_copyleft: true,
             is_strong_copyleft: true,
             is_network_copyleft: true)
    end

    let!(:public_domain) do
      create(:supply_chain_license,
             spdx_id: "Unlicense",
             name: "The Unlicense",
             category: "public_domain",
             is_copyleft: false)
    end

    context "without authentication" do
      it "checks compatibility successfully" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "Apache-2.0" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]).to include("license1", "license2", "compatible", "explanation")
      end
    end

    context "with compatible licenses" do
      it "returns compatible for two permissive licenses" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "Apache-2.0" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["compatible"]).to be true
        expect(json["data"]["explanation"]).to include("permissive")
      end

      it "returns compatible for public domain with any license" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "Unlicense", license2: "GPL-3.0-only" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["compatible"]).to be true
        expect(json["data"]["explanation"]).to include("Public domain")
      end
    end

    context "with incompatible licenses" do
      it "returns incompatible for different copyleft licenses" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "GPL-3.0-only", license2: "LGPL-3.0-only" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["compatible"]).to be false
        expect(json["data"]["explanation"]).to be_present
      end

      it "returns incompatible for network copyleft licenses" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "AGPL-3.0-only", license2: "MIT" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["compatible"]).to be false
        expect(json["data"]["explanation"]).to include("Network copyleft")
      end
    end

    context "response structure" do
      it "includes license details for both licenses" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "Apache-2.0" },
             as: :json

        expect_success_response
        json = json_response
        data = json["data"]

        expect(data["license1"]).to include(
          "id",
          "spdx_id",
          "name",
          "category",
          "is_copyleft"
        )
        expect(data["license2"]).to include(
          "id",
          "spdx_id",
          "name",
          "category",
          "is_copyleft"
        )
      end

      it "includes compatibility boolean" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "Apache-2.0" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["compatible"]).to be_in([true, false])
      end

      it "includes explanation text" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "Apache-2.0" },
             as: :json

        expect_success_response
        json = json_response

        expect(json["data"]["explanation"]).to be_a(String)
        expect(json["data"]["explanation"].length).to be > 0
      end
    end

    context "error cases" do
      it "returns 404 when first license not found" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "NONEXISTENT", license2: "MIT" },
             as: :json

        expect(response).to have_http_status(:not_found)
        json = json_response
        expect(json["success"]).to be false
        expect(json["error"]).to include("not found")
      end

      it "returns 404 when second license not found" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "MIT", license2: "NONEXISTENT" },
             as: :json

        expect(response).to have_http_status(:not_found)
        json = json_response
        expect(json["success"]).to be false
        expect(json["error"]).to include("not found")
      end

      it "returns 404 when both licenses not found" do
        post "/api/v1/supply_chain/licenses/check_compatibility",
             params: { license1: "NONEXISTENT1", license2: "NONEXISTENT2" },
             as: :json

        expect(response).to have_http_status(:not_found)
        json = json_response
        expect(json["success"]).to be false
      end
    end
  end

  describe "response format consistency" do
    let!(:license) { create(:supply_chain_license, :permissive) }

    it "returns consistent success response format for index" do
      get "/api/v1/supply_chain/licenses", as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json).to have_key("data")
      expect(json["success"]).to be true
    end

    it "returns consistent success response format for show" do
      get "/api/v1/supply_chain/licenses/#{license.id}", as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json).to have_key("data")
      expect(json["success"]).to be true
    end

    it "returns consistent success response format for categories" do
      get "/api/v1/supply_chain/licenses/categories", as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json).to have_key("data")
      expect(json["success"]).to be true
    end

    it "returns consistent success response format for check_compatibility" do
      license2 = create(:supply_chain_license, :permissive, spdx_id: "Apache-2.0")

      post "/api/v1/supply_chain/licenses/check_compatibility",
           params: { license1: license.spdx_id, license2: license2.spdx_id },
           as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json).to have_key("data")
      expect(json["success"]).to be true
    end

    it "returns consistent error response format for not found" do
      get "/api/v1/supply_chain/licenses/00000000-0000-0000-0000-000000000000", as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json["success"]).to be false
    end
  end
end
