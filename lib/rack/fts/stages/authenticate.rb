# frozen_string_literal: true

module Rack
  module FTS
    module Stages
      class Authenticate < Stage
        protected
        
        def perform(context)
          # Extract authentication credentials from request
          request = context[:request]
          auth_header = request.env["HTTP_AUTHORIZATION"]
          
          if auth_header.nil? || auth_header.empty?
            return Failure(
              error: "Missing authentication credentials",
              stage: name,
              code: :missing_credentials
            )
          end
          
          # Parse authentication header
          identity = parse_auth_header(auth_header)
          
          if identity.nil?
            return Failure(
              error: "Invalid authentication credentials",
              stage: name,
              code: :invalid_credentials
            )
          end
          
          # Verify credentials
          verified_identity = verify_credentials(identity)
          
          if verified_identity.nil?
            return Failure(
              error: "Authentication failed",
              stage: name,
              code: :authentication_failed
            )
          end
          
          # Add identity to context
          context[:identity] = verified_identity
          Success(context)
        end
        
        private
        
        # Parse authentication header
        # Override this method to implement custom authentication parsing
        # @param auth_header [String] The Authorization header value
        # @return [Hash, nil] The parsed identity or nil
        def parse_auth_header(auth_header)
          # Default implementation: Bearer token
          if auth_header.start_with?("Bearer ")
            token = auth_header.sub("Bearer ", "")
            { token: token }
          else
            nil
          end
        end
        
        # Verify credentials
        # Override this method to implement custom credential verification
        # @param identity [Hash] The parsed identity
        # @return [Hash, nil] The verified identity or nil
        def verify_credentials(identity)
          # Default implementation: accept any token
          # In production, verify against database, JWT, etc.
          identity.merge(
            user_id: "user_#{identity[:token]}",
            authenticated_at: Time.now
          )
        end
      end
    end
  end
end
