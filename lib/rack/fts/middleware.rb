# frozen_string_literal: true

module Rack
  module FTS
    class Middleware
      include Dry::Monads[:result]
      
      attr_reader :app, :config
      
      def initialize(app, &block)
        @app = app
        @config = Configuration.instance.dup
        block.call(@config) if block_given?
      end
      
      # Rack interface with PreRails, Rails, and PostRails stages
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        context = build_initial_context(env)
        
        # PreRails stages
        result = run_stages(config.pre_rails_stages, context)
        return error_response(result.failure) if result.failure?
        
        context = result.value!
        
        # Rails stage (delegate to wrapped application)
        status, headers, body = app.call(context[:env])
        context[:status] = status
        context[:headers] = headers
        context[:body] = body
        
        # PostRails stages
        result = run_stages(config.post_rails_stages, context)
        return error_response(result.failure) if result.failure?
        
        final_context = result.value!
        [final_context[:status], final_context[:headers], final_context[:body]]
      end
      
      private
      
      # Build initial context
      # @param env [Hash] The Rack environment
      # @return [Hash] The initial context
      def build_initial_context(env)
        {
          env: env,
          request: Rack::Request.new(env),
          identity: nil,
          permissions: nil
        }
      end
      
      # Run a sequence of stages
      # @param stage_classes [Array<Class>] Array of stage classes
      # @param context [Hash] The execution context
      # @return [Dry::Monads::Result] Success or Failure
      def run_stages(stage_classes, context)
        return Success(context) if stage_classes.empty?
        
        stage_classes.reduce(Success(context)) do |result, stage_class|
          result.bind do |ctx|
            stage = stage_class.new
            stage.call(ctx)
          end
        end
      end
      
      # Generate error response
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
      
      # Generate error body
      # @param error [Hash] The error information
      # @return [String] JSON error body
      def error_body(error)
        require "json"
        {
          error: error[:error],
          stage: error[:stage],
          timestamp: Time.now.iso8601
        }.to_json
      end
    end
  end
end
