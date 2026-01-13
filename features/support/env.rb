# frozen_string_literal: true

require "rack/test"
require_relative "../../lib/rack-fts"

World(Rack::Test::Methods)

# Helper methods for Cucumber scenarios
module FTSHelpers
  def app
    @app
  end
  
  def set_app(application)
    @app = application
  end
  
  def last_json_response
    JSON.parse(last_response.body)
  end
end

World(FTSHelpers)
