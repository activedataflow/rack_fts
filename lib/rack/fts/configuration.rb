# frozen_string_literal: true

require "singleton"

module Rack
  module FTS
    class Configuration
      include Singleton
      
      attr_accessor :authenticate_stage,
                    :authorize_stage,
                    :action_stage,
                    :render_stage,
                    :pre_rails_stages,
                    :post_rails_stages,
                    :route_handlers,
                    :error_handler,
                    :logger

      def initialize
        @authenticate_stage = Stages::Authenticate
        @authorize_stage = Stages::Authorize
        @action_stage = Stages::Action
        @render_stage = Stages::Render
        @pre_rails_stages = []
        @post_rails_stages = []
        @route_handlers = []
        @error_handler = nil
        @logger = nil
      end
      
      def configure
        yield self if block_given?
      end

      # Create a duplicate of this configuration
      # Singleton instances can't be duped normally, so we provide this method
      # @return [Configuration] A new configuration with copied values
      def dup
        copy = self.class.send(:allocate)
        copy.instance_variable_set(:@authenticate_stage, @authenticate_stage)
        copy.instance_variable_set(:@authorize_stage, @authorize_stage)
        copy.instance_variable_set(:@action_stage, @action_stage)
        copy.instance_variable_set(:@render_stage, @render_stage)
        copy.instance_variable_set(:@pre_rails_stages, @pre_rails_stages.dup)
        copy.instance_variable_set(:@post_rails_stages, @post_rails_stages.dup)
        copy.instance_variable_set(:@route_handlers, @route_handlers.dup)
        copy.instance_variable_set(:@error_handler, @error_handler)
        copy.instance_variable_set(:@logger, @logger)
        copy
      end
    end
  end
end
