# Rack-fts

A Ruby gem that implements a Functional Task Supervisor (FTS) pattern for Rack-based applications with special integration for Ruby on Rails. The gem provides a structured pipeline for request processing through four core stages: **Authenticate**, **Authorize**, **Action**, and **Render**.

## Features

- **Type-safe error handling** with dry-monads Result types (Success/Failure)
- **Multi-stage request pipeline** with explicit stage states
- **Railway Oriented Programming** for clean error propagation
- **Four deployment modes**: Standalone server, Rails engine, Rails middleware, Rails fallback router
- **Customizable stages** for authentication, authorization, action, and rendering
- **Comprehensive testing** with RSpec and Cucumber

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack-fts'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install rack-fts
```

## Core Concepts

### FTS Pipeline

The FTS pipeline consists of four stages that execute sequentially:

1. **Authenticate** - Verifies the identity of the requester
2. **Authorize** - Determines if the authenticated identity has permission
3. **Action** - Executes the core business logic
4. **Render** - Transforms the result into an HTTP response

Each stage returns either `Success(data)` or `Failure(error)`. When a stage returns Failure, the pipeline short-circuits and skips remaining stages, proceeding directly to error rendering.

### Monadic Composition

Stages are composed using dry-monads Result types, creating a "railway" where:
- Success values flow through all stages
- Failure values short-circuit the pipeline
- Error information is preserved throughout

## Use Cases

### Use Case 1: Standalone FTS Server

Run Rack-fts as a standalone Rack application for microservices or API-only applications.

**config.ru:**
```ruby
require 'rack-fts'

class CustomAuthenticate < Rack::FTS::Stages::Authenticate
  private
  
  def verify_credentials(identity)
    # Your authentication logic here
    token = identity[:token]
    return nil unless valid_token?(token)
    
    { user_id: extract_user_id(token), authenticated_at: Time.now }
  end
end

class CustomAction < Rack::FTS::Stages::Action
  private
  
  def execute_action(request, identity, permissions)
    # Your business logic here
    case request.path
    when "/api/users"
      { users: User.all }
    when "/api/posts"
      { posts: Post.all }
    else
      { error: "Not found" }
    end
  end
end

app = Rack::FTS::Application.new do |config|
  config.authenticate_stage = CustomAuthenticate
  config.action_stage = CustomAction
end

run app
```

**Run the server:**
```bash
rackup config.ru
```

**Make requests:**
```bash
# Successful request
curl -H "Authorization: Bearer your_token" http://localhost:9292/api/users

# Unauthorized request
curl http://localhost:9292/api/users
```

### Use Case 2: Rails Engine Integration

Mount Rack-fts as a Rails engine at a specific path (e.g., `/fts`).

**lib/rack/fts/engine.rb:**
```ruby
module Rack
  module FTS
    class Engine < ::Rails::Engine
      isolate_namespace Rack::FTS
      
      config.fts = ActiveSupport::OrderedOptions.new
      
      initializer "rack_fts.configure" do |app|
        # Configuration goes here
      end
    end
  end
end
```

**config/routes.rb:**
```ruby
Rails.application.routes.draw do
  mount Rack::FTS::Engine => "/fts"
  
  # Your other routes
  resources :articles
end
```

### Use Case 3: Rails Rack Middleware

Use Rack-fts as middleware that wraps your Rails application with PreRails and PostRails stages.

**config/application.rb:**
```ruby
module MyApp
  class Application < Rails::Application
    # PreRails stages execute before Rails
    class RateLimitStage < Rack::FTS::Stage
      protected
      def perform(context)
        # Rate limiting logic
        if rate_limit_exceeded?(context[:request])
          Failure(error: "Rate limit exceeded", stage: name, status: 429)
        else
          Success(context)
        end
      end
    end
    
    # PostRails stages execute after Rails
    class MetricsStage < Rack::FTS::Stage
      protected
      def perform(context)
        # Metrics collection logic
        record_metrics(context)
        Success(context)
      end
    end
    
    # Insert middleware
    config.middleware.insert_before ActionDispatch::Static, Rack::FTS::Middleware do |config|
      config.pre_rails_stages = [RateLimitStage]
      config.post_rails_stages = [MetricsStage]
    end
  end
