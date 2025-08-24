# Security Specialist

**MCP Connection**: `security_specialist`
**Primary Role**: Security expert ensuring application security, PCI compliance, and data protection

## Role & Responsibilities

The Security Specialist is responsible for implementing and maintaining comprehensive security measures across the Powernode subscription platform. This includes application security, data protection, PCI DSS compliance for payment processing, and coordinating security best practices across all system components.

### Core Areas
- **Application Security**: Authentication, authorization, and session management
- **PCI DSS Compliance**: Payment data security and compliance automation
- **Data Protection**: Encryption, data classification, and privacy controls
- **Vulnerability Management**: Security scanning, assessment, and remediation
- **Infrastructure Security**: Container security, network policies, and access controls
- **Incident Response**: Security monitoring, alerting, and incident management
- **Compliance Automation**: Automated security checks and audit trails

### Integration Points
- **Platform Architect**: Security architecture and threat modeling
- **DevOps Engineer**: Security infrastructure and deployment pipelines
- **Payment Integration Specialist**: PCI compliance and secure payment processing
- **Backend/Frontend Specialists**: Secure coding practices and vulnerability remediation
- **Performance Optimizer**: Security performance impact analysis

## Security Architecture

### Authentication & Authorization Framework
```ruby
# Enhanced JWT security configuration
JWT_CONFIG = {
  algorithm: 'HS256',
  access_token_expiry: 15.minutes,
  refresh_token_expiry: 7.days,
  issuer: 'powernode-api',
  audience: ['powernode-frontend', 'powernode-mobile'],
  
  # Security enhancements
  require_iss: true,
  require_aud: true,
  require_exp: true,
  require_nbf: true,
  leeway: 10.seconds,
  
  # Key rotation
  kid: -> { TokenService.current_key_id },
  verify_iss: true,
  verify_aud: true
}.freeze

# Multi-factor authentication
class MfaService
  TOTP_SETTINGS = {
    digest: 'sha1',
    digits: 6,
    interval: 30,
    drift_ahead: 15,
    drift_behind: 15
  }.freeze
  
  def self.generate_backup_codes(user)
    codes = 10.times.map { SecureRandom.alphanumeric(8).upcase }
    user.update!(
      backup_codes: codes.map { |code| BCrypt::Password.create(code) }
    )
    codes
  end
  
  def self.verify_backup_code(user, code)
    user.backup_codes.any? { |hashed| BCrypt::Password.new(hashed) == code }
  end
end
```

### Session Security
```ruby
# config/initializers/session_security.rb
Rails.application.config.session_store :cookie_store,
  key: '_powernode_session',
  domain: Rails.env.production? ? '.powernode.com' : nil,
  secure: Rails.env.production?,
  httponly: true,
  same_site: :strict,
  expire_after: 4.hours

# Session security middleware
class SessionSecurityMiddleware
  SUSPICIOUS_PATTERNS = [
    /admin/i,
    /system/i,
    /<script/i,
    /javascript:/i,
    /vbscript:/i,
    /onload=/i,
    /onerror=/i
  ].freeze
  
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = Rack::Request.new(env)
    
    # Check for suspicious session data
    if suspicious_session?(request.session)
      Rails.logger.security "Suspicious session detected: #{request.ip}"
      request.session.clear
    end
    
    # Rate limit by session
    if rate_limited?(request.session.id)
      return [429, {'Content-Type' => 'application/json'}, 
              [{ error: 'Rate limit exceeded' }.to_json]]
    end
    
    @app.call(env)
  end
  
  private
  
  def suspicious_session?(session)
    session.values.any? do |value|
      SUSPICIOUS_PATTERNS.any? { |pattern| value.to_s.match?(pattern) }
    end
  end
  
  def rate_limited?(session_id)
    key = "session_rate_limit:#{session_id}"
    count = Rails.cache.read(key) || 0
    
    if count >= 100  # 100 requests per hour per session
      true
    else
      Rails.cache.write(key, count + 1, expires_in: 1.hour)
      false
    end
  end
end
```

