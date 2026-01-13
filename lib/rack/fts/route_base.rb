# frozen_string_literal: true

require "json"

module Rack
  module FTS
    # Base class for FTS route handlers (plugins) that respond to routes Rails doesn't handle.
    #
    # RouteBase is a hybrid class that supports two execution modes:
    # - FTS Mode: Runs the full authenticate -> authorize -> action -> render pipeline
    # - Rails Mode: Delegates to a Rails controller/action
    #
    # @example FTS Pipeline Mode
    #   class ApiDocsRoute < Rack::FTS::RouteBase
    #     route_pattern %r{^/api/docs(/.*)?$}
    #     http_methods :get
    #
    #     class DocsAction < Rack::FTS::Stages::Action
    #       protected
    #       def execute_action(request, identity, permissions)
    #         { docs: "API documentation" }
    #       end
    #     end
    #
    #     protected
    #     def action_stage_class
    #       DocsAction
    #     end
    #   end
    #
    # @example Rails Delegation Mode
    #   class LegacyApiRoute < Rack::FTS::RouteBase
    #     route_pattern %r{^/v1/legacy(/.*)?$}
    #     http_methods :get, :post
    #     delegate_to "LegacyApi", action: :handle
    #   end
    #
    # @example Skip Authentication (e.g., health checks)
    #   class HealthCheckRoute < Rack::FTS::RouteBase
    #     route_pattern "/health"
    #     http_methods :get
    #
    #     protected
    #     def authenticate_stage_class
    #       Rack::FTS::Stages::NoOp
    #     end
    #   end
    class RouteBase
      include Dry::Monads[:result]

      class << self
        # DSL: Define route pattern (String or Regexp)
        # @param pattern [String, Regexp, nil] The pattern to match against request path
        # @return [String, Regexp, nil] The current pattern
        def route_pattern(pattern = nil)
          @route_pattern = pattern if pattern
          @route_pattern
        end

        # DSL: Define allowed HTTP methods
        # @param methods [Array<Symbol>] The HTTP methods to allow
        # @return [Array<Symbol>] The current allowed methods
        def http_methods(*methods)
          @http_methods = methods unless methods.empty?
          @http_methods || [:get, :post, :put, :patch, :delete]
        end

        # DSL: Define Rails controller delegation
        # @param controller [String, nil] The controller name (without "Controller" suffix)
        # @param action [Symbol] The action to call
        # @return [Hash] The delegation configuration
        # @example
        #   delegate_to "ApiDocs", action: :show
        def delegate_to(controller = nil, action: nil)
          if controller
            @rails_controller = controller
            @rails_action = action || :index
          end
          { controller: @rails_controller, action: @rails_action }
        end

        # ============================================
        # Use Case 5: Plugin Metadata DSL
        # ============================================

        # DSL: Define unique plugin identifier
        # @param name [Symbol, String, nil] The plugin name
        # @return [Symbol] The current plugin name
        # @example
        #   plugin_name :health_check
        def plugin_name(name = nil)
          @plugin_name = name.to_sym if name
          @plugin_name || default_plugin_name
        end

        # DSL: Define plugin version
        # @param version [String, nil] Semantic version string
        # @return [String] The current plugin version
        # @example
        #   plugin_version "1.2.0"
        def plugin_version(version = nil)
          @plugin_version = version if version
          @plugin_version || "0.0.0"
        end

        # DSL: Define rack-fts version requirement
        # @param requirement [String, nil] RubyGems requirement string
        # @return [String, nil] The version requirement
        # @example
        #   requires_rack_fts "~> 0.2.0"
        #   requires_rack_fts ">= 0.1.0, < 1.0"
        def requires_rack_fts(requirement = nil)
          @rack_fts_version_requirement = requirement if requirement
          @rack_fts_version_requirement
        end

        # Alias for requires_rack_fts
        alias rack_fts_version_requirement requires_rack_fts

        # DSL: Define plugin priority (higher = checked first)
        # @param value [Integer, nil] Priority value
        # @return [Integer] The current priority
        # @example
        #   priority 100
        def priority(value = nil)
          @priority = value if value
          @priority || 0
        end

        # ============================================
        # Use Case 5: Nesting DSL
        # ============================================

        # DSL: Mount a child plugin at a relative path
        # @param child_class [Class] The plugin class to mount
        # @param at [String] The relative path prefix
        # @example
        #   mount ApiV1Plugin, at: "/v1"
        #   mount ApiV2Plugin, at: "/v2"
        def mount(child_class, at:)
          @mounted_plugins ||= []
          @mounted_plugins << { class: child_class, path: at }
        end

        # Get all mounted sub-plugins
        # @return [Array<Hash>] Array of {class:, path:} hashes
        def mounted_plugins
          @mounted_plugins || []
        end

        # DSL: Wrap child plugin stages with pre/post hooks
        # @param stage [Symbol] The stage to wrap (:authenticate, :authorize, :action, :render)
        # @param position [Symbol] When to run (:before or :after)
        # @yield [context] Block to execute with the context
        # @example
        #   wrap_with stage: :authenticate, position: :before do |context|
        #     context[:started_at] = Time.now
        #     Success(context)
        #   end
        def wrap_with(stage:, position:, &block)
          @stage_wrappers ||= {}
          @stage_wrappers[stage] ||= { before: [], after: [] }
          @stage_wrappers[stage][position] << block
        end

        # Get all stage wrappers
        # @return [Hash] Stage wrappers configuration
        def stage_wrappers
          @stage_wrappers || {}
        end

        # ============================================
        # Use Case 5: ENV Configuration
        # ============================================

        # Get the ENV configuration helper for this plugin
        # @return [PluginEnv] The ENV accessor instance
        def env
          @env ||= PluginEnv.new(plugin_name)
        end

        private

        # Generate default plugin name from class name
        # @return [Symbol] The default plugin name
        def default_plugin_name
          class_name = name || "anonymous"
          # Simple demodulize and underscore without ActiveSupport
          base_name = class_name.split("::").last || class_name
          base_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                   .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                   .downcase
                   .to_sym
        end
      end

      # Check if this handler matches the given request
      # Override this method for custom matching logic
      # @param request [Rack::Request] The incoming request
      # @return [Boolean] true if this handler should process the request
      def matches?(request)
        return false unless enabled?
        return false unless method_matches?(request)
        path_matches?(request)
      end

      # Check if this plugin is enabled via ENV configuration
      # @return [Boolean] true if enabled (default: true)
      def enabled?
        self.class.env.enabled?
      end

      # Get the ENV configuration helper for this plugin instance
      # @return [PluginEnv] The ENV accessor
      def env
        self.class.env
      end

      # Main entry point - chooses FTS or Rails mode
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        if rails_delegation?
          call_rails_controller(env)
        else
          call_fts_pipeline(env)
        end
      end

      protected

      # Override in subclass for custom authenticate stage
      # @return [Class] The authenticate stage class
      def authenticate_stage_class
        Stages::Authenticate
      end

      # Override in subclass for custom authorize stage
      # @return [Class] The authorize stage class
      def authorize_stage_class
        Stages::Authorize
      end

      # Override in subclass for custom action stage
      # @return [Class] The action stage class
      # @raise [NotImplementedError] if not overridden and not using delegation
      def action_stage_class
        raise NotImplementedError, "Override action_stage_class or use delegate_to"
      end

      # Override in subclass for custom render stage
      # @return [Class] The render stage class
      def render_stage_class
        Stages::Render
      end

      private

      # Check if Rails delegation is configured
      # @return [Boolean] true if delegate_to was called
      def rails_delegation?
        delegation = self.class.delegate_to
        !delegation[:controller].nil?
      end

      # FTS Mode: Run full pipeline
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple
      def call_fts_pipeline(env)
        task = build_task
        result = task.run(env)

        case result
        when Dry::Monads::Success
          result.value![:response].finish
        when Dry::Monads::Failure
          error_response(result.failure)
        end
      end

      # Rails Mode: Delegate to Rails controller
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple
      def call_rails_controller(env)
        delegation = self.class.delegate_to
        controller_name = delegation[:controller]
        action = delegation[:action]

        # Attempt to load the controller class
        controller_class = "#{controller_name}Controller".constantize

        # Build Rails-compatible path parameters
        env["action_dispatch.request.path_parameters"] = {
          controller: controller_name.underscore,
          action: action.to_s
        }

        # Call the controller action
        controller_class.action(action).call(env)
      rescue NameError => e
        # Controller not found
        [
          500,
          { "Content-Type" => "application/json" },
          [{ error: "Controller not found: #{controller_name}Controller", details: e.message }.to_json]
        ]
      end

      # Build a Task with configured stages
      # @return [Task] The configured task
      def build_task
        Task.new.tap do |task|
          task.add_stage(authenticate_stage_class.new("authenticate"))
          task.add_stage(authorize_stage_class.new("authorize"))
          task.add_stage(action_stage_class.new("action"))
          task.add_stage(render_stage_class.new("render"))
        end
      end

      # Check if HTTP method matches
      # @param request [Rack::Request] The incoming request
      # @return [Boolean] true if method is allowed
      def method_matches?(request)
        self.class.http_methods.include?(request.request_method.downcase.to_sym)
      end

      # Check if path matches
      # @param request [Rack::Request] The incoming request
      # @return [Boolean] true if path matches pattern
      def path_matches?(request)
        pattern = self.class.route_pattern
        return false unless pattern

        case pattern
        when Regexp then pattern.match?(request.path_info)
        when String then request.path_info == pattern
        else false
        end
      end

      # Generate error response from failure
      # @param error [Hash] The error information
      # @return [Array] Rack response tuple
      def error_response(error)
        status = determine_status_code(error)
        headers = { "Content-Type" => "application/json" }
        body = [error_body(error)]

        [status, headers, body]
      end

      # Determine HTTP status code from error
      # @param error [Hash] The error information
      # @return [Integer] HTTP status code
      def determine_status_code(error)
        case error[:stage]
        when "authenticate"
          401
        when "authorize"
          403
        else
          error[:status] || 500
        end
      end

      # Generate error body JSON
      # @param error [Hash] The error information
      # @return [String] JSON error body
      def error_body(error)
        {
          error: error[:error],
          stage: error[:stage],
          code: error[:code],
          timestamp: Time.now.iso8601
        }.compact.to_json
      end
    end
  end
end