end
```

### Use Case 4: Rails Fallback Router

Use Rack-fts as a fallback router that catches routes Rails doesn't recognize and delegates to custom FTS route handlers. This enables a plugin architecture for handling dynamic or legacy routes.

**How it works:**
1. Request comes in to Rails
2. Rails attempts to route the request
3. If Rails throws `ActionController::RoutingError`, the FTS Router catches it
4. FTS Router iterates through registered handlers to find a match
5. First matching handler processes the request (via FTS pipeline or Rails delegation)

#### Creating Route Handlers

**FTS Pipeline Mode** - Full authenticate → authorize → action → render pipeline:

```ruby
# app/fts_routes/api_docs_route.rb
class ApiDocsRoute < Rack::FTS::RouteBase
  route_pattern %r{^/api/docs(/.*)?$}
  http_methods :get

  class DocsAction < Rack::FTS::Stages::Action
    protected

    def execute_action(request, identity, permissions)
      { docs: load_api_documentation, version: "1.0" }
    end
  end

  protected

  def action_stage_class
    DocsAction
  end
end
```

**Rails Delegation Mode** - Delegate to existing Rails controllers:

```ruby
# app/fts_routes/legacy_api_route.rb
class LegacyApiRoute < Rack::FTS::RouteBase
  route_pattern %r{^/v1/legacy(/.*)?$}
  http_methods :get, :post

  # Delegate to existing Rails controller
  delegate_to "LegacyApi", action: :handle
end
```

**Public Routes (Skip Authentication)** - Use NoOp stage for public endpoints:

```ruby
# app/fts_routes/health_check_route.rb
class HealthCheckRoute < Rack::FTS::RouteBase
  route_pattern "/health"
  http_methods :get

  class HealthAction < Rack::FTS::Stages::Action
    protected

    def execute_action(request, identity, permissions)
      { status: "healthy", timestamp: Time.now.iso8601 }
    end
  end

  protected

  # Skip authentication for health checks
  def authenticate_stage_class
    Rack::FTS::Stages::NoOp
  end

  def authorize_stage_class
    Rack::FTS::Stages::NoOp
  end

  def action_stage_class
    HealthAction
  end
end
```

#### Configuration

**config/initializers/rack_fts.rb:**
```ruby
require 'rack-fts'

Rack::FTS.configure do |config|
  config.route_handlers = [
    HealthCheckRoute,     # First priority (specific routes first)
    ApiDocsRoute,
    LegacyApiRoute,       # Last priority (catch-all patterns go last)
  ]
end
```

**config/application.rb:**
```ruby
module MyApp
  class Application < Rails::Application
    # Insert FTS Router to catch routing errors
    config.middleware.insert_before ActionDispatch::ShowExceptions,
                                    Rack::FTS::Router
  end
end
```

#### RouteBase DSL

| Method | Description | Example |
|--------|-------------|---------|
| `route_pattern` | String or Regexp to match request path | `route_pattern %r{^/api/.*$}` |
| `http_methods` | Allowed HTTP methods (symbols) | `http_methods :get, :post` |
| `delegate_to` | Delegate to Rails controller | `delegate_to "MyController", action: :index` |

#### Built-in Route Handler

Rack-fts includes a health check route handler out of the box:

```ruby
# Add to your route_handlers
config.route_handlers = [
  Rack::FTS::Routes::HealthCheck,  # Responds to GET /health
  # ... your other handlers
]
```

### Use Case 5: Rails Fallback Router Engine with Discoverable, Versionable, Nestable Plugins

Extends Use Case 4 with automatic plugin discovery, version compatibility checking, nested plugin support, and environment-based configuration.

#### Key Features

- **Auto-Discovery**: Scans directories for `*_plugin.rb` files
- **Version Compatibility**: Plugins declare required rack-fts version
- **Nested Plugins**: Mount child plugins at relative paths with stage wrappers
- **ENV Configuration**: Each plugin has dedicated `RACK_FTS_{NAME}_{SETTING}` variables

#### Rails Engine Integration

The engine automatically discovers and registers plugins during Rails initialization:

```ruby
# config/initializers/rack_fts.rb
Rack::FTS.configure do |config|
  config.plugin_directories = [
    Rails.root.join("app/fts_plugins"),
    Rails.root.join("lib/fts_plugins")
  ]
  config.auto_discover = true
  config.version_check_mode = :warn  # :strict, :warn, :ignore