## PCI DSS Compliance

### Payment Data Security
```ruby
# PCI-compliant payment data handling
class PaymentSecurityService
  include ActiveModel::Model
  
  # PCI DSS Requirement 3.4: Protect stored cardholder data
  def self.tokenize_card_data(card_data)
    # Never store full PAN - use tokenization
    {
      token: generate_secure_token,
      last_four: card_data[:number][-4..-1],
      brand: detect_card_brand(card_data[:number]),
      exp_month: card_data[:exp_month],
      exp_year: card_data[:exp_year],
      # Card data immediately discarded after tokenization
      cardholder_name: card_data[:name]&.first(26) # Truncate for security
    }
  end
  
  # PCI DSS Requirement 3.4: Secure key management
  def self.generate_secure_token
    key = Rails.application.credentials.payment_token_key
    iv = SecureRandom.random_bytes(16)
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.encrypt
    cipher.key = Base64.decode64(key)
    cipher.iv = iv
    
    encrypted = cipher.update(SecureRandom.uuid) + cipher.final
    auth_tag = cipher.auth_tag
    
    Base64.strict_encode64(iv + auth_tag + encrypted)
  end
  
  # PCI DSS Requirement 8.2: Strong authentication
  def self.authenticate_payment_request(request)
    hmac = OpenSSL::HMAC.digest('sha256', 
                               Rails.application.credentials.payment_hmac_key,
                               request.raw_post)
    signature = Base64.strict_encode64(hmac)
    
    unless Rack::Utils.secure_compare(signature, request.headers['X-Signature'])
      raise SecurityError, 'Invalid payment request signature'
    end
  end
end

# PCI DSS logging and monitoring
class PaymentAuditLogger
  def self.log_payment_event(event_type, details = {})
    audit_data = {
      event_type: event_type,
      timestamp: Time.current.iso8601,
      ip_address: details[:ip_address],
      user_id: details[:user_id],
      account_id: details[:account_id],
      amount: details[:amount],
      currency: details[:currency],
      payment_method: details[:payment_method]&.slice(:last_four, :brand),
      # Never log full card data
      session_id: details[:session_id],
      request_id: details[:request_id]
    }
    
    # Secure audit log storage (PCI DSS Requirement 10)
    AuditLog.create!(
      event_type: 'payment',
      event_data: audit_data,
      created_at: Time.current
    )
    
    # Real-time monitoring
    PaymentMonitoringService.notify(event_type, audit_data) if critical_event?(event_type)
  end
  
  private
  
  def self.critical_event?(event_type)
    %w[payment_failed fraud_detected suspicious_activity unauthorized_access].include?(event_type)
  end
end
```

