# frozen_string_literal: true

module Rack
  module FTS
    module Stages
      class Authorize < Stage
        protected
        
        def perform(context)
          # Check if authenticated
          identity = context[:identity]
          
          if identity.nil?
            return Failure(
              error: "No authenticated identity found",
              stage: name,
              code: :no_identity
            )
          end
          
          # Extract request information
          request = context[:request]
          resource = extract_resource(request)
          action = extract_action(request)
          
          # Check permissions
          permissions = check_permissions(identity, resource, action)
          
          if permissions.nil? || !permissions[:allowed]
            return Failure(
              error: "Access denied",
              stage: name,
              code: :access_denied,
              resource: resource,
              action: action
            )
          end
          
          # Add permissions to context
          context[:permissions] = permissions
          Success(context)
        end
        
        private
        
        # Extract resource from request
        # Override this method to implement custom resource extraction
        # @param request [Rack::Request] The request object
        # @return [String] The resource identifier
        def extract_resource(request)
          # Default implementation: use path
          request.path
        end
        
        # Extract action from request
        # Override this method to implement custom action extraction
        # @param request [Rack::Request] The request object
        # @return [String] The action identifier
        def extract_action(request)
          # Default implementation: use HTTP method
          request.request_method.downcase
        end
        
        # Check permissions
        # Override this method to implement custom authorization logic
        # @param identity [Hash] The authenticated identity
        # @param resource [String] The resource identifier
        # @param action [String] The action identifier
        # @return [Hash, nil] The permissions or nil
        def check_permissions(identity, resource, action)
          # Default implementation: allow all
          # In production, check against ACL, RBAC, ABAC, etc.
          {
            allowed: true,
            identity: identity,
            resource: resource,
            action: action,
            authorized_at: Time.now
          }
        end
      end
    end
  end
end
