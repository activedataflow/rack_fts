# Research Notes: Rack-fts Gem Development

## Ruby on Rails Overview

### Key Characteristics
- **Full-stack framework** for web applications
- Ships with tools for front-end and back-end development
- Built on top of **Rack** (the Ruby web server interface)
- Current version: Rails 8.1.1 (released October 28, 2025)

### Core Components
1. **Active Record** - Database modeling with ORM
2. **Action Controller** - Request handling and processing
3. **Action View** - Template rendering (HTML/JSON)
4. **Action Dispatch** - URL routing

### Architecture Patterns
- MVC (Model-View-Controller) pattern
- Convention over Configuration
- RESTful resource routing
- Middleware stack architecture

### Relevant Features for Rack-fts
- **Rack Middleware**: Rails is built on Rack, allowing middleware integration
- **Rails Engines**: Mountable applications that can be integrated into Rails apps
- **Routing DSL**: Flexible routing configuration

### Next Steps
- Need to understand Rack middleware architecture in detail
- Review Rails guides on middleware and engines
- Examine functional_task_supervisor repository
- Study dry-monad for functional programming patterns


## Rails on Rack - Middleware Architecture

### Rack Integration
Rails applications are fundamentally Rack applications. The **Rails.application** object is the primary Rack application object that any Rack-compliant web server uses to serve a Rails application. This makes Rails fully compatible with the Rack ecosystem and allows seamless integration of Rack middleware.

### Middleware Stack
Rails uses **ActionDispatch::MiddlewareStack** to manage its middleware stack, which is equivalent to Rack::Builder but provides better flexibility for Rails requirements. The middleware stack processes requests in order from top to bottom, with each middleware having the opportunity to modify the request, response, or pass control to the next middleware in the chain.

### Standard Middleware Components
A typical Rails application includes numerous built-in middlewares such as ActionDispatch::HostAuthorization, Rack::Sendfile, ActionDispatch::Static, ActionDispatch::Executor, and many others. The final component in the stack is typically the application routes (run MyApp::Application.routes).

### Middleware Configuration
Rails provides a configuration interface through **config.middleware** that allows developers to manipulate the middleware stack in application.rb or environment-specific configuration files. Key operations include:

- **config.middleware.use** - Adds middleware at the bottom of the stack
- **config.middleware.insert_before** - Inserts middleware before a specific existing middleware
- **config.middleware.insert_after** - Inserts middleware after a specific existing middleware
- **config.middleware.swap** - Replaces one middleware with another
- **config.middleware.delete** - Removes middleware from the stack

### Inspection
The command **bin/rails middleware** displays the complete middleware stack in order, making it easy to understand the request processing pipeline.


## Rails Engines

### What are Engines?
Rails engines are miniature applications that provide functionality to their host applications. A Rails application itself is essentially a "supercharged" engine, with Rails::Application inheriting much of its behavior from Rails::Engine. This means engines and applications share a common structure and can be thought of as almost the same thing with subtle differences.

### Types of Engines
Engines can be generated with different options:

- **--full**: Creates a basic engine with app directory structure, routes, and engine configuration
- **--mountable**: Includes everything from --full plus namespace isolation, asset manifests, namespaced controllers/helpers, and layout templates

### Namespace Isolation
Mountable engines use **isolate_namespace** to prevent naming conflicts with the host application. This means an engine can have its own articles_path helper that won't clash with the host application's articles_path. Controllers, models, and table names are also namespaced.

### Mounting Engines
Engines are mounted in the host application's routes file using the **mount** directive:

```ruby
mount Blorgh::Engine => "/blorgh"
```

This makes the engine accessible at the /blorgh path in the host application.

### Integration as Gems
Engines are typically distributed as gems and included in the host application's Gemfile. The engine has its own gemspec file and can be loaded like any other gem dependency.

### Key Principle
The host application always takes precedence over its engines. Engines should enhance the application rather than drastically changing it. Applications can override engine functionality as needed.

### Examples
Popular Rails engines include Devise (authentication), Thredded (forums), Spree (e-commerce), and Refinery CMS (content management).


## Functional Task Supervisor

### Overview
FunctionalTaskSupervisor is a Ruby gem that implements multi-stage task lifecycle using **dry-monads** Result types and **dry-effects** for composable, testable task execution. This provides a foundation for understanding how to structure the Rack-fts gem with similar patterns.

### Core Architecture

