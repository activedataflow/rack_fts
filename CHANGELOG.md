# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-11

### Added
- Initial release of Rack-fts gem
- Core FTS pipeline with four stages: Authenticate, Authorize, Action, Render
- Stage base class with Success/Failure result types using dry-monads
- Task orchestrator for sequential stage execution
- Application class for standalone Rack server use case
- Middleware class for Rails integration with PreRails and PostRails stages
- Default stage implementations for all four stages
- Configuration management with global and per-application settings
- Comprehensive RSpec test suite
- Cucumber features for behavior-driven testing
- Example configurations for all three use cases
- Complete documentation with README, architecture diagrams, and usage examples
- MIT License

### Features
- Type-safe error handling with dry-monads Result types
- Railway Oriented Programming for clean error propagation
- Short-circuiting on failure to skip remaining stages
- Customizable stages through subclassing
- Three deployment modes: Standalone, Rails Engine, Rails Middleware
- Structured error responses with appropriate HTTP status codes
- Context passing between stages with accumulated data
- Reset functionality for stage re-execution

### Documentation
- Comprehensive README with usage examples
- UML class diagram showing component relationships
- UML sequence diagram showing request flow
- Architecture design document
- Example configurations for all use cases
- RSpec and Cucumber test examples

[0.1.0]: https://github.com/example/rack-fts/releases/tag/v0.1.0