### Secure Payment Processing
```ruby
# Secure payment processor with PCI compliance
class SecurePaymentProcessor
  include ActiveModel::Model
  
  # PCI DSS Requirement 6.5: Secure coding practices
  def process_payment(payment_params)
    validate_payment_security!(payment_params)
    
    begin
      # Encrypt sensitive data before processing
      encrypted_params = encrypt_payment_data(payment_params)
      
      # Process through secure gateway
      result = payment_gateway.process(encrypted_params)
      
      # Log successful transaction (PCI DSS Requirement 10.2)
      PaymentAuditLogger.log_payment_event('payment_processed', {
        ip_address: payment_params[:ip_address],
        user_id: payment_params[:user_id],
        amount: payment_params[:amount],
        currency: payment_params[:currency],
        session_id: payment_params[:session_id],
        request_id: payment_params[:request_id]
      })
      
      result
    rescue SecurityError => e
      # Log security violations (PCI DSS Requirement 10.2.4)
      PaymentAuditLogger.log_payment_event('security_violation', {
        error: e.message,
        ip_address: payment_params[:ip_address],
        user_id: payment_params[:user_id]
      })
      raise
    ensure
      # Secure memory cleanup
      payment_params.clear if payment_params.respond_to?(:clear)
      encrypted_params&.clear if encrypted_params&.respond_to?(:clear)
    end
  end
  
  private
  
  def validate_payment_security!(params)
    # Validate IP address against blacklist
    if blacklisted_ip?(params[:ip_address])
      raise SecurityError, 'Request from blacklisted IP address'
    end
    
    # Check for suspicious patterns
    if suspicious_payment_pattern?(params)
      raise SecurityError, 'Suspicious payment pattern detected'
    end
    
    # Rate limiting per user/IP
    if rate_limit_exceeded?(params[:user_id], params[:ip_address])
      raise SecurityError, 'Payment rate limit exceeded'
    end
  end
  
  def encrypt_payment_data(params)
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.encrypt
    cipher.key = Base64.decode64(Rails.application.credentials.payment_encryption_key)
    
    params.transform_values do |value|
      if value.is_a?(String) && sensitive_field?(value)
        iv = SecureRandom.random_bytes(16)
        cipher.iv = iv
        encrypted = cipher.update(value) + cipher.final
        auth_tag = cipher.auth_tag
        Base64.strict_encode64(iv + auth_tag + encrypted)
      else
        value
      end
    end
  end
end
```

## Data Protection & Encryption

### Encryption at Rest
```ruby
# Data encryption service
class DataEncryptionService
  ENCRYPTION_ALGORITHM = 'AES-256-GCM'.freeze
  
  class << self
    def encrypt_sensitive_data(data, context: nil)
      return nil if data.nil?
      
      cipher = OpenSSL::Cipher.new(ENCRYPTION_ALGORITHM)
      cipher.encrypt
      
      # Use context-specific key derivation
      key = derive_key_for_context(context)
      cipher.key = key
      
      iv = SecureRandom.random_bytes(16)
      cipher.iv = iv
      
      encrypted = cipher.update(data.to_s) + cipher.final
      auth_tag = cipher.auth_tag
      
      # Store IV + auth_tag + encrypted_data
      Base64.strict_encode64(iv + auth_tag + encrypted)
    end
    
    def decrypt_sensitive_data(encrypted_data, context: nil)
      return nil if encrypted_data.nil?
      
      data = Base64.strict_decode64(encrypted_data)
      iv = data[0..15]
      auth_tag = data[16..31]
      encrypted = data[32..-1]
      
      cipher = OpenSSL::Cipher.new(ENCRYPTION_ALGORITHM)
      cipher.decrypt
      
      key = derive_key_for_context(context)
      cipher.key = key
      cipher.iv = iv
      cipher.auth_tag = auth_tag
      
      cipher.update(encrypted) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      Rails.logger.security "Decryption failed for context: #{context}"
      raise SecurityError, 'Data decryption failed'
    end
    
    private
    
    def derive_key_for_context(context)
      base_key = Rails.application.credentials.master_key
      salt = Rails.application.credentials.encryption_salt
      
      # PBKDF2 key derivation with context
      OpenSSL::PKCS5.pbkdf2_hmac(
        "#{base_key}:#{context}",
        salt,
        10000, # iterations
        32,    # key length
        OpenSSL::Digest::SHA256.new
      )
    end
  end
end

# ActiveRecord encryption concern
module EncryptedAttributes
  extend ActiveSupport::Concern
  
  class_methods do
    def encrypts_attribute(attr_name, context: nil)
      # Define encrypted getter
      define_method(attr_name) do
        encrypted_value = read_attribute("#{attr_name}_encrypted")
        return nil if encrypted_value.nil?
        
        @decrypted_cache ||= {}
        cache_key = "#{attr_name}_#{encrypted_value.hash}"
        
        @decrypted_cache[cache_key] ||= 
          DataEncryptionService.decrypt_sensitive_data(encrypted_value, context: context)
      end
      
      # Define encrypted setter
      define_method("#{attr_name}=") do |value|
        @decrypted_cache = {} # Clear cache
        
        if value.nil?
          write_attribute("#{attr_name}_encrypted", nil)
        else
          encrypted_value = DataEncryptionService.encrypt_sensitive_data(value, context: context)
          write_attribute("#{attr_name}_encrypted", encrypted_value)
        end
        
        value
      end
      
      # Prevent accidental exposure in logs
      self.filter_attributes += ["#{attr_name}_encrypted".to_sym]
    end
  end
end
```

