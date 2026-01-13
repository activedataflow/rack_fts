# frozen_string_literal: true

module Rack
  module FTS
    class Application
      include Dry::Monads[:result]
      
      attr_reader :config, :task
      
      def initialize(&block)
        @config = Configuration.instance.dup
        block.call(@config) if block_given?
        @task = build_task
      end
      
      # Rack interface
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        result = task.run(env)
        
        case result
        when Dry::Monads::Success
          extract_response(result.value!)
        when Dry::Monads::Failure
          error_response(result.failure)
        end
      end
      
      private
      
      # Build the task with configured stages
      # @return [Task] The configured task
      def build_task
        Task.new.tap do |t|
          t.add_stage(config.authenticate_stage.new("authenticate"))
          t.add_stage(config.authorize_stage.new("authorize"))
          t.add_stage(config.action_stage.new("action"))
          t.add_stage(config.render_stage.new("render"))
        end
      end
      
      # Extract Rack response from context
      # @param context [Hash] The execution context
      # @return [Array] Rack response tuple
      def extract_response(context)
        response = context[:response]
        response.finish
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
        when "action"
          error[:status] || 500
        else
          500
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
