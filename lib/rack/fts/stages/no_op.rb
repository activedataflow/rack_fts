# frozen_string_literal: true

module Rack
  module FTS
    module Stages
      # NoOp stage that passes through with placeholder values.
      # Useful for routes that need to skip authentication or authorization.
      #
      # When used for authentication, sets a placeholder identity.
      # When used for authorization, sets a placeholder permissions hash.
      #
      # @example Skip authentication for health checks
      #   class HealthCheckRoute < Rack::FTS::RouteBase
      #     def authenticate_stage_class
      #       Rack::FTS::Stages::NoOp
      #     end
      #     def authorize_stage_class
      #       Rack::FTS::Stages::NoOp
      #     end
      #   end
      class NoOp < Stage
        protected

        def perform(context)
          # Set placeholder identity if not present (for skipping authenticate)
          context[:identity] ||= {
            anonymous: true,
            authenticated_at: Time.now
          }

          # Set placeholder permissions if not present (for skipping authorize)
          context[:permissions] ||= {
            allowed: true,
            anonymous: true,
            authorized_at: Time.now
          }

          Success(context)
        end
      end
    end
  end
end