#### Stage Concept
A Stage represents a single unit of work that returns a Result (Success or Failure). Each stage has three possible states:

- **nil** - Stage has not been run yet
- **Success(data)** - Stage ran successfully with data
- **Failure(error)** - Stage failed with error information

Stages are created by subclassing the base Stage class and implementing the **perform_work** method, which must return either Success or Failure.

#### Task Orchestration
A Task orchestrates the execution of multiple stages in sequence. It manages stage execution order, collects results, and provides methods to check overall task status (all_successful?, any_failed?, etc.).

#### Execution Flow
Tasks execute stages sequentially by default, but can implement custom logic through the **determine_next_stage** method for conditional execution paths. This allows for branching logic based on stage results.

### Key Features

#### Type-Safe Error Handling
Uses dry-monads Result types (Success/Failure) for explicit error handling without exceptions. All errors are wrapped in Failure objects with structured error information.

#### Composable Effects
Leverages dry-effects for:

- **State tracking** - Recording execution history and metadata
- **Dependency injection** - Providing services (logger, repository, config) to stages
- **Combined effects** - Using multiple effect handlers together

#### Preconditions
Stages can implement **preconditions_met?** to validate whether they should execute based on current state or context.

#### Transaction Safety
Tasks can be wrapped in database transactions with automatic rollback on failure.

### Relevance to Rack-fts

The functional_task_supervisor pattern maps well to the Rack-fts requirements:

1. **FTS Stages** (Authenticate, Authorize, Action, Render) can be implemented as Stage subclasses
2. **Task orchestration** handles the sequential execution of FTS stages
3. **Result types** provide clean success/failure handling for each stage
4. **Conditional execution** allows branching based on authentication/authorization results
5. **Dependency injection** enables providing request/response context to stages

The pattern of Stage → Task → Result provides a clean functional architecture for implementing the FTS pipeline in a Rack middleware context.


## dry-monads

### Overview
dry-monads is a Ruby gem that provides common monads for elegant error handling, exception management, and function chaining. It eliminates the need for extensive if/else statements and provides type-safe error handling without exceptions.

### Core Monads

#### Result Monad
The Result monad is the most relevant for Rack-fts implementation. It has two type constructors:

- **Success(value)** - Represents successful computation with a value
- **Failure(error)** - Represents failed computation with error information

The Result monad is particularly useful for expressing a series of computations that might fail at any step, which maps perfectly to the FTS stage pipeline (Authenticate → Authorize → Action → Render).

### Key Operations

#### bind
The **bind** operation is used for composing several possibly-failing operations. When called on a Success, it executes the block with the unwrapped value. When called on a Failure, it short-circuits and returns the Failure without executing the block. This creates a "railway" where failures automatically skip subsequent operations.

```ruby
find_user(user_id).bind do |user|
  find_address(address_id).fmap do |address|
    user.update(address_id: address.id)
  end
end
```

#### fmap
The **fmap** operation transforms the value inside a Success while leaving Failure intact. It's used when the transformation cannot fail.

```ruby
Success(10).fmap { |x| x * 2 } # => Success(20)
Failure("error").fmap { |x| x * 2 } # => Failure("error")
```

#### value_or
The **value_or** method provides a safe way to extract values with a default for the Failure case.

```ruby
Success(10).value_or(0) # => 10
Failure('Error').value_or(0) # => 0
```

#### either
The **either** method maps a Result to some type by taking two callables for Success and Failure cases respectively, allowing you to handle both branches explicitly.

### Do Notation
dry-monads supports **Do notation** which simplifies monadic composition to look almost like regular Ruby code while maintaining type safety:

```ruby
user = yield find_user(params[:user_id])
address = yield find_address(params[:address_id])

Success(user.update(address_id: address.id))
```

The yield keyword automatically unwraps Success values and short-circuits on Failure, making the code readable while preserving the error-handling benefits.

### Railway Oriented Programming
The Result monad enables "Railway Oriented Programming" where successful operations continue on the "success track" and failures switch to the "failure track" and skip all subsequent operations. This pattern is ideal for request processing pipelines.

### Integration with Rack-fts
The Result monad pattern is perfect for implementing FTS stages:

1. Each stage (Authenticate, Authorize, Action, Render) returns Success or Failure
2. Stages are composed with bind to create a pipeline
3. Failures short-circuit the pipeline and skip remaining stages
4. Do notation keeps the code readable and maintainable
5. Error information is preserved throughout the pipeline