end
```

#### Creating Plugins

**Directory Structure:**
```
app/
└── fts_plugins/
    ├── health_plugin.rb
    ├── api_docs_plugin.rb
    └── metrics_plugin.rb
```

**Plugin DSL:**

```ruby
# app/fts_plugins/metrics_plugin.rb
class MetricsPlugin < Rack::FTS::RouteBase
  # Plugin metadata
  plugin_name :metrics
  plugin_version "1.2.0"
  requires_rack_fts "~> 0.2.0"
  priority 100  # Higher = checked first

  # Route matching
  route_pattern %r{^/metrics(/.*)?$}
  http_methods :get

  # Mount sub-plugins at relative paths
  mount PrometheusPlugin, at: "/prometheus"
  mount HealthPlugin, at: "/health"

  # Wrap child plugin stages with before/after hooks
  wrap_with stage: :authenticate, position: :before do |context|
    context[:metrics_start] = Time.now
    Success(context)
  end

  wrap_with stage: :render, position: :after do |context|
    MetricsCollector.record(context[:metrics_start], Time.now)
    Success(context)
  end

  class MetricsAction < Rack::FTS::Stages::Action
    protected

    def execute_action(request, identity, permissions)
      format = env.get(:format, default: "json")
      { metrics: collect_metrics, format: format }
    end
  end

  protected

  def authenticate_stage_class
    Rack::FTS::Stages::NoOp
  end

  def authorize_stage_class
    Rack::FTS::Stages::NoOp
  end

  def action_stage_class
    MetricsAction
  end
end
```

#### Plugin DSL Reference

| Method | Description | Example |
|--------|-------------|---------|
| `plugin_name` | Unique plugin identifier | `plugin_name :health_check` |
| `plugin_version` | Plugin semantic version | `plugin_version "1.2.0"` |
| `requires_rack_fts` | Version requirement | `requires_rack_fts "~> 0.2.0"` |
| `priority` | Discovery/matching priority | `priority 100` |
| `mount` | Mount child plugin at path | `mount ChildPlugin, at: "/sub"` |
| `wrap_with` | Wrap child stages | `wrap_with stage: :auth, position: :before` |
| `env` | Access plugin ENV config | `env.get(:timeout, default: "30")` |

#### Environment Variables

Each plugin has a dedicated ENV namespace:

```bash
RACK_FTS_{PLUGIN_NAME}_{SETTING}

# Examples
RACK_FTS_HEALTH_ENABLED=true
RACK_FTS_HEALTH_DETAILED=false
RACK_FTS_METRICS_FORMAT=prometheus
RACK_FTS_METRICS_INTERVAL=60
RACK_FTS_API_DOCS_VERSION=v2
```

**Reserved Variables:**

| Variable | Description | Default |
|----------|-------------|---------|
| `RACK_FTS_{NAME}_ENABLED` | Enable/disable plugin | `true` |

**Using ENV in Plugins:**

```ruby
class MyPlugin < Rack::FTS::RouteBase
  plugin_name :my_plugin

  def some_method
    # Basic string access
    timeout = env.get(:timeout, default: "30")

    # Typed accessors
    port = env.get_int(:port, default: 3000)
    debug = env.get_bool(:debug, default: false)

    # Check if enabled
    return unless env.enabled?

    # Get all plugin ENV vars as hash
    all_settings = env.to_h
  end
end
```

#### Nested Plugin Routing

Child plugins are mounted at relative paths:

```ruby
# Parent matches /api/*
class ApiPlugin < Rack::FTS::RouteBase
  route_pattern %r{^/api(/.*)?$}

  mount ApiV1Plugin, at: "/v1"  # Handles /api/v1/*
  mount ApiV2Plugin, at: "/v2"  # Handles /api/v2/*
