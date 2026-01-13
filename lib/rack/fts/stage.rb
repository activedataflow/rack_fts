# frozen_string_literal: true

module Rack
  module FTS
    class Stage
      include Dry::Monads[:result]
      
      attr_reader :name, :result
      
      def initialize(name = nil)
        @name = name || self.class.name.split("::").last.downcase
        @result = nil
      end
      
      # Main entry point for stage execution
      def call(context)
        @result = perform(context)
      rescue StandardError => e
        @result = Failure(
          error: e.message,
          stage: name,
          exception: e.class.name,
          backtrace: e.backtrace.first(5)
        )
      end
      
      # Check if stage has been executed
      def performed?
        !@result.nil?
      end
      
      # Check if stage succeeded
      def success?
        performed? && @result.success?
      end
      
      # Check if stage failed
      def failure?
        performed? && @result.failure?
      end
      
      # Get the success value
      def value
        return nil unless success?
        @result.value!
      end
      
      # Get the failure error
      def error
        return nil unless failure?
        @result.failure
      end
      
      # Reset stage to unexecuted state
      def reset!
        @result = nil
      end
      
      protected
      
      # Subclasses must implement this method
      # @param context [Hash] The execution context
      # @return [Dry::Monads::Result] Success or Failure
      def perform(context)
        raise NotImplementedError, "Subclasses must implement #perform"
      end
      
      # Check if preconditions are met before execution
      # @param context [Hash] The execution context
      # @return [Boolean] true if preconditions are met
      def preconditions_met?(context)
        true
      end
    end
  end
end