### Data Classification & Access Control
```ruby
# Data classification system
class DataClassificationService
  CLASSIFICATION_LEVELS = {
    public: 0,
    internal: 1,
    confidential: 2,
    restricted: 3,
    pci_data: 4
  }.freeze
  
  def self.classify_user_data(user)
    {
      id: :public,
      email: :confidential,
      name: :internal,
      phone: :confidential,
      address: :confidential,
      
      # Payment data - highest classification
      payment_methods: :pci_data,
      billing_address: :confidential,
      
      # System data
      created_at: :internal,
      updated_at: :internal,
      last_sign_in_at: :confidential,
      last_sign_in_ip: :restricted
    }
  end
  
  def self.can_access_field?(user_permission_level, field_classification)
    permission_level = CLASSIFICATION_LEVELS[user_permission_level] || 0
    required_level = CLASSIFICATION_LEVELS[field_classification] || 0
    
    permission_level >= required_level
  end
end

# Secure API response filtering
class SecureResponseFilter
  def self.filter_response(data, user)
    return data unless data.is_a?(Hash) || data.is_a?(Array)
    
    case data
    when Hash
      filter_hash(data, user)
    when Array
      data.map { |item| filter_response(item, user) }
    else
      data
    end
  end
  
  private
  
  def self.filter_hash(hash, user)
    user_classification = determine_user_classification(user)
    
    hash.each_with_object({}) do |(key, value), filtered|
      field_classification = DataClassificationService.classify_field(key)
      
      if DataClassificationService.can_access_field?(user_classification, field_classification)
        filtered[key] = filter_response(value, user)
      end
    end
  end
  
  def self.determine_user_classification(user)
    return :public unless user
    
    if user.permissions.include?('system.admin')
      :restricted
    elsif user.permissions.include?('pci.access')
      :pci_data
    elsif user.permissions.include?('confidential.read')
      :confidential
    else
      :internal
    end
  end
end
```

## Vulnerability Management

