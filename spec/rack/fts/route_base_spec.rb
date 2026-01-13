# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::FTS::RouteBase do
  # Test route handler with FTS pipeline
  let(:fts_route_class) do
    Class.new(described_class) do
      route_pattern "/test"
      http_methods :get, :post

      class TestAction < Rack::FTS::Stages::Action
        protected

        def execute_action(request, identity, permissions)
          { message: "test action executed" }
        end
      end

      protected

      def action_stage_class
        TestAction
      end
    end
  end

  # Test route handler with regex pattern
  let(:regex_route_class) do
    Class.new(described_class) do
      route_pattern %r{^/api/v1/.*$}
      http_methods :get

      class ApiAction < Rack::FTS::Stages::Action
        protected

        def execute_action(request, identity, permissions)
          { api: true }
        end
      end

      protected

      def action_stage_class
        ApiAction
      end
    end
  end

  # Test route handler that skips authentication
  let(:no_auth_route_class) do
    Class.new(described_class) do
      route_pattern "/health"
      http_methods :get

      class HealthAction < Rack::FTS::Stages::Action
        protected

        def execute_action(request, identity, permissions)
          { status: "healthy" }
        end
      end

      protected

      def authenticate_stage_class
        Rack::FTS::Stages::NoOp
      end

      def authorize_stage_class
        Rack::FTS::Stages::NoOp
      end

      def action_stage_class
        HealthAction
      end
    end
  end

  def build_request(path, method = "GET")
    env = Rack::MockRequest.env_for(path, method: method)
    Rack::Request.new(env)
  end

  describe ".route_pattern" do
    it "sets and gets the route pattern" do
      expect(fts_route_class.route_pattern).to eq("/test")
    end

    it "supports regex patterns" do
      expect(regex_route_class.route_pattern).to be_a(Regexp)
    end
  end

  describe ".http_methods" do
    it "sets and gets allowed HTTP methods" do
      expect(fts_route_class.http_methods).to eq([:get, :post])
    end

    it "has sensible defaults" do
      blank_route = Class.new(described_class)
      expect(blank_route.http_methods).to eq([:get, :post, :put, :patch, :delete])
    end
  end

  describe "#matches?" do
    context "with string pattern" do
      it "matches exact path" do
        route = fts_route_class.new
        request = build_request("/test", "GET")
        expect(route.matches?(request)).to be true
      end

      it "does not match different path" do
        route = fts_route_class.new
        request = build_request("/other", "GET")
        expect(route.matches?(request)).to be false
      end
    end

    context "with regex pattern" do
      it "matches paths that match the regex" do
        route = regex_route_class.new
        request = build_request("/api/v1/users", "GET")
        expect(route.matches?(request)).to be true
      end

      it "does not match paths outside the regex" do
        route = regex_route_class.new
        request = build_request("/api/v2/users", "GET")
        expect(route.matches?(request)).to be false
      end
    end

    context "with HTTP method matching" do
      it "matches allowed methods" do
        route = fts_route_class.new
        request = build_request("/test", "POST")
        expect(route.matches?(request)).to be true
      end

      it "does not match disallowed methods" do
        route = fts_route_class.new
        request = build_request("/test", "DELETE")
        expect(route.matches?(request)).to be false
      end
    end
  end

  describe "#call" do
    context "with FTS pipeline mode" do
      it "returns 401 when authentication fails" do
        route = fts_route_class.new
        env = Rack::MockRequest.env_for("/test", method: "GET")

        status, headers, body = route.call(env)

        expect(status).to eq(401)
        expect(headers["Content-Type"]).to eq("application/json")
      end

      it "returns success when authenticated" do
        route = fts_route_class.new
        env = Rack::MockRequest.env_for(
          "/test",
          method: "GET",
          "HTTP_AUTHORIZATION" => "Bearer test-token"
        )

        status, headers, body = route.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")

        response_body = JSON.parse(body.join)
        expect(response_body["message"]).to eq("test action executed")
      end
    end

    context "with no-auth routes" do
      it "skips authentication and returns success" do
        route = no_auth_route_class.new
        env = Rack::MockRequest.env_for("/health", method: "GET")

        status, headers, body = route.call(env)

        expect(status).to eq(200)
        response_body = JSON.parse(body.join)
        expect(response_body["status"]).to eq("healthy")
      end
    end
  end

  describe "error handling" do
    it "returns proper error structure for authentication failures" do
      route = fts_route_class.new
      env = Rack::MockRequest.env_for("/test", method: "GET")

      status, headers, body = route.call(env)
      error = JSON.parse(body.join)

      expect(error).to have_key("error")
      expect(error).to have_key("stage")
      expect(error).to have_key("timestamp")
      expect(error["stage"]).to eq("authenticate")
    end
  end
end
