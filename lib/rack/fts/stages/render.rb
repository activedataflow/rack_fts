# frozen_string_literal: true

module Rack
  module FTS
    module Stages
      class Render < Stage
        protected
        
        def perform(context)
          # Extract action result
          action_result = context[:action_result]
          
          if action_result.nil?
            return Failure(
              error: "No action result to render",
              stage: name,
              code: :no_action_result
            )
          end
          
          # Get response object
          response = context[:response]
          
          # Render the response
          render_response(response, action_result, context)
          
          # Return updated context
          Success(context)
        end
        
        private
        
        # Render the response
        # Override this method to implement custom rendering logic
        # @param response [Rack::Response] The response object
        # @param action_result [Hash] The action result
        # @param context [Hash] The execution context
        def render_response(response, action_result, context)
          # Default implementation: JSON response
          response.status = 200
          response["Content-Type"] = "application/json"
          response.write(render_json(action_result))
        end
        
        # Render JSON
        # @param data [Hash] The data to render
        # @return [String] JSON string
        def render_json(data)
          require "json"
          data.to_json
        end
        
        # Render HTML (example)
        # @param data [Hash] The data to render
        # @return [String] HTML string
        def render_html(data)
          <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
              <title>FTS Response</title>
            </head>
            <body>
              <h1>Action Result</h1>
              <pre>#{data.inspect}</pre>
            </body>
            </html>
          HTML
        end
      end
    end
  end
end