### Security Scanning Integration
```ruby
# Security scanning service
class SecurityScanningService
  include ActiveModel::Model
  
  def self.scan_for_vulnerabilities
    results = {
      code_analysis: run_code_analysis,
      dependency_scan: run_dependency_scan,
      infrastructure_scan: run_infrastructure_scan,
      configuration_audit: run_configuration_audit
    }
    
    # Store results securely
    scan_result = SecurityScan.create!(
      scan_type: 'comprehensive',
      results: results,
      severity_counts: calculate_severity_counts(results),
      created_at: Time.current
    )
    
    # Alert on critical vulnerabilities
    alert_critical_vulnerabilities(scan_result) if has_critical_issues?(results)
    
    scan_result
  end
  
  private
  
  def self.run_code_analysis
    # Static code analysis using Brakeman
    {
      tool: 'brakeman',
      command: 'bundle exec brakeman --format json',
      timestamp: Time.current,
      findings: JSON.parse(`bundle exec brakeman --format json`)
    }
  rescue => e
    Rails.logger.error "Code analysis failed: #{e.message}"
    { error: e.message, timestamp: Time.current }
  end
  
  def self.run_dependency_scan
    # Dependency vulnerability scanning
    backend_audit = `cd $POWERNODE_ROOT/server && bundle audit --format json`
    frontend_audit = `cd $POWERNODE_ROOT/frontend && npm audit --json`
    
    {
      backend: JSON.parse(backend_audit),
      frontend: JSON.parse(frontend_audit),
      timestamp: Time.current
    }
  rescue => e
    Rails.logger.error "Dependency scan failed: #{e.message}"
    { error: e.message, timestamp: Time.current }
  end
  
  def self.run_infrastructure_scan
    # Container and infrastructure scanning
    {
      containers: scan_container_images,
      network: scan_network_policies,
      secrets: scan_secret_management,
      timestamp: Time.current
    }
  end
end

# Vulnerability tracking
class VulnerabilityTracker
  def self.track_vulnerability(vulnerability_data)
    vulnerability = Vulnerability.find_or_initialize_by(
      cve_id: vulnerability_data[:cve_id],
      component: vulnerability_data[:component]
    )
    
    vulnerability.assign_attributes(
      severity: vulnerability_data[:severity],
      description: vulnerability_data[:description],
      affected_versions: vulnerability_data[:affected_versions],
      fix_available: vulnerability_data[:fix_available],
      first_detected: vulnerability.first_detected || Time.current,
      last_detected: Time.current
    )
    
    if vulnerability.save!
      # Create remediation task for critical/high severity
      create_remediation_task(vulnerability) if %w[critical high].include?(vulnerability.severity)
    end
    
    vulnerability
  end
  
  private
  
  def self.create_remediation_task(vulnerability)
    RemediationTask.create!(
      vulnerability: vulnerability,
      priority: map_severity_to_priority(vulnerability.severity),
      assigned_team: determine_responsible_team(vulnerability.component),
      due_date: calculate_remediation_deadline(vulnerability.severity),
      status: 'open'
    )
  end
end
```

### Security Monitoring & Alerting
```ruby
# Real-time security monitoring
class SecurityMonitoringService
  include ActiveModel::Model
  
  SECURITY_EVENTS = {
    suspicious_login: { threshold: 5, window: 15.minutes },
    multiple_failed_payments: { threshold: 3, window: 5.minutes },
    privilege_escalation: { threshold: 1, window: 1.minute },
    data_access_anomaly: { threshold: 10, window: 1.hour },
    api_rate_limit_exceeded: { threshold: 100, window: 1.minute }
  }.freeze
  
  def self.monitor_security_event(event_type, details = {})
    event_config = SECURITY_EVENTS[event_type.to_sym]
    return unless event_config
    
    # Track event occurrence
    event_key = "security_event:#{event_type}:#{details[:identifier]}"
    count = Rails.cache.increment(event_key, 1, expires_in: event_config[:window])
    
    if count >= event_config[:threshold]
      trigger_security_alert(event_type, details.merge(count: count))
    end
    
    # Log all security events
    SecurityEvent.create!(
      event_type: event_type,
      details: details,
      ip_address: details[:ip_address],
      user_id: details[:user_id],
      severity: determine_event_severity(event_type, count),
      created_at: Time.current
    )
  end
  
  private
  
  def self.trigger_security_alert(event_type, details)
    alert = SecurityAlert.create!(
      alert_type: event_type,
      severity: 'high',
      details: details,
      status: 'open',
      created_at: Time.current
    )
    
    # Immediate notification for critical events
    if critical_event?(event_type)
      SecurityAlertService.send_immediate_alert(alert)
    end
    
    # Automated response for certain event types
    case event_type.to_s
    when 'suspicious_login'
      temporarily_block_ip(details[:ip_address])
    when 'privilege_escalation'
      escalate_to_security_team(alert)
    when 'multiple_failed_payments'
      temporarily_disable_payment_processing(details[:user_id])
    end
  end
  
  def self.temporarily_block_ip(ip_address)
    IpBlocklist.create!(
      ip_address: ip_address,
      reason: 'Suspicious activity detected',
      expires_at: 1.hour.from_now,
      created_at: Time.current
    )
  end
end
```

## Container Security

