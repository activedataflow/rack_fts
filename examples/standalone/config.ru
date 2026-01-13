# frozen_string_literal: true

require_relative "../../lib/rack-fts"

# Example: Standalone FTS Server
# Run with: rackup examples/standalone/config.ru

# Optional: Custom Authentication Stage
class CustomAuthenticate < Rack::FTS::Stages::Authenticate
  private
  
  def verify_credentials(identity)
    # Example: Verify against a database or external service
    token = identity[:token]
    
    if token == "secret_token"
      identity.merge(
        user_id: "user_123",
        username: "john_doe",
        authenticated_at: Time.now
      )
    else
      nil
    end
  end
end

# Optional: Custom Authorization Stage
class CustomAuthorize < Rack::FTS::Stages::Authorize
  private
  
  def check_permissions(identity, resource, action)
    # Example: Check permissions based on user role
    user_id = identity[:user_id]
    
    # Allow all GET requests, restrict POST/PUT/DELETE
    if action == "get"
      {
        allowed: true,
        identity: identity,
        resource: resource,
        action: action,
        authorized_at: Time.now
      }
    elsif user_id == "user_123"
      {
        allowed: true,
        identity: identity,
        resource: resource,
        action: action,
        authorized_at: Time.now
      }
    else
      nil
    end
  end
end

# Optional: Custom Action Stage
class CustomAction < Rack::FTS::Stages::Action
  private
  
  def execute_action(request, identity, permissions)
    # Example: Route to different handlers based on path
    case request.path
    when "/api/users"
      handle_users(request, identity)
    when "/api/posts"
      handle_posts(request, identity)
    else
      {
        status: :not_found,
        message: "Resource not found",
        path: request.path
      }
    end
  end
  
  def handle_users(request, identity)
    {
      status: :success,
      resource: "users",
      data: [
        { id: 1, name: "John Doe" },
        { id: 2, name: "Jane Smith" }
      ],
      requested_by: identity[:username]
    }
  end
  
  def handle_posts(request, identity)
    {
      status: :success,
      resource: "posts",
      data: [
        { id: 1, title: "First Post", author: "John Doe" },
        { id: 2, title: "Second Post", author: "Jane Smith" }
      ],
      requested_by: identity[:username]
    }
  end
end

# Configure and create the application
app = Rack::FTS::Application.new do |config|
  config.authenticate_stage = CustomAuthenticate
  config.authorize_stage = CustomAuthorize
  config.action_stage = CustomAction
  # config.render_stage = CustomRender  # Optional
end

run app

# Usage examples:
# 
# 1. Successful request:
#    curl -H "Authorization: Bearer secret_token" http://localhost:9292/api/users
#
# 2. Unauthorized request:
#    curl http://localhost:9292/api/users
#
# 3. Invalid token:
#    curl -H "Authorization: Bearer invalid_token" http://localhost:9292/api/users
#
# 4. POST request:
#    curl -X POST -H "Authorization: Bearer secret_token" \
#         -H "Content-Type: application/json" \
#         -d '{"title":"New Post"}' \
#         http://localhost:9292/api/posts
