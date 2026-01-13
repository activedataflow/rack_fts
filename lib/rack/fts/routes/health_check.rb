# frozen_string_literal: true

module Rack
  module FTS
    module Routes
      # Example route handler for health check endpoints.
      #
      # This handler responds to GET /health with a JSON status response.
      # Authentication and authorization are skipped (using NoOp stages).
      #
      # @example Register the health check handler
      #   Rack::FTS.configure do |config|
      #     config.route_handlers = [
      #       Rack::FTS::Routes::HealthCheck,
      #       # ... other handlers
      #     ]
      #   end
      #
      # @example Response format
      #   {
      #     "status": "healthy",
      #     "timestamp": "2024-01-15T10:30:00Z"
      #   }
      class HealthCheck < RouteBase
        route_pattern "/health"
        http_methods :get

        # Custom action stage for health checks
        class HealthAction < Stages::Action
          protected

          def execute_action(request, identity, permissions)
            {
              status: "healthy",
              timestamp: Time.now.iso8601
            }
          end
        end

        protected

        # Skip authentication for health checks
        def authenticate_stage_class
          Stages::NoOp
        end

        # Skip authorization for health checks
        def authorize_stage_class
          Stages::NoOp
        end

        def action_stage_class
          HealthAction
        end
      end
    end
  end
end
