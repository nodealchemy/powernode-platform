# frozen_string_literal: true

# Seed default questionnaire templates for vendor risk assessments

puts "Seeding Supply Chain questionnaire templates..."

# SOC 2 Type II Questionnaire Template
soc2_template = SupplyChain::QuestionnaireTemplate.find_or_initialize_by(
  name: "SOC 2 Type II Security Questionnaire",
  is_system: true
)
soc2_template.assign_attributes(
  template_type: "soc2",
  description: "Standard SOC 2 Type II security questionnaire covering the Trust Services Criteria",
  version: "1.0",
  is_active: true,
  sections: [
    {
      id: "cc1",
      name: "Control Environment",
      description: "Organization and Management",
      weight: 15,
      order: 0
    },
    {
      id: "cc2",
      name: "Communication and Information",
      description: "Internal and External Communication",
      weight: 10,
      order: 1
    },
    {
      id: "cc3",
      name: "Risk Assessment",
      description: "Risk Identification and Assessment",
      weight: 15,
      order: 2
    },
    {
      id: "cc5",
      name: "Control Activities",
      description: "Policies and Procedures",
      weight: 15,
      order: 3
    },
    {
      id: "cc6",
      name: "Logical and Physical Access Controls",
      description: "Access Control Systems",
      weight: 20,
      order: 4
    },
    {
      id: "cc7",
      name: "System Operations",
      description: "Operational Security",
      weight: 15,
      order: 5
    },
    {
      id: "cc9",
      name: "Risk Mitigation",
      description: "Incident Response and Recovery",
      weight: 10,
      order: 6
    }
  ],
  questions: [
    # CC1 - Control Environment
    {
      id: "cc1_1",
      section_id: "cc1",
      text: "Does your organization have a documented information security policy?",
      type: "yes_no",
      required: true,
      weight: 5,
      order: 0
    },
    {
      id: "cc1_2",
      section_id: "cc1",
      text: "Is there a designated person or team responsible for information security?",
      type: "yes_no",
      required: true,
      weight: 5,
      order: 1
    },
    {
      id: "cc1_3",
      section_id: "cc1",
      text: "How often is the security policy reviewed and updated?",
      type: "single_choice",
      required: true,
      weight: 5,
      order: 2,
      options: ["Annually", "Semi-annually", "Quarterly", "As needed", "Never"]
    },
    # CC6 - Access Controls
    {
      id: "cc6_1",
      section_id: "cc6",
      text: "Do you require multi-factor authentication for system access?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "cc6_2",
      section_id: "cc6",
      text: "How is user access provisioned and deprovisioned?",
      type: "text",
      required: true,
      weight: 5,
      order: 1
    },
    {
      id: "cc6_3",
      section_id: "cc6",
      text: "What encryption standards are used for data at rest?",
      type: "single_choice",
      required: true,
      weight: 10,
      order: 2,
      options: ["AES-256", "AES-128", "Other", "None"]
    },
    # CC7 - System Operations
    {
      id: "cc7_1",
      section_id: "cc7",
      text: "Do you have an incident response plan?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "cc7_2",
      section_id: "cc7",
      text: "How often do you conduct security testing (penetration testing, vulnerability scans)?",
      type: "single_choice",
      required: true,
      weight: 5,
      order: 1,
      options: ["Continuously", "Quarterly", "Annually", "Never"]
    },
    # CC9 - Risk Mitigation
    {
      id: "cc9_1",
      section_id: "cc9",
      text: "Do you have a business continuity/disaster recovery plan?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "cc9_2",
      section_id: "cc9",
      text: "What is your Recovery Time Objective (RTO)?",
      type: "single_choice",
      required: false,
      weight: 5,
      order: 1,
      options: ["< 1 hour", "1-4 hours", "4-24 hours", "> 24 hours", "Not defined"]
    }
  ],
  metadata: {
    scoring_rules: {
      yes_value: 100,
      no_value: 0,
      partial_value: 50,
      passing_threshold: 70
    }
  }
)
soc2_template.save!
print "."

# ISO 27001 Questionnaire Template
iso27001_template = SupplyChain::QuestionnaireTemplate.find_or_initialize_by(
  name: "ISO 27001 Security Assessment",
  is_system: true
)
iso27001_template.assign_attributes(
  template_type: "iso27001",
  description: "ISO 27001 Information Security Management System assessment questionnaire",
  version: "1.0",
  is_active: true,
  sections: [
    {
      id: "a5",
      name: "Information Security Policies",
      description: "Management direction for information security",
      weight: 10,
      order: 0
    },
    {
      id: "a6",
      name: "Organization of Information Security",
      description: "Internal organization and mobile devices/teleworking",
      weight: 10,
      order: 1
    },
    {
      id: "a9",
      name: "Access Control",
      description: "Business requirements and user access management",
      weight: 20,
      order: 2
    },
    {
      id: "a12",
      name: "Operations Security",
      description: "Operational procedures and malware protection",
      weight: 20,
      order: 3
    },
    {
      id: "a17",
      name: "Business Continuity",
      description: "Information security continuity",
      weight: 15,
      order: 4
    },
    {
      id: "a18",
      name: "Compliance",
      description: "Legal and contractual requirements",
      weight: 15,
      order: 5
    }
  ],
  questions: [
    {
      id: "a5_1",
      section_id: "a5",
      text: "Are information security policies approved by management?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "a9_1",
      section_id: "a9",
      text: "Is there a formal user registration and de-registration process?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "a9_2",
      section_id: "a9",
      text: "Are user access rights reviewed at regular intervals?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "a12_1",
      section_id: "a12",
      text: "Are operating procedures documented and available?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "a12_2",
      section_id: "a12",
      text: "Is malware protection implemented and regularly updated?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "a17_1",
      section_id: "a17",
      text: "Is information security continuity embedded in business continuity management?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 0
    },
    {
      id: "a18_1",
      section_id: "a18",
      text: "Are applicable legal, statutory, and contractual requirements identified?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 0
    }
  ],
  metadata: {
    scoring_rules: {
      yes_value: 100,
      no_value: 0,
      partial_value: 50,
      passing_threshold: 75
    }
  }
)
iso27001_template.save!
print "."

