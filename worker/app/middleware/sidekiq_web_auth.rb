# frozen_string_literal: true

require 'jwt'
require 'cgi'

# Middleware for Sidekiq Web interface authentication
# Authenticates users with email/password and maintains sessions
class SidekiqWebAuth
  def initialize(app)
    @app = app
    @logger = PowernodeWorker.application.logger
    @api_client = WebAuthApiClient.new
  end

  def call(env)
    request = Rack::Request.new(env)
    session = env['rack.session'] || {}

    # Allow health check without auth
    return @app.call(env) if request.path == '/health'
    
    # Allow static assets without auth (CSS, JS, images)
    if static_asset?(request.path)
      return @app.call(env)
    end

    # Handle JWT token from query param (platform SSO)
    if request.params['token'].present?
      return handle_token_login(request, session, env)
    end

    # Handle login form submission (email/password or token field)
    if request.post? && (request.params['email'] || request.params['password'] || request.params['platform_token'])
      if request.params['platform_token'].present?
        return handle_token_login(request, session, env, token: request.params['platform_token'])
      end
      return handle_login(request, session, env)
    end

    # Handle logout
    if request.path == '/sidekiq/logout' || request.params['logout']
      session.clear
      @logger.info "User signed out from worker web interface"
      redirect_url = request.path.gsub('/logout', '').gsub('/sidekiq', '/sidekiq')
      redirect_url = '/sidekiq/' if redirect_url.empty? || redirect_url == '/sidekiq'
      return [302, {'location' => redirect_url}, []]
    end

    # Check if user has valid session
    session_token = session['session_token']
    if session_token && verify_session_with_backend(session_token)
      # User is authenticated, allow access and inject Sign Out button
      status, headers, response = @app.call(env)
      
      # Inject Sign Out button into HTML responses
      if headers['content-type']&.include?('text/html') && request.get?
        response_body = ''
        response.each { |chunk| response_body += chunk }
        
        # Inject Sign Out button near the Live Poll button area
        if response_body.include?('<h3>') && !response_body.include?('powernode-sign-out')
          
          # Look for the Live Poll button or top navigation area to inject Sign Out button
          if response_body.include?('Live Poll') || response_body.include?('poll-wrapper')
            # Inject next to Live Poll button with matching styling
            sign_out_html = <<~HTML
              <span id="powernode-sign-out" style="margin-left: 10px;">
                <a href="/sidekiq/logout" class="btn btn-sm btn-outline-danger" style="font-size: 11px; padding: 4px 8px;">
                  Sign Out
                </a>
              </span>
            HTML
            
            # Try to inject after Live Poll button
            if response_body.sub!(/(<[^>]*poll[^>]*>[^<]*<\/[^>]*>)/i) { |match| "#{match}#{sign_out_html}" }
              # Successfully injected after poll element
            else
              # Fallback: inject near top navigation
              response_body.sub!(/<nav[^>]*>/) { |match| "#{match}#{sign_out_html}" }
            end
          elsif response_body.match?(/<nav[^>]*class[^>]*header[^>]*>/i) || response_body.match?(/<div[^>]*class[^>]*header[^>]*>/i)
            # Inject into header navigation area with consistent styling
            sign_out_html = <<~HTML
              <div id="powernode-sign-out" style="float: right; margin-top: 5px;">
                <a href="/sidekiq/logout" class="btn btn-sm btn-outline-danger" style="font-size: 11px; padding: 4px 8px;">
                  Sign Out
                </a>
              </div>
            HTML
            
            response_body.sub!(/<nav[^>]*class[^>]*header[^>]*>|<div[^>]*class[^>]*header[^>]*>/i) { |match| "#{match}#{sign_out_html}" }
          else
            # Fallback: inject after the main h3 title with Bootstrap-like styling
            sign_out_html = <<~HTML
              <div id="powernode-sign-out" style="position: absolute; top: 20px; right: 20px; z-index: 1000;">
                <a href="/sidekiq/logout" class="btn btn-sm btn-outline-danger" style="font-size: 11px; padding: 4px 8px; background: white; border: 1px solid #dc3545; color: #dc3545; text-decoration: none; border-radius: 4px; font-weight: 400;">
                  Sign Out
                </a>
              </div>
            HTML
            
            response_body.sub!(/<h3[^>]*>/) { |match| "#{match}\n#{sign_out_html}" }
          end
        end
        
        # Return modified response
        headers['content-length'] = response_body.bytesize.to_s
        return [status, headers, [response_body]]
      end
      
      return [status, headers, response]
    end

    # No valid session, show login form
    unauthorized_response
  rescue StandardError => e
    @logger.error "Sidekiq web auth error: #{e.message}"
    @logger.error e.backtrace.join("\n")
    internal_error_response
  end

  private

  # Check if the request is for a static asset (CSS, JS, images)
  def static_asset?(path)
    path.match?(%r{^/sidekiq/(stylesheets|javascripts|images)/})
  end

  def handle_token_login(request, session, env, token: nil)
    token ||= request.params['token']

    begin
      response = @api_client.verify_platform_token(token)

      if response['success'] && response['data'] && response['data']['valid']
        session['session_token'] = response['data']['session_token']
        session['user_email'] = response['data']['user_email']
        session['expires_at'] = response['data']['expires_at']

        @logger.info "User #{response['data']['user_email']} authenticated via platform token"

        # Strip token from URL and redirect to clean path
        clean_path = request.path
        clean_path = '/sidekiq/' if clean_path.empty? || clean_path == '/sidekiq'
        return [302, { 'location' => clean_path }, []]
      else
        return unauthorized_response(response['error'] || 'Token verification failed')
      end
    rescue BackendApiClient::ApiError => e
      @logger.warn "Platform token verification failed: #{e.message}"
      return unauthorized_response('Invalid or expired platform token')
    rescue StandardError => e
      @logger.error "Platform token auth error: #{e.message}"
      return unauthorized_response('Authentication system unavailable')
    end
  end

  def handle_login(request, session, env)
    email = request.params['email']&.strip
    password = request.params['password']

    unless email.present? && password.present?
      return unauthorized_response('Email and password are required')
    end

    begin
      # Authenticate user with backend
      response = @api_client.authenticate_user(email, password)
      
      if response['success'] && response['data'] && response['data']['valid']
        # Store session token
        session['session_token'] = response['data']['session_token']
        session['user_email'] = response['data']['user_email']
        session['expires_at'] = response['data']['expires_at']
        
        @logger.info "User #{email} successfully authenticated for worker web interface"
        
        # Redirect back to the original path
        redirect_url = request.path
        return [302, {'location' => redirect_url}, []]
      else
        return unauthorized_response(response['error'] || 'Authentication failed')
      end
      
    rescue BackendApiClient::ApiError => e
      @logger.warn "User authentication failed: #{e.message}"
      return unauthorized_response('Invalid email or password')
    rescue StandardError => e
      @logger.error "Authentication error: #{e.message}"
      return unauthorized_response('Authentication system unavailable')
    end
  end

  def verify_session_with_backend(session_token)
    return false if session_token.blank?
    
    begin
      response = @api_client.verify_session(session_token)
      response['success'] == true && response['data'] && response['data']['valid'] == true
    rescue BackendApiClient::ApiError => e
      @logger.debug "Session verification failed: #{e.message}"
      false
    rescue StandardError => e
      @logger.error "Session verification error: #{e.message}"
      false
    end
  end

  def unauthorized_response(message = nil)
    [401, 
     { 'content-type' => 'text/html' }, 
     [render_login_page(message)]]
  end

  def internal_error_response
    [500, 
     { 'content-type' => 'text/html' }, 
     ['<h1>Internal Server Error</h1><p>Please try again later.</p>']]
  end

  def render_login_page(error_message = nil)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Powernode Worker - Authentication Required</title>
        <style>
          body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f5f5;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
          }
          .login-container {
            background: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            max-width: 400px;
            width: 100%;
          }
          .logo {
            text-align: center;
            margin-bottom: 2rem;
          }
          .logo h1 {
            color: #2563eb;
            margin: 0;
            font-size: 1.5rem;
          }
          .error {
            background: #fef2f2;
            border: 1px solid #fecaca;
            color: #dc2626;
            padding: 0.75rem;
            border-radius: 4px;
            margin-bottom: 1rem;
            font-size: 0.875rem;
          }
          .form-group {
            margin-bottom: 1rem;
          }
          label {
            display: block;
            margin-bottom: 0.5rem;
            font-weight: 500;
            color: #374151;
          }
          input[type="email"], input[type="password"] {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #d1d5db;
            border-radius: 4px;
            font-size: 1rem;
            box-sizing: border-box;
          }
          input[type="email"]:focus, input[type="password"]:focus {
            outline: none;
            border-color: #2563eb;
            box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
          }
          button {
            width: 100%;
            background: #2563eb;
            color: white;
            border: none;
            padding: 0.75rem;
            border-radius: 4px;
            font-size: 1rem;
            cursor: pointer;
            font-weight: 500;
          }
          button:hover {
            background: #1d4ed8;
          }
          .info {
            margin-top: 1.5rem;
            padding: 1rem;
            background: #f0f9ff;
            border: 1px solid #bae6fd;
            border-radius: 4px;
            font-size: 0.875rem;
            color: #0369a1;
          }
        </style>
      </head>
      <body>
        <div class="login-container">
          <div class="logo">
            <h1>Powernode Worker</h1>
            <p style="margin: 0; color: #6b7280;">Sidekiq Web Interface</p>
          </div>
          
          #{error_message ? "<div class=\"error\">#{error_message}</div>" : ''}
          
          <form action="" method="post" id="token-form">
            <div class="form-group">
              <label for="platform_token">Platform Access Token</label>
              <input type="password" id="platform_token" name="platform_token" required
                     placeholder="Paste your JWT access token" autocomplete="off"
                     style="font-family: monospace; font-size: 0.85rem;">
            </div>

            <button type="submit">Sign In with Token</button>
          </form>

          <div class="divider" style="text-align: center; margin: 1.5rem 0; color: #9ca3af; font-size: 0.875rem;">
            <span style="background: white; padding: 0 1rem;">or sign in with credentials</span>
          </div>

          <form action="" method="post" id="password-form">
            <div class="form-group">
              <label for="email">Email Address</label>
              <input type="email" id="email" name="email" required
                     placeholder="Enter your email address" autocomplete="username">
            </div>

            <div class="form-group">
              <label for="password">Password</label>
              <input type="password" id="password" name="password" required
                     placeholder="Enter your password" autocomplete="current-password">
            </div>

            <button type="submit">Sign In</button>
          </form>

          <div class="info">
            <strong>Platform Authentication</strong><br>
            Paste your platform access token from the browser console:
            <code style="font-size: 0.75rem; background: #e5e7eb; padding: 2px 4px; border-radius: 2px;">localStorage.getItem('access_token')</code>
          </div>
        </div>
        
        <script>
          // Focus on the email input for better UX
          document.addEventListener('DOMContentLoaded', function() {
            document.getElementById('email').focus();
          });
        </script>
      </body>
      </html>
    HTML
  end
end