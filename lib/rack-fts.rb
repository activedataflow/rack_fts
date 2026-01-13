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

# Use Case 5: Plugin discovery and versioning
require_relative "rack/fts/plugin_env"
require_relative "rack/fts/version_checker"
require_relative "rack/fts/plugin_registry"
require_relative "rack/fts/plugin_discovery"
require_relative "rack/fts/nested_route"

# Load example route handlers
require_relative "rack/fts/routes/health_check"

# Rails engine (conditionally loaded when Rails is present)
require_relative "rack/fts/engine" if defined?(Rails::Engine)

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
