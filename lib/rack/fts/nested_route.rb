# frozen_string_literal: true

module Rack
  module FTS
    # Handles route prefix mounting and stage wrapping for nested plugins.
    #
    # When a parent plugin mounts a child plugin at a relative path,
    # NestedRoute handles:
    # - Path prefix stripping (e.g., /api/v1/users becomes /users for child)
    # - Stage wrapper execution (before/after hooks from parent)
    # - Request delegation to child plugin
    #
    # @example Request flow
    #   Request: GET /api/v1/users
    #   1. Parent (ApiPlugin) matches /api/*
    #   2. NestedRoute created with child (ApiV1Plugin) at /v1
    #   3. Path stripped: /api/v1/users -> /users
    #   4. Parent's before wrappers run
    #   5. Child's pipeline executes
    #   6. Parent's after wrappers run
    class NestedRoute
      include Dry::Monads[:result]

      attr_reader :parent_class, :child_class, :mount_path

      # @param parent [Class] The parent plugin class
      # @param child [Class] The child plugin class
      # @param mount_path [String] The relative path prefix
      def initialize(parent:, child:, mount_path:)
        @parent_class = parent
        @child_class = child
        @mount_path = mount_path
      end

      # Check if this nested route matches the request
      # @param request [Rack::Request] The incoming request
      # @return [Boolean] true if this nested route should handle the request
      def matches?(request)
        return false unless path_has_prefix?(request)

        # Check if child matches the stripped path
        modified_request = strip_prefix_from_request(request)
        child_instance.matches?(modified_request)
      end

      # Process the request through the nested route
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        request = Rack::Request.new(env)

        # Apply parent's before wrappers
        context = initial_context(env)
        context = apply_before_wrappers(context)
        return failure_response(context) if context.is_a?(Dry::Monads::Failure)

        # Modify env for child (strip path prefix)
        modified_env = strip_path_prefix(env)

        # Execute child plugin
        child_response = child_instance.call(modified_env)

        # Apply parent's after wrappers
        context = context.merge(child_response: child_response)
        context = apply_after_wrappers(context)
        return failure_response(context) if context.is_a?(Dry::Monads::Failure)

        # Return child's response (possibly modified by after wrappers)
        context[:child_response] || child_response
      end

      # Get the child plugin instance
      # @return [RouteBase] The child plugin instance
      def child_instance
        @child_instance ||= child_class.new
      end

      # Get the parent plugin instance
      # @return [RouteBase] The parent plugin instance
      def parent_instance
        @parent_instance ||= parent_class.new
      end

      private

      # Check if request path starts with mount path
      # @param request [Rack::Request] The request
      # @return [Boolean] true if path has prefix
      def path_has_prefix?(request)
        request.path_info.start_with?(full_mount_path)
      end

      # Get the full mount path including parent's pattern
      # For simplicity, we use just the mount_path here
      # The parent match is handled by the router
      # @return [String] The mount path
      def full_mount_path
        mount_path
      end

      # Strip the mount path prefix from the request
      # @param request [Rack::Request] The original request
      # @return [Rack::Request] A new request with stripped path
      def strip_prefix_from_request(request)
        modified_env = request.env.dup
        modified_env["PATH_INFO"] = strip_path(request.path_info)
        modified_env["ORIGINAL_PATH_INFO"] = request.path_info
        Rack::Request.new(modified_env)
      end

      # Strip mount path prefix from env
      # @param env [Hash] The original Rack env
      # @return [Hash] Modified env with stripped path
      def strip_path_prefix(env)
        env.merge(
          "PATH_INFO" => strip_path(env["PATH_INFO"]),
          "ORIGINAL_PATH_INFO" => env["PATH_INFO"]
        )
      end

      # Strip the mount path from a path string
      # @param path [String] The original path
      # @return [String] The stripped path
      def strip_path(path)
        stripped = path.sub(mount_path, "")
        stripped.empty? ? "/" : stripped
      end

      # Build initial context for wrapper execution
      # @param env [Hash] The Rack environment
      # @return [Hash] The initial context
      def initial_context(env)
        {
          env: env,
          request: Rack::Request.new(env),
          response: Rack::Response.new,
          parent_class: parent_class,
          child_class: child_class,
          mount_path: mount_path
        }
      end

      # Apply parent's before stage wrappers
      # @param context [Hash] The current context
      # @return [Hash, Dry::Monads::Failure] The modified context or failure
      def apply_before_wrappers(context)
        apply_wrappers(context, :before)
      end

      # Apply parent's after stage wrappers
      # @param context [Hash] The current context
      # @return [Hash, Dry::Monads::Failure] The modified context or failure
      def apply_after_wrappers(context)
        apply_wrappers(context, :after)
      end

      # Apply wrappers for a specific position
      # @param context [Hash] The current context
      # @param position [Symbol] :before or :after
      # @return [Hash, Dry::Monads::Failure] The modified context or failure
      def apply_wrappers(context, position)
        wrappers = parent_class.stage_wrappers
        return context if wrappers.empty?

        # Apply wrappers for each stage in order
        [:authenticate, :authorize, :action, :render].each do |stage|
          stage_wrappers = wrappers.dig(stage, position) || []
          stage_wrappers.each do |wrapper_block|
            result = wrapper_block.call(context)
            case result
            when Dry::Monads::Success
              context = result.value!
            when Dry::Monads::Failure
              return result
            when Hash
              context = result
            end
          end
        end

        context
      end

      # Convert a failure to a Rack response
      # @param failure [Dry::Monads::Failure] The failure
      # @return [Array] Rack response tuple
      def failure_response(failure)
        error = failure.failure
        status = error[:status] || 500
        headers = { "Content-Type" => "application/json" }
        body = [{
          error: error[:error] || "Wrapper error",
          stage: error[:stage] || "wrapper",
          code: error[:code],
          timestamp: Time.now.iso8601
        }.compact.to_json]

        [status, headers, body]
      end
    end
  end
end
