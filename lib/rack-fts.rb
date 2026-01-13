# frozen_string_literal: true

require "rack"
require "dry/monads"
require "dry/configurable"

require_relative "rack/fts/version"
require_relative "rack/fts/configuration"
require_relative "rack/fts/stage"
require_relative "rack/fts/task"
require_relative "rack/fts/application"
require_relative "rack/fts/middleware"
require_relative "rack/fts/route_base"
require_relative "rack/fts/router"

# Load default stage implementations
require_relative "rack/fts/stages/authenticate"
require_relative "rack/fts/stages/authorize"
require_relative "rack/fts/stages/action"
require_relative "rack/fts/stages/render"
require_relative "rack/fts/stages/no_op"

# Load example route handlers
require_relative "rack/fts/routes/health_check"

module Rack
  module FTS
    class Error < StandardError; end
    
    class << self
      def configure(&block)
        Configuration.instance.configure(&block)
      end
      
      def configuration
        Configuration.instance
      end
    end
  end
end