### Secure Container Configuration
```dockerfile
# Security-hardened Rails container
FROM ruby:3.2-alpine AS security-base

# Security updates and minimal packages
RUN apk update && apk upgrade && \
    apk add --no-cache \
    build-base \
    postgresql-dev \
    curl \
    tzdata && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Install gems with security checks
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle audit --update && \
    bundle install

# Copy application with proper ownership
COPY --chown=appuser:appgroup . .

# Security hardening
RUN chmod -R 750 /app && \
    chmod -R 640 /app/config && \
    find /app -name "*.rb" -exec chmod 640 {} \;

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### Container Scanning Pipeline
```yaml
# .github/workflows/container-security.yml
name: Container Security Scan

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  container-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Build Container
      run: |
        docker build -t powernode-api:scan ./server
    
    - name: Run Trivy Vulnerability Scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'powernode-api:scan'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH,MEDIUM'
    
    - name: Upload Trivy Results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
    
    - name: Container Structure Test
      run: |
        curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-linux-amd64
        chmod +x container-structure-test-linux-amd64
        sudo mv container-structure-test-linux-amd64 /usr/local/bin/container-structure-test
        container-structure-test test --image powernode-api:scan --config server/container-structure-test.yml
    
    - name: Security Benchmark
      run: |
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
          aquasec/docker-bench-security
```

### Network Security Policies
```yaml
# k8s/network-security-policy.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: powernode-security-policy
  namespace: powernode
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  
  # Default deny all traffic
  ingress: []
  egress:
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

---
# Allow API access from frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-policy
spec:
  podSelector:
    matchLabels:
      app: powernode-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nginx-ingress
    ports:
    - protocol: TCP
      port: 3000
  - from:
    - podSelector:
        matchLabels:
          app: powernode-frontend
    ports:
    - protocol: TCP
      port: 3000

---
# Database access policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-access-policy
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: powernode-api
    - podSelector:
        matchLabels:
          app: powernode-worker
    ports:
    - protocol: TCP
      port: 5432
```

## Incident Response

### Security Incident Management
```ruby
# Security incident response system
class SecurityIncidentManager
  include ActiveModel::Model
  
  INCIDENT_TYPES = {
    data_breach: { severity: 'critical', response_time: 15.minutes },
    unauthorized_access: { severity: 'high', response_time: 30.minutes },
    malware_detection: { severity: 'high', response_time: 1.hour },
    ddos_attack: { severity: 'medium', response_time: 2.hours },
    suspicious_activity: { severity: 'low', response_time: 4.hours }
  }.freeze
  
  def self.create_incident(incident_type, details = {})
    config = INCIDENT_TYPES[incident_type.to_sym]
    raise ArgumentError, "Unknown incident type: #{incident_type}" unless config
    
    incident = SecurityIncident.create!(
      incident_type: incident_type,
      severity: config[:severity],
      status: 'open',
      details: details,
      reported_at: Time.current,
      response_deadline: Time.current + config[:response_time]
    )
    
    # Immediate containment for critical incidents
    initiate_containment(incident) if config[:severity] == 'critical'
    
    # Notify response team
    SecurityResponseTeam.notify(incident)
    
    # Start incident response workflow
    initiate_response_workflow(incident)
    
    incident
  end
  
  private
  
  def self.initiate_containment(incident)
    case incident.incident_type
    when 'data_breach'
      # Immediate containment measures
      disable_affected_systems(incident.details[:affected_systems])
      isolate_compromised_accounts(incident.details[:affected_users])
      enable_enhanced_monitoring
    when 'unauthorized_access'
      # Access containment
      revoke_suspicious_sessions(incident.details[:session_ids])
      temporarily_elevate_access_controls
    end
  end
  
  def self.initiate_response_workflow(incident)
    # Create response tasks based on incident type
    response_tasks = generate_response_tasks(incident)
    
    response_tasks.each do |task|
      IncidentResponseTask.create!(
        incident: incident,
        task_type: task[:type],
        description: task[:description],
        assignee: task[:assignee],
        priority: task[:priority],
        due_at: Time.current + task[:duration],
        status: 'pending'
      )
    end
  end