# GDPR Data Processing Questionnaire
gdpr_template = SupplyChain::QuestionnaireTemplate.find_or_initialize_by(
  name: "GDPR Data Processing Assessment",
  is_system: true
)
gdpr_template.assign_attributes(
  template_type: "gdpr",
  description: "GDPR compliance questionnaire for data processors",
  version: "1.0",
  is_active: true,
  sections: [
    {
      id: "data_handling",
      name: "Data Handling",
      description: "Personal data processing practices",
      weight: 30,
      order: 0
    },
    {
      id: "security",
      name: "Security Measures",
      description: "Technical and organizational measures",
      weight: 30,
      order: 1
    },
    {
      id: "rights",
      name: "Data Subject Rights",
      description: "Support for data subject rights",
      weight: 20,
      order: 2
    },
    {
      id: "transfers",
      name: "International Transfers",
      description: "Cross-border data transfers",
      weight: 20,
      order: 3
    }
  ],
  questions: [
    {
      id: "dh_1",
      section_id: "data_handling",
      text: "What categories of personal data do you process on our behalf?",
      type: "multi_choice",
      required: true,
      weight: 10,
      order: 0,
      options: ["Names", "Email addresses", "IP addresses", "Financial data", "Health data", "Location data", "Other"]
    },
    {
      id: "dh_2",
      section_id: "data_handling",
      text: "Do you use any sub-processors for data processing?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "sec_1",
      section_id: "security",
      text: "Is personal data encrypted in transit and at rest?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 0
    },
    {
      id: "sec_2",
      section_id: "security",
      text: "Do you maintain an audit log of data access?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "rights_1",
      section_id: "rights",
      text: "Can you support data subject access requests within 30 days?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "rights_2",
      section_id: "rights",
      text: "Can you support data deletion requests?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "trans_1",
      section_id: "transfers",
      text: "Do you transfer personal data outside the EU/EEA?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "trans_2",
      section_id: "transfers",
      text: "If yes, what transfer mechanism do you use?",
      type: "single_choice",
      required: false,
      weight: 10,
      order: 1,
      options: ["Standard Contractual Clauses", "Binding Corporate Rules", "Adequacy Decision", "None/Not applicable"]
    }
  ],
  metadata: {
    scoring_rules: {
      yes_value: 100,
      no_value: 0,
      partial_value: 50,
      passing_threshold: 80
    }
  }
)
gdpr_template.save!
print "."

# HIPAA Business Associate Questionnaire
hipaa_template = SupplyChain::QuestionnaireTemplate.find_or_initialize_by(
  name: "HIPAA Business Associate Assessment",
  is_system: true
)
hipaa_template.assign_attributes(
  template_type: "hipaa",
  description: "HIPAA compliance questionnaire for business associates handling PHI",
  version: "1.0",
  is_active: true,
  sections: [
    {
      id: "admin",
      name: "Administrative Safeguards",
      description: "Policies and procedures",
      weight: 35,
      order: 0
    },
    {
      id: "physical",
      name: "Physical Safeguards",
      description: "Physical security controls",
      weight: 25,
      order: 1
    },
    {
      id: "technical",
      name: "Technical Safeguards",
      description: "Technical security controls",
      weight: 40,
      order: 2
    }
  ],
  questions: [
    {
      id: "admin_1",
      section_id: "admin",
      text: "Do you have a designated Privacy Officer?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 0
    },
    {
      id: "admin_2",
      section_id: "admin",
      text: "Do you conduct regular HIPAA training for workforce members?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "admin_3",
      section_id: "admin",
      text: "Do you have breach notification procedures?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 2
    },
    {
      id: "phys_1",
      section_id: "physical",
      text: "Are data centers physically secured with access controls?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 0
    },
    {
      id: "phys_2",
      section_id: "physical",
      text: "Is there a policy for workstation and device security?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 1
    },
    {
      id: "tech_1",
      section_id: "technical",
      text: "Is PHI encrypted at rest using AES-256 or equivalent?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 0
    },
    {
      id: "tech_2",
      section_id: "technical",
      text: "Is PHI encrypted in transit using TLS 1.2 or higher?",
      type: "yes_no",
      required: true,
      weight: 15,
      order: 1
    },
    {
      id: "tech_3",
      section_id: "technical",
      text: "Do you maintain audit logs of PHI access?",
      type: "yes_no",
      required: true,
      weight: 10,
      order: 2
    }
  ],
  metadata: {
    scoring_rules: {
      yes_value: 100,
      no_value: 0,
      partial_value: 50,
      passing_threshold: 85
    }
  }
)
hipaa_template.save!
print "."

puts "\nSeeded 4 questionnaire templates."
