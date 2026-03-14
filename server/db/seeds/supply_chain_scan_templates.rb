# frozen_string_literal: true

# Seed system scan templates for common ecosystems and use cases

puts "Seeding Supply Chain scan templates..."

scan_templates = [
  # Security Scan Templates
  {
    name: "NPM Security Scan",
    slug: "npm-security-scan",
    description: "Comprehensive security scan for Node.js/NPM projects. Generates SBOM, detects vulnerabilities, and checks for malicious packages.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "npm", "nodejs", "javascript", "typescript" ],
    average_rating: 4.8,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        include_dev_dependencies: { type: "boolean", default: false, description: "Include devDependencies in scan" },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        fail_on_vulnerability: { type: "boolean", default: true },
        generate_sbom: { type: "boolean", default: true },
        sbom_format: { type: "string", enum: [ "cyclonedx_1_5", "spdx_2_3" ], default: "cyclonedx_1_5" }
      },
      required: [ "severity_threshold" ]
    },
    default_configuration: {
      include_dev_dependencies: false,
      severity_threshold: "high",
      fail_on_vulnerability: true,
      generate_sbom: true,
      sbom_format: "cyclonedx_1_5"
    }
  },
  {
    name: "Ruby Gem Security Scan",
    slug: "ruby-gem-security-scan",
    description: "Security scan for Ruby/Rails projects using Bundler. Detects vulnerable gems and license compliance issues.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "gem", "ruby", "rails", "bundler" ],
    average_rating: 4.7,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        include_development: { type: "boolean", default: false },
        include_test: { type: "boolean", default: false },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        check_bundler_audit: { type: "boolean", default: true },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      include_development: false,
      include_test: false,
      severity_threshold: "high",
      check_bundler_audit: true,
      generate_sbom: true
    }
  },
  {
    name: "Python Pip Security Scan",
    slug: "python-pip-security-scan",
    description: "Security scan for Python projects. Supports requirements.txt, Pipfile, pyproject.toml, and Poetry.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "pip", "python", "poetry", "pipenv" ],
    average_rating: 4.6,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        manifest_files: { type: "array", description: "Specific manifest files to scan" },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        check_safety_db: { type: "boolean", default: true },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      manifest_files: [],
      severity_threshold: "high",
      check_safety_db: true,
      generate_sbom: true
    }
  },
  {
    name: "Go Module Security Scan",
    slug: "go-module-security-scan",
    description: "Security scan for Go projects using Go modules. Detects vulnerable dependencies via govulncheck.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "go", "golang" ],
    average_rating: 4.5,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        use_govulncheck: { type: "boolean", default: true },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      use_govulncheck: true,
      severity_threshold: "high",
      generate_sbom: true
    }
  },
  {
    name: "Maven/Gradle Security Scan",
    slug: "maven-gradle-security-scan",
    description: "Security scan for Java projects using Maven or Gradle. Integrates with OWASP Dependency-Check.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "maven", "gradle", "java", "kotlin" ],
    average_rating: 4.6,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        build_tool: { type: "string", enum: [ "maven", "gradle", "auto" ], default: "auto" },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        use_owasp_check: { type: "boolean", default: true },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      build_tool: "auto",
      severity_threshold: "high",
      use_owasp_check: true,
      generate_sbom: true
    }
  },
  {
    name: "Rust Cargo Security Scan",
    slug: "rust-cargo-security-scan",
    description: "Security scan for Rust projects using Cargo. Uses cargo-audit for vulnerability detection.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "cargo", "rust" ],
    average_rating: 4.7,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        use_cargo_audit: { type: "boolean", default: true },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "medium" },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      use_cargo_audit: true,
      severity_threshold: "high",
      generate_sbom: true
    }
  },

  # Container Security Templates
  {
    name: "Container Image Scan (Trivy)",
    slug: "container-trivy-scan",
    description: "Comprehensive container image scanning using Trivy. Detects OS and application vulnerabilities, misconfigurations, and secrets.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "docker", "oci", "container" ],
    average_rating: 4.9,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        scanner: { type: "string", enum: [ "trivy", "grype" ], default: "trivy" },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "high" },
        scan_secrets: { type: "boolean", default: true },
        scan_misconfig: { type: "boolean", default: true },
        ignore_unfixed: { type: "boolean", default: false },
        generate_sbom: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      scanner: "trivy",
      severity_threshold: "high",
      scan_secrets: true,
      scan_misconfig: true,
      ignore_unfixed: false,
      generate_sbom: true
    }
  },

  # License Compliance Templates
  {
    name: "License Compliance Scan",
    slug: "license-compliance-scan",
    description: "Scan dependencies for license compliance. Detects copyleft, GPL contamination, and license conflicts.",
    category: "license",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "npm", "gem", "pip", "maven", "go", "cargo" ],
    average_rating: 4.5,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        block_copyleft: { type: "boolean", default: false },
        block_strong_copyleft: { type: "boolean", default: true },
        block_network_copyleft: { type: "boolean", default: true },
        allowed_licenses: { type: "array", description: "Explicitly allowed SPDX license IDs" },
        denied_licenses: { type: "array", description: "Explicitly denied SPDX license IDs" },
        require_osi_approved: { type: "boolean", default: false },
        generate_attribution: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      block_copyleft: false,
      block_strong_copyleft: true,
      block_network_copyleft: true,
      allowed_licenses: [],
      denied_licenses: [ "SSPL-1.0" ],
      require_osi_approved: false,
      generate_attribution: true
    }
  },

  # Compliance Templates
  {
    name: "NTIA SBOM Compliance",
    slug: "ntia-sbom-compliance",
    description: "Validate SBOM against NTIA minimum elements for software transparency. Required for US government contracts.",
    category: "compliance",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "all" ],
    average_rating: 4.4,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        strict_mode: { type: "boolean", default: true, description: "Fail if SBOM doesn't meet NTIA minimum" },
        require_supplier: { type: "boolean", default: true },
        require_version: { type: "boolean", default: true },
        require_unique_identifier: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      strict_mode: true,
      require_supplier: true,
      require_version: true,
      require_unique_identifier: true
    }
  },
  {
    name: "EU Cyber Resilience Act (CRA)",
    slug: "eu-cra-compliance",
    description: "Compliance scan for EU Cyber Resilience Act requirements. Validates SBOM, vulnerability handling, and documentation.",
    category: "compliance",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "all" ],
    average_rating: 4.3,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        product_category: { type: "string", enum: [ "default", "important_class_1", "important_class_2", "critical" ], default: "default" },
        require_sbom: { type: "boolean", default: true },
        require_vulnerability_process: { type: "boolean", default: true },
        max_vulnerability_age_days: { type: "integer", default: 90 }
      }
    },
    default_configuration: {
      product_category: "default",
      require_sbom: true,
      require_vulnerability_process: true,
      max_vulnerability_age_days: 90
    }
  },

  # Full Pipeline Templates
  {
    name: "Full Supply Chain Scan",
    slug: "full-supply-chain-scan",
    description: "Comprehensive supply chain scan including SBOM generation, vulnerability detection, license compliance, and SLSA attestation.",
    category: "security",
    status: "published",
    version: "1.0.0",
    is_system: true,
    is_public: true,
    supported_ecosystems: [ "npm", "gem", "pip", "maven", "go", "cargo", "docker" ],
    average_rating: 4.9,
    install_count: 0,
    configuration_schema: {
      type: "object",
      properties: {
        generate_sbom: { type: "boolean", default: true },
        sbom_format: { type: "string", enum: [ "cyclonedx_1_5", "spdx_2_3" ], default: "cyclonedx_1_5" },
        scan_vulnerabilities: { type: "boolean", default: true },
        severity_threshold: { type: "string", enum: [ "critical", "high", "medium", "low" ], default: "high" },
        check_licenses: { type: "boolean", default: true },
        block_copyleft: { type: "boolean", default: false },
        generate_attestation: { type: "boolean", default: true },
        slsa_level: { type: "integer", enum: [ 1, 2, 3 ], default: 2 },
        sign_artifacts: { type: "boolean", default: true }
      }
    },
    default_configuration: {
      generate_sbom: true,
      sbom_format: "cyclonedx_1_5",
      scan_vulnerabilities: true,
      severity_threshold: "high",
      check_licenses: true,
      block_copyleft: false,
      generate_attestation: true,
      slsa_level: 2,
      sign_artifacts: true
    }
  }
]

scan_templates.each do |template_data|
  template = SupplyChain::ScanTemplate.find_or_initialize_by(slug: template_data[:slug])
  template.assign_attributes(template_data)
  template.save!
  print "."
end

puts "\nSeeded #{scan_templates.count} scan templates."