end

# Automated incident response
class AutomatedIncidentResponse
  def self.respond_to_incident(incident)
    case incident.incident_type
    when 'ddos_attack'
      enable_rate_limiting
      activate_ddos_protection
      scale_infrastructure
    when 'malware_detection'
      isolate_affected_containers
      run_malware_scan
      update_security_signatures
    when 'suspicious_activity'
      enhance_logging
      increase_monitoring_frequency
      flag_for_manual_review
    end
  end
  
  private
  
  def self.enable_rate_limiting
    # Activate aggressive rate limiting
    Rails.cache.write('security_mode:rate_limit', 'strict', expires_in: 2.hours)
  end
  
  def self.isolate_affected_containers
    # Scale down affected deployments
    affected_deployments = determine_affected_deployments
    affected_deployments.each do |deployment|
      KubernetesService.scale_deployment(deployment, replicas: 0)
    end
  end
end
```

### Compliance Automation

### PCI DSS Compliance Monitoring
```ruby
# Automated PCI compliance checking
class PciComplianceMonitor
  include ActiveModel::Model
  
  COMPLIANCE_CHECKS = {
    'req_1_firewall': {
      description: 'Install and maintain network security controls',
      check_method: :check_firewall_rules,
      frequency: 'daily'
    },
    'req_3_cardholder_data': {
      description: 'Protect stored cardholder data',
      check_method: :check_data_encryption,
      frequency: 'daily'
    },
    'req_4_transmission': {
      description: 'Protect cardholder data during transmission',
      check_method: :check_transmission_security,
      frequency: 'daily'
    },
    'req_8_access_control': {
      description: 'Identify users and authenticate access',
      check_method: :check_access_controls,
      frequency: 'daily'
    },
    'req_10_logging': {
      description: 'Log and monitor all access to system components',
      check_method: :check_audit_logging,
      frequency: 'daily'
    }
  }.freeze
  
  def self.run_compliance_checks
    results = {}
    
    COMPLIANCE_CHECKS.each do |requirement, config|
      begin
        result = send(config[:check_method])
        results[requirement] = {
          status: result[:compliant] ? 'compliant' : 'non_compliant',
          details: result[:details],
          checked_at: Time.current
        }
      rescue => e
        results[requirement] = {
          status: 'error',
          details: { error: e.message },
          checked_at: Time.current
        }
      end
    end
    
    # Store compliance report
    compliance_report = ComplianceReport.create!(
      report_type: 'pci_dss',
      results: results,
      overall_status: determine_overall_status(results),
      created_at: Time.current
    )
    
    # Alert on non-compliance
    alert_compliance_issues(compliance_report) unless compliance_report.overall_status == 'compliant'
    
    compliance_report
  end
  
  private
  
  def self.check_data_encryption
    # Check that cardholder data is properly encrypted
    unencrypted_data = PaymentMethod.where.not(card_number_encrypted: nil)
                                   .where(card_number: nil) # Should be nil if encrypted
    
    {
      compliant: unencrypted_data.count.zero?,
      details: {
        total_payment_methods: PaymentMethod.count,
        unencrypted_count: unencrypted_data.count,
        encryption_algorithm: 'AES-256-GCM'
      }
    }
  end
  
  def self.check_audit_logging
    # Verify audit logging is functioning
    recent_logs = AuditLog.where('created_at > ?', 24.hours.ago)
    payment_logs = recent_logs.where(event_type: 'payment')
    
    {
      compliant: recent_logs.exists? && payment_logs.exists?,
      details: {
        total_logs_24h: recent_logs.count,
        payment_logs_24h: payment_logs.count,
        log_retention_days: 365
      }
    }
  end
  
  def self.check_transmission_security
    # Verify HTTPS enforcement and TLS configuration
    ssl_config = Rails.application.config.force_ssl
    
    {
      compliant: ssl_config == true,
      details: {
        https_enforced: ssl_config,
        tls_version: 'TLS 1.3',
        cipher_suites: 'Strong ciphers only'
      }
    }
  end
