# Rack-fts Gem Architecture Design

## Overview

Rack-fts is a Ruby gem that implements a Functional Task Supervisor (FTS) pattern for Rack-based applications, with special integration for Ruby on Rails. The gem provides a structured pipeline for request processing through four core stages: Authenticate, Authorize, Action, and Render.

## Core Architecture

### FTS Stage Pipeline

The gem implements a four-stage pipeline based on the functional_task_supervisor pattern using dry-monads Result types for type-safe error handling.

#### Stage 1: Authenticate
The Authenticate stage verifies the identity of the requester. It examines credentials (tokens, sessions, certificates) and returns either:
- **Success(identity)** - Authentication succeeded with identity information
- **Failure(auth_error)** - Authentication failed with error details

#### Stage 2: Authorize
The Authorize stage determines whether the authenticated identity has permission to perform the requested action. It returns:
- **Success(permissions)** - Authorization succeeded with permission context
- **Failure(authz_error)** - Authorization failed with error details

#### Stage 3: Action
The Action stage executes the core business logic of the request. It receives the authenticated identity and authorization context, then returns:
- **Success(result)** - Action executed successfully with result data
- **Failure(action_error)** - Action failed with error details

#### Stage 4: Render
The Render stage transforms the action result into an appropriate HTTP response. It handles:
- **Success cases** - Renders successful responses (JSON, HTML, etc.)
- **Failure cases** - Renders error responses with appropriate status codes

### Monadic Composition

The stages are composed using dry-monads bind operation, creating a "railway" where:
- Success values flow through all stages
- Failure values short-circuit the pipeline and skip to rendering
- Each stage receives the accumulated context from previous stages

```ruby
authenticate(env).bind do |identity|
  authorize(identity, env).bind do |permissions|
    action(identity, permissions, env).bind do |result|
      render(result, env)
    end
  end
end
```

Or using Do notation for cleaner syntax:

```ruby
identity = yield authenticate(env)
permissions = yield authorize(identity, env)
result = yield action(identity, permissions, env)
render(result, env)
```

## Use Cases

### Use Case 1: Standalone FTS Server

A standalone Rack application that runs the FTS pipeline independently. This is useful for microservices or API-only applications.

**Implementation:**
- Rack application class that implements the call(env) interface
- Configurable stage implementations
- Can be run with any Rack-compatible server (Puma, Unicorn, etc.)

**Structure:**
```ruby
# config.ru
require 'rack/fts'

app = Rack::FTS::Application.new do |config|
  config.authenticate_stage = MyAuthenticateStage
  config.authorize_stage = MyAuthorizeStage
  config.action_stage = MyActionStage
  config.render_stage = MyRenderStage
end

run app
```

### Use Case 2: Rails Engine Integration

A Rails engine that can be mounted at a specific path (e.g., /fts) within a Rails application. This allows FTS functionality to coexist with standard Rails routes.

**Implementation:**
- Rails::Engine subclass with isolate_namespace
- Mountable at any path in the host application
- Can access Rails models, helpers, and services
- Maintains separate routing namespace

**Structure:**
```ruby
# In host Rails application config/routes.rb
mount Rack::FTS::Engine => "/fts"

# In engine lib/rack/fts/engine.rb
module Rack
  module FTS
    class Engine < ::Rails::Engine
      isolate_namespace Rack::FTS
      
      config.fts = ActiveSupport::OrderedOptions.new
    end
  end
end
```

### Use Case 3: Rails Rack Middleware

A Rack middleware that wraps the entire Rails application, providing three execution points:

#### PreRails Stage
Executes before the Rails stack, useful for:
- Early authentication/authorization
- Request preprocessing
- Rate limiting
- Request logging

#### Rails Stage
Delegates to the standard Rails application stack

#### PostRails Stage
Executes after Rails processing, useful for:
- Response transformation
- Additional logging
- Metrics collection
- Response caching

**Implementation:**
```ruby
# config/application.rb
module MyApp
  class Application < Rails::Application
    config.middleware.insert_before ActionDispatch::Static, Rack::FTS::Middleware do |config|
      config.pre_rails_stages = [AuthenticationStage, RateLimitStage]
      config.post_rails_stages = [MetricsStage, CachingStage]
    end
  end
end
```

## Component Design

### Base Stage Class

```ruby
module Rack
  module FTS
    class Stage
      include Dry::Monads[:result]
      include Dry::Monads::Do.for(:call)
      
      attr_reader :name
      
      def initialize(name)
        @name = name
        @result = nil
      end
      
      def call(context)
        @result = perform(context)
      rescue StandardError => e
        @result = Failure(
          error: e.message,
          stage: name,
          backtrace: e.backtrace.first(5)
        )
      end
      
      def performed?
        !@result.nil?
      end
      
      def success?
        performed? && @result.success?
      end
      
      def failure?
        performed? && @result.failure?
      end
      
      private
      
      def perform(context)
        raise NotImplementedError, "Subclasses must implement #perform"
      end
    end
  end
end
```

### Task Orchestrator

```ruby
module Rack
  module FTS
    class Task
      include Dry::Monads[:result]
      include Dry::Monads::Do.for(:run)
      
      attr_reader :stages
      
      def initialize
        @stages = []
      end
      
      def add_stage(stage)
        @stages << stage
        self
      end
      
      def run(env)
        context = build_initial_context(env)
        
        stages.each do |stage|
          context = yield stage.call(context)
        end
        
        Success(context)
      end
      
      private
      
      def build_initial_context(env)
        {
          env: env,
          request: Rack::Request.new(env),
          response: Rack::Response.new
        }
      end
    end
  end
end
```

