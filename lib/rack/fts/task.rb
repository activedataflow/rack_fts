# frozen_string_literal: true

module Rack
  module FTS
    class Task
      include Dry::Monads[:result]
      include Dry::Monads::Do.for(:run, :run_conditional)
      
      attr_reader :stages
      
      def initialize
        @stages = []
      end
      
      # Add a stage to the task
      # @param stage [Stage] The stage to add
      # @return [Task] self for chaining
      def add_stage(stage)
        raise ArgumentError, "Stage must be a Rack::FTS::Stage" unless stage.is_a?(Stage)
        @stages << stage
        self
      end
      
      # Run all stages sequentially
      # @param env [Hash] The Rack environment
      # @return [Dry::Monads::Result] Success or Failure
      def run(env)
        context = build_initial_context(env)
        
        stages.each do |stage|
          context = yield stage.call(context)
        end
        
        Success(context)
      end
      
      # Run stages with conditional logic
      # @param env [Hash] The Rack environment
      # @return [Dry::Monads::Result] Success or Failure
      def run_conditional(env)
        context = build_initial_context(env)
        current_index = 0
        
        while current_index < stages.length
          stage = stages[current_index]
          result = stage.call(context)
          
          if result.success?
            context = result.value!
            current_index = determine_next_stage(result, current_index)
          else
            return result
          end
        end
        
        Success(context)
      end
      
      # Get all successful stage results
      # @return [Array<Dry::Monads::Success>] Array of successful results
      def successful_results
        stages.select(&:success?).map(&:result)
      end
      
      # Get all failed stage results
      # @return [Array<Dry::Monads::Failure>] Array of failed results
      def failed_results
        stages.select(&:failure?).map(&:result)
      end
      
      # Check if all stages succeeded
      # @return [Boolean] true if all stages succeeded
      def all_successful?
        stages.all?(&:success?)
      end
      
      # Check if any stage failed
      # @return [Boolean] true if any stage failed
      def any_failed?
        stages.any?(&:failure?)
      end
      
      # Reset all stages
      def reset!
        stages.each(&:reset!)
      end
      
      private
      
      # Build the initial context from Rack environment
      # @param env [Hash] The Rack environment
      # @return [Hash] The initial context
      def build_initial_context(env)
        {
          env: env,
          request: Rack::Request.new(env),
          response: Rack::Response.new,
          identity: nil,
          permissions: nil,
          action_result: nil
        }
      end
      
      # Determine the next stage to execute (can be overridden)
      # @param result [Dry::Monads::Result] The current stage result
      # @param current_index [Integer] The current stage index
      # @return [Integer] The next stage index
      def determine_next_stage(result, current_index)
        current_index + 1
      end
    end
  end
end