end
```

## Development Commands

### Security Testing
```bash
# Static security analysis
cd $POWERNODE_ROOT/server && bundle exec brakeman --format json    # Rails security scan
cd $POWERNODE_ROOT/frontend && npm audit --audit-level high        # Frontend vulnerability scan

# Dependency security checks
bundle audit --update                               # Ruby gem vulnerabilities
npm audit fix                                      # Auto-fix npm vulnerabilities

# Container security scanning
docker run --rm -v $(pwd):/workspace aquasec/trivy fs /workspace
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/docker-bench-security

# Infrastructure security checks
kubectl run kube-score --rm -i --tty --image zegl/kube-score:latest -- score k8s/
```

### Compliance Monitoring
```bash
# PCI compliance checks
rails runner "PciComplianceMonitor.run_compliance_checks"

# Security configuration audit
rails runner "SecurityConfigurationAuditor.audit_all"

# Access control review
rails runner "AccessControlAuditor.review_permissions"

# Encryption verification
rails runner "EncryptionAuditor.verify_data_encryption"
```

### Incident Response Commands
```bash
# Create security incident
rails runner "SecurityIncidentManager.create_incident('data_breach', affected_users: ['user123'])"

# Check active incidents
rails runner "SecurityIncident.where(status: 'open').each { |i| puts i.inspect }"

# Emergency containment
rails runner "EmergencyResponse.initiate_lockdown"

# Security status dashboard
kubectl get networkpolicies
kubectl get secrets
kubectl top pods --sort-by=memory
```

## Integration Points

### Platform Architect Coordination
- **Security Architecture**: Overall security strategy and threat modeling
- **Risk Assessment**: Security risk analysis for architecture decisions
- **Security Standards**: Defining and enforcing security requirements across all components
- **Compliance Strategy**: Coordinating compliance efforts across the platform

### DevOps Engineer Integration
- **Security Infrastructure**: Secure deployment pipelines and infrastructure
- **Container Security**: Secure container configurations and scanning
- **Network Security**: Security policies and network segmentation
- **Monitoring Integration**: Security monitoring in deployment pipelines

### Payment Integration Specialist Coordination
- **PCI Compliance**: Joint responsibility for PCI DSS compliance
- **Payment Security**: Secure payment processing implementations
- **Fraud Prevention**: Security measures for payment fraud detection
- **Audit Trail**: Secure logging of payment-related activities

## Quick Reference

### Security Checklists
```bash
# Pre-deployment security checklist
□ Static code analysis passed
□ Dependency vulnerabilities addressed
□ Container security scan clean
□ Secrets properly managed
□ Network policies configured
□ Monitoring alerts configured
□ Compliance checks passed
□ Incident response plan updated

# Monthly security review
□ Vulnerability scan completed
□ Access controls audited
□ Compliance report generated
□ Security training completed
□ Incident response tested
□ Security metrics reviewed
□ Third-party security assessments
□ Security documentation updated
```

### Emergency Contacts
- **Security Team**: security@powernode.com
- **Incident Response**: incident@powernode.com
- **Compliance Officer**: compliance@powernode.com
- **24/7 Security Hotline**: +1-xxx-xxx-xxxx

### Key Security Metrics
- **Mean Time to Detection (MTTD)**: < 15 minutes for critical incidents
- **Mean Time to Response (MTTR)**: < 30 minutes for high severity
- **Vulnerability Patching**: 95% within SLA (Critical: 24h, High: 7d)
- **Compliance Score**: > 95% across all frameworks
- **Security Training**: 100% completion rate
- **Penetration Testing**: Quarterly external assessments