end

# Child sees path with prefix stripped
class ApiV1Plugin < Rack::FTS::RouteBase
  route_pattern %r{^/users.*$}  # Matches /api/v1/users (sees /users)
end
```

**Request Flow:**
```
GET /api/v1/users
  ↓
1. Router finds ApiPlugin matches /api/*
2. ApiPlugin.mounted_plugins finds ApiV1Plugin at /v1
3. Path stripped: /api/v1/users → /users
4. Parent's before wrappers execute
5. Child's pipeline executes
6. Parent's after wrappers execute
7. Response returned
```

#### Stage Wrappers

Parent plugins can wrap child plugin stages:

```ruby
class SecureApiPlugin < Rack::FTS::RouteBase
  route_pattern %r{^/secure}

  # Run before child's authenticate stage
  wrap_with stage: :authenticate, position: :before do |context|
    if rate_limited?(context[:request])
      Failure(error: "Rate limited", status: 429)
    else
      Success(context)
    end
  end

  # Run after child's action stage
  wrap_with stage: :action, position: :after do |context|
    AuditLog.record(context)
    Success(context)
  end

  mount PublicApiPlugin, at: "/public"
  mount AdminApiPlugin, at: "/admin"
end
```

#### Version Checking

Plugins can declare compatibility requirements:

```ruby
class MyPlugin < Rack::FTS::RouteBase
  requires_rack_fts "~> 0.2.0"  # Allows 0.2.x
  # or
  requires_rack_fts ">= 0.2.0, < 1.0"  # Range
end
```

**Check Modes:**

| Mode | Behavior |
|------|----------|
| `:strict` | Raises error, prevents boot |
| `:warn` | Logs warning, continues |
| `:ignore` | No checking |

#### Plugin Registry

Access registered plugins programmatically:

```ruby
registry = Rack::FTS::PluginRegistry.instance

registry.all                   # All plugins
registry.enabled_plugins       # Only enabled
registry.by_priority           # Sorted by priority
registry.find(:my_plugin)      # Find by name
registry.registered?(:health)  # Check if exists
```

## Custom Stages

### Creating Custom Stages

Subclass `Rack::FTS::Stage` and implement the `perform` method:

```ruby
class MyCustomStage < Rack::FTS::Stage
  protected
  
  def perform(context)
    # Your logic here
    if everything_ok?
      Success(context.merge(custom_data: "value"))
    else
      Failure(error: "Something went wrong", stage: name)
    end
  end
end
```

### Authenticate Stage Example

```ruby
class JWTAuthenticate < Rack::FTS::Stages::Authenticate
  private
  
  def verify_credentials(identity)
    token = identity[:token]
    
    begin
      payload = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256')
      {
        user_id: payload[0]['user_id'],
        email: payload[0]['email'],
        authenticated_at: Time.now
      }
    rescue JWT::DecodeError
      nil
    end
  end
end
```

### Authorize Stage Example

```ruby
class RBACAuthorize < Rack::FTS::Stages::Authorize
  private
  
  def check_permissions(identity, resource, action)
    user = User.find(identity[:user_id])
    
    if user.can?(action, resource)
      {
        allowed: true,
        identity: identity,
        resource: resource,
        action: action,
        role: user.role,
        authorized_at: Time.now
      }
    else
      nil
    end
  end
end
```

### Action Stage Example

```ruby
class RESTfulAction < Rack::FTS::Stages::Action
  private
  
  def execute_action(request, identity, permissions)
    controller = route_to_controller(request.path)
    action_name = map_method_to_action(request.request_method)
    
    controller.new.send(action_name, request, identity, permissions)
  end
  
  def route_to_controller(path)
    # Your routing logic
    case path
    when %r{^/api/users}
      UsersController
    when %r{^/api/posts}
      PostsController
    else
      NotFoundController
    end
  end
end
```

### Render Stage Example

```ruby
class JSONAPIRender < Rack::FTS::Stages::Render
  private
  
  def render_response(response, action_result, context)
    response.status = 200
    response["Content-Type"] = "application/vnd.api+json"
    response.write(format_jsonapi(action_result))
  end
  
  def format_jsonapi(data)
    {
      data: {
        type: data[:type],
        id: data[:id],
        attributes: data[:attributes]
      },
      jsonapi: { version: "1.0" }
    }.to_json
  end
end
```

## Configuration

### Global Configuration

```ruby
Rack::FTS.configure do |config|
  # Stage classes for the FTS pipeline
  config.authenticate_stage = CustomAuthenticateStage
  config.authorize_stage = CustomAuthorizeStage
  config.action_stage = CustomActionStage
  config.render_stage = CustomRenderStage

  # Route handlers for fallback router (Use Case 4)
  config.route_handlers = [HealthCheckRoute, ApiDocsRoute]

  config.logger = Logger.new(STDOUT)
end
```

### Per-Application Configuration

```ruby
app = Rack::FTS::Application.new do |config|
  config.authenticate_stage = CustomAuthenticateStage
  config.action_stage = CustomActionStage
end
```

### Middleware Configuration

```ruby
use Rack::FTS::Middleware do |config|
  config.pre_rails_stages = [AuthenticationStage, RateLimitStage]
  config.post_rails_stages = [MetricsStage, CachingStage]
end
```

## Error Handling

All errors are wrapped in Failure monads with structured information:

```ruby
Failure(
  error: "Authentication failed",
  stage: "authenticate",
  code: :invalid_credentials,
  details: { username: "user@example.com" }
)
```

HTTP status codes are automatically determined based on the stage:
- **Authenticate failures** → 401 Unauthorized
- **Authorize failures** → 403 Forbidden
- **Action failures** → 500 Internal Server Error (or custom status)

## Testing

### RSpec

```ruby
require 'spec_helper'

RSpec.describe MyCustomStage do
  let(:stage) { described_class.new('test_stage') }
  let(:context) { { request: mock_request } }

  it 'executes successfully' do
    result = stage.call(context)
    expect(result).to be_success
  end

  it 'returns expected data' do
    result = stage.call(context)
    expect(result.value!).to include(data: 'expected')
  end
end
```

### Cucumber

```gherkin
Feature: FTS Pipeline
  Scenario: Successful request
    Given I have a valid authentication token
    When I make a GET request to "/api/resource"
    Then the response status should be 200
    And the response should contain the resource data
```

Run tests:
```bash
bundle exec rspec
bundle exec cucumber
```

## Architecture

### Class Diagram

The gem consists of the following main components:

- **Stage** - Base class for all FTS stages
- **Task** - Orchestrates execution of multiple stages
- **Application** - Standalone Rack application
- **Middleware** - Rails middleware wrapper
- **Router** - Fallback router middleware for catching Rails routing errors
- **RouteBase** - Base class for custom route handlers (supports FTS pipeline and Rails delegation)
- **Configuration** - Configuration management

See `rack_fts_class_diagram.png` for the complete class diagram.

### Sequence Diagram

The request flow through the FTS pipeline:

1. Client sends HTTP request
2. Rack server calls Application
3. Application creates Task and runs stages
4. Each stage executes in sequence
5. Success flows through all stages
6. Failure short-circuits to error response
7. Response is returned to client

See `rack_fts_sequence_diagram.png` for the complete sequence diagram.

## Dependencies

- **rack** (~> 3.0) - Core Rack interface
- **dry-monads** (~> 1.6) - Result types and Do notation
- **dry-configurable** (~> 1.0) - Configuration management

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

```bash
# Install dependencies
bundle install

# Run RSpec tests
bundle exec rspec

# Run Cucumber features
bundle exec cucumber

# Run all tests
bundle exec rake

# Run example server
rackup examples/standalone/config.ru
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/example/rack-fts.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Credits

Built with:
- [dry-monads](https://dry-rb.org/gems/dry-monads) - Common monads for Ruby
- [functional_task_supervisor](https://github.com/activedataflow/functional_task_supervisor) - Inspiration for the stage pattern
- [rack](https://github.com/rack/rack) - Ruby web server interface

## Support

For questions, issues, or feature requests, please open an issue on GitHub.