### Rack Application

```ruby
module Rack
  module FTS
    class Application
      def initialize(&block)
        @config = Configuration.new
        block.call(@config) if block_given?
        @task = build_task
      end
      
      def call(env)
        result = @task.run(env)
        
        case result
        when Dry::Monads::Success
          result.value![:response].finish
        when Dry::Monads::Failure
          error_response(result.failure)
        end
      end
      
      private
      
      def build_task
        Task.new.tap do |task|
          task.add_stage(@config.authenticate_stage.new('authenticate'))
          task.add_stage(@config.authorize_stage.new('authorize'))
          task.add_stage(@config.action_stage.new('action'))
          task.add_stage(@config.render_stage.new('render'))
        end
      end
      
      def error_response(error)
        [500, {'Content-Type' => 'application/json'}, [error.to_json]]
      end
    end
  end
end
```

### Rails Middleware

```ruby
module Rack
  module FTS
    class Middleware
      def initialize(app, &block)
        @app = app
        @config = Configuration.new
        block.call(@config) if block_given?
      end
      
      def call(env)
        context = { env: env }
        
        # PreRails stages
        result = run_stages(@config.pre_rails_stages, context)
        return error_response(result.failure) if result.failure?
        
        context = result.value!
        
        # Rails stage
        status, headers, body = @app.call(context[:env])
        context[:status] = status
        context[:headers] = headers
        context[:body] = body
        
        # PostRails stages
        result = run_stages(@config.post_rails_stages, context)
        return error_response(result.failure) if result.failure?
        
        final_context = result.value!
        [final_context[:status], final_context[:headers], final_context[:body]]
      end
      
      private
      
      def run_stages(stage_classes, context)
        include Dry::Monads[:result]
        
        stage_classes.reduce(Success(context)) do |result, stage_class|
          result.bind { |ctx| stage_class.new.call(ctx) }
        end
      end
      
      def error_response(error)
        [500, {'Content-Type' => 'application/json'}, [error.to_json]]
      end
    end
  end
end
```

## Gem Structure

```
rack-fts/
├── lib/
│   ├── rack/
│   │   └── fts/
│   │       ├── application.rb       # Standalone Rack app
│   │       ├── configuration.rb     # Configuration DSL
│   │       ├── engine.rb            # Rails engine
│   │       ├── middleware.rb        # Rails middleware
│   │       ├── stage.rb             # Base stage class
│   │       ├── task.rb              # Task orchestrator
│   │       ├── stages/
│   │       │   ├── authenticate.rb  # Base authenticate stage
│   │       │   ├── authorize.rb     # Base authorize stage
│   │       │   ├── action.rb        # Base action stage
│   │       │   └── render.rb        # Base render stage
│   │       └── version.rb
│   └── rack-fts.rb                  # Main entry point
├── spec/
│   ├── spec_helper.rb
│   ├── rack/
│   │   └── fts/
│   │       ├── application_spec.rb
│   │       ├── middleware_spec.rb
│   │       ├── stage_spec.rb
│   │       └── task_spec.rb
├── features/
│   ├── support/
│   │   └── env.rb
│   ├── standalone_server.feature
│   ├── rails_engine.feature
│   └── rails_middleware.feature
├── examples/
│   ├── standalone/
│   │   └── config.ru
│   ├── rails_engine/
│   │   └── config/routes.rb
│   └── rails_middleware/
│       └── config/application.rb
├── rack-fts.gemspec
├── Gemfile
├── Rakefile
├── README.md
├── LICENSE
└── CHANGELOG.md
```

## Dependencies

- **rack** (~> 3.0) - Core Rack interface
- **dry-monads** (~> 1.6) - Result types and Do notation
- **rails** (~> 8.0) - Optional, for Rails engine and middleware
- **dry-configurable** (~> 1.0) - Configuration management

## Testing Strategy

### RSpec Tests
- Unit tests for Stage, Task, Application, Middleware classes
- Integration tests for stage composition
- Mock Rack environments for testing

### Cucumber Tests
- Feature tests for standalone server use case
- Feature tests for Rails engine integration
- Feature tests for Rails middleware integration
- End-to-end request/response scenarios

## Configuration API

```ruby
Rack::FTS.configure do |config|
  # Stage implementations
  config.authenticate_stage = CustomAuthenticateStage
  config.authorize_stage = CustomAuthorizeStage
  config.action_stage = CustomActionStage
  config.render_stage = CustomRenderStage
  
  # Error handling
  config.error_handler = CustomErrorHandler
  
  # Logging
  config.logger = Logger.new(STDOUT)
  
  # Middleware-specific
  config.pre_rails_stages = [Stage1, Stage2]
  config.post_rails_stages = [Stage3, Stage4]
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

The Render stage (or middleware error handler) transforms these into appropriate HTTP responses with proper status codes and error messages.

## Extension Points

1. **Custom Stages** - Subclass Stage and implement perform method
2. **Custom Error Handlers** - Implement error_handler interface
3. **Custom Renderers** - Implement renderer interface for different formats
4. **Hooks** - before_stage, after_stage, on_failure callbacks
5. **Dependency Injection** - Use dry-effects for injecting services

## Performance Considerations

- Stages are executed synchronously in order
- Short-circuiting on failure prevents unnecessary computation
- Context is passed by reference to avoid copying
- Minimal overhead from monadic composition
- No global state, thread-safe by design

## Security Considerations

- Authentication stage validates all credentials
- Authorization stage enforces permissions
- Failures contain only necessary error information (no sensitive data)
- Configurable error message sanitization
- Support for rate limiting in PreRails stages
- CSRF protection can be implemented in Authenticate stage

