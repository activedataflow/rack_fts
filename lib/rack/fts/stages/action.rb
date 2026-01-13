# frozen_string_literal: true

module Rack
  module FTS
    module Stages
      class Action < Stage
        protected
        
        def perform(context)
          # Check if authorized
          permissions = context[:permissions]
          
          if permissions.nil?
            return Failure(
              error: "No authorization found",
              stage: name,
              code: :no_authorization
            )
          end
          
          # Extract request information
          request = context[:request]
          identity = context[:identity]
          
          # Execute the action
          result = execute_action(request, identity, permissions)
          
          if result.nil?
            return Failure(
              error: "Action execution failed",
              stage: name,
              code: :action_failed
            )
          end
          
          # Add action result to context
          context[:action_result] = result
          Success(context)
        end
        
        private
        
        # Execute the action
        # Override this method to implement custom action logic
        # @param request [Rack::Request] The request object
        # @param identity [Hash] The authenticated identity
        # @param permissions [Hash] The authorization permissions
        # @return [Hash, nil] The action result or nil
        def execute_action(request, identity, permissions)
          # Default implementation: echo request information
          {
            status: :success,
            message: "Action executed successfully",
            request_method: request.request_method,
            request_path: request.path,
            identity: identity[:user_id],
            executed_at: Time.now
          }
        end
      end
    end
  end
end
