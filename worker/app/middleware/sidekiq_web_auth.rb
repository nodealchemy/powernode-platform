require 'jwt'

# Middleware for Sidekiq Web interface authentication
# Authenticates requests using service tokens validated against the backend
class SidekiqWebAuth
  def initialize(app)
    @app = app
    @logger = PowernodeWorker.application.logger
    @api_client = BackendApiClient.new
  end

  def call(env)
    request = Rack::Request.new(env)

    # Allow health check without auth
    return @app.call(env) if request.path == '/health'

    # Extract token from Authorization header or session
    token = extract_token(request)

    unless token
      return unauthorized_response('No authentication token provided')
    end

    # Verify token with backend API
    unless verify_token_with_backend(token)
      return unauthorized_response('Invalid or expired token')
    end

    @app.call(env)
  rescue StandardError => e
    @logger.error "Sidekiq web auth error: #{e.message}"
    internal_error_response
  end

  private

  def extract_token(request)
    # Check Authorization header first
    auth_header = request.env['HTTP_AUTHORIZATION']
    if auth_header&.start_with?('Bearer ')
      return auth_header.split(' ', 2).last
    end

    # Check session token
    session_token = request.session['auth_token'] if request.session
    return session_token if session_token

    # Check query parameter (for direct links)
    request.params['token']
  end

  def verify_token_with_backend(token)
    # Create a temporary client with the provided token
    temp_config = Class.new do
      attr_reader :backend_api_url, :service_token, :api_timeout, :max_retry_attempts

      def initialize(url, token)
        @backend_api_url = url
        @service_token = token
        @api_timeout = 10
        @max_retry_attempts = 1
      end
    end

    temp_client = BackendApiClient.new
    # Override the config temporarily
    config = temp_config.new(PowernodeWorker.application.config.backend_api_url, token)
    temp_client.instance_variable_set(:@config, config)

    # Try to verify the token
    response = temp_client.verify_service_token
    response['valid'] == true
  rescue BackendApiClient::ApiError => e
    @logger.warn "Token verification failed: #{e.message}"
    false
  rescue StandardError => e
    @logger.error "Token verification error: #{e.message}"
    false
  end

  def unauthorized_response(message = 'Unauthorized')
    [401, 
     { 'Content-Type' => 'text/html' }, 
     [render_login_page(message)]]
  end

  def internal_error_response
    [500, 
     { 'Content-Type' => 'text/html' }, 
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
          input[type="password"] {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #d1d5db;
            border-radius: 4px;
            font-size: 1rem;
            box-sizing: border-box;
          }
          input[type="password"]:focus {
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
            <h1>🔧 Powernode Worker</h1>
            <p style="margin: 0; color: #6b7280;">Sidekiq Web Interface</p>
          </div>
          
          #{error_message ? "<div class=\"error\">#{error_message}</div>" : ''}
          
          <form action="" method="post">
            <div class="form-group">
              <label for="token">Service Token</label>
              <input type="password" id="token" name="token" required 
                     placeholder="Enter your service authentication token">
            </div>
            
            <button type="submit">Authenticate</button>
          </form>
          
          <div class="info">
            <strong>Authentication Required</strong><br>
            This Sidekiq web interface requires a valid service token. 
            Please contact your administrator for access credentials.
          </div>
        </div>
        
        <script>
          // Handle form submission
          document.querySelector('form').addEventListener('submit', function(e) {
            e.preventDefault();
            const token = document.getElementById('token').value;
            if (token) {
              // Redirect with token parameter
              window.location.href = window.location.pathname + '?token=' + encodeURIComponent(token);
            }
          });
        </script>
      </body>
      </html>
    HTML
  end
end