# frozen_string_literal: true

require "json"

module Rack
  module FTS
    # Fallback router middleware that catches Rails routing errors and delegates
    # to configured FTS route handlers.
    #
    # When Rails throws ActionController::RoutingError (route not found), this
    # middleware intercepts the error and iterates through configured route_handlers
    # to find one that matches the request.
    #
    # @example Rails Configuration
    #   # config/initializers/rack_fts.rb
    #   Rack::FTS.configure do |config|
    #     config.route_handlers = [
    #       HealthCheckRoute,
    #       ApiDocsRoute,
    #       LegacyApiRoute,
    #     ]
    #   end
    #
    #   # config/application.rb
    #   module MyApp
    #     class Application < Rails::Application
    #       config.middleware.insert_before ActionDispatch::ShowExceptions,
    #                                       Rack::FTS::Router
    #     end
    #   end
    class Router
      include Dry::Monads[:result]

      attr_reader :app, :config

      # Initialize the router middleware
      # @param app [#call] The wrapped Rack application (typically Rails)
      # @yield [Configuration] Optional block to configure this router instance
      def initialize(app, &block)
        @app = app
        @config = Configuration.instance.dup
        block.call(@config) if block_given?
      end

      # Rack interface - process the request
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        # Try the wrapped app (Rails) first
        app.call(env)
      rescue routing_error_class => e
        # Rails couldn't route - try FTS handlers
        handle_unrouted_request(env, e)
      end

      private

      # Get the routing error class to catch
      # Returns a no-match class if ActionController is not defined (non-Rails environment)
      # @return [Class] The error class to catch
      def routing_error_class
        if defined?(ActionController::RoutingError)
          ActionController::RoutingError
        else
          # In non-Rails environments, use a class that will never be raised
          Class.new(StandardError)
        end
      end

      # Handle a request that Rails couldn't route
      # @param env [Hash] The Rack environment
      # @param original_error [Exception] The original routing error
      # @return [Array] Rack response tuple
      def handle_unrouted_request(env, original_error)
        request = Rack::Request.new(env)

        # Find first matching handler (including nested routes)
        handler = find_matching_handler(request)

        if handler
          handler.call(env)
        else
          # No handler found - return 404
          not_found_response(request, original_error)
        end
      end

      # Find a handler that matches the request
      # Checks both direct plugin matches and nested/mounted plugins
      # @param request [Rack::Request] The request
      # @return [RouteBase, NestedRoute, nil] The matching handler or nil
      def find_matching_handler(request)
        config.route_handlers.each do |handler_class|
          instance = handler_class.new

          # Check direct match (includes enabled? check via matches?)
          return instance if instance.matches?(request)

          # Check mounted sub-plugins (Use Case 5)
          nested = find_nested_match(handler_class, request)
          return nested if nested
        end
        nil
      end

      # Find a matching nested route within a parent plugin
      # @param parent_class [Class] The parent plugin class
      # @param request [Rack::Request] The request
      # @return [NestedRoute, nil] The matching nested route or nil
      def find_nested_match(parent_class, request)
        return nil unless parent_class.respond_to?(:mounted_plugins)

        parent_class.mounted_plugins.each do |mount_config|
          nested = NestedRoute.new(
            parent: parent_class,
            child: mount_config[:class],
            mount_path: mount_config[:path]
          )
          return nested if nested.matches?(request)
        end
        nil
      end

      # Generate 404 Not Found response
      # @param request [Rack::Request] The request
      # @param error [Exception] The original error
      # @return [Array] Rack response tuple
      def not_found_response(request, error)
        [
          404,
          { "Content-Type" => "application/json" },
          [not_found_body(request, error)]
        ]
      end

      # Generate 404 response body
      # @param request [Rack::Request] The request
      # @param error [Exception] The original error
      # @return [String] JSON body
      def not_found_body(request, error)
        {
          error: "Not Found",
          path: request.path_info,
          method: request.request_method,
          timestamp: Time.now.iso8601
        }.to_json
      end
    end
  end
end
