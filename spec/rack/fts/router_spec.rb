# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::FTS::Router do
  # Mock Rails routing error for testing
  let(:routing_error_class) do
    Class.new(StandardError)
  end

  # Simple app that raises routing error
  let(:routing_error_app) do
    error_class = routing_error_class
    lambda { |env| raise error_class, "No route matches" }
  end

  # Simple app that succeeds
  let(:success_app) do
    lambda { |env| [200, { "Content-Type" => "text/plain" }, ["Rails handled it"]] }
  end

  # Test route handler
  let(:test_route_class) do
    Class.new(Rack::FTS::RouteBase) do
      route_pattern "/fts-handled"
      http_methods :get

      class TestAction < Rack::FTS::Stages::Action
        protected

        def execute_action(request, identity, permissions)
          { handler: "fts" }
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
        TestAction
      end
    end
  end

  # Catch-all route handler
  let(:catchall_route_class) do
    Class.new(Rack::FTS::RouteBase) do
      route_pattern %r{^/api/.*$}
      http_methods :get, :post, :put, :patch, :delete

      class CatchAllAction < Rack::FTS::Stages::Action
        protected

        def execute_action(request, identity, permissions)
          { caught: true, path: request.path_info }
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
        CatchAllAction
      end
    end
  end

  describe "#initialize" do
    it "wraps the given app" do
      router = described_class.new(success_app)
      expect(router.app).to eq(success_app)
    end

    it "creates a copy of configuration" do
      router = described_class.new(success_app)
      expect(router.config).to be_a(Rack::FTS::Configuration)
    end

    it "accepts configuration block" do
      router = described_class.new(success_app) do |config|
        config.route_handlers = [test_route_class]
      end

      expect(router.config.route_handlers).to include(test_route_class)
    end
  end

  describe "#call" do
    context "when Rails handles the route" do
      it "passes through to wrapped app" do
        router = described_class.new(success_app) do |config|
          config.route_handlers = [test_route_class]
        end

        env = Rack::MockRequest.env_for("/rails-route")
        status, headers, body = router.call(env)

        expect(status).to eq(200)
        expect(body).to eq(["Rails handled it"])
      end
    end

    context "when Rails raises routing error" do
      before do
        # Stub the routing_error_class method to return our test class
        allow_any_instance_of(described_class).to receive(:routing_error_class)
          .and_return(routing_error_class)
      end

      it "delegates to matching FTS handler" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = [test_route_class]
        end

        env = Rack::MockRequest.env_for("/fts-handled", method: "GET")
        status, headers, body = router.call(env)

        expect(status).to eq(200)
        response = JSON.parse(body.join)
        expect(response["handler"]).to eq("fts")
      end

      it "tries handlers in order and uses first match" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = [test_route_class, catchall_route_class]
        end

        env = Rack::MockRequest.env_for("/fts-handled", method: "GET")
        status, headers, body = router.call(env)

        # Should match test_route_class first
        response = JSON.parse(body.join)
        expect(response["handler"]).to eq("fts")
      end

      it "falls through to catch-all handlers" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = [test_route_class, catchall_route_class]
        end

        env = Rack::MockRequest.env_for("/api/users", method: "GET")
        status, headers, body = router.call(env)

        response = JSON.parse(body.join)
        expect(response["caught"]).to eq(true)
        expect(response["path"]).to eq("/api/users")
      end

      it "returns 404 when no handler matches" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = [test_route_class]
        end

        env = Rack::MockRequest.env_for("/unknown", method: "GET")
        status, headers, body = router.call(env)

        expect(status).to eq(404)
        response = JSON.parse(body.join)
        expect(response["error"]).to eq("Not Found")
        expect(response["path"]).to eq("/unknown")
      end

      it "returns 404 when no handlers configured" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = []
        end

        env = Rack::MockRequest.env_for("/anything", method: "GET")
        status, headers, body = router.call(env)

        expect(status).to eq(404)
      end
    end

    context "HTTP method matching" do
      before do
        allow_any_instance_of(described_class).to receive(:routing_error_class)
          .and_return(routing_error_class)
      end

      it "matches handlers by HTTP method" do
        router = described_class.new(routing_error_app) do |config|
          config.route_handlers = [test_route_class]
        end

        # test_route_class only allows GET
        env = Rack::MockRequest.env_for("/fts-handled", method: "POST")
        status, headers, body = router.call(env)

        # Should not match, return 404
        expect(status).to eq(404)
      end
    end
  end

  describe "404 response format" do
    before do
      allow_any_instance_of(described_class).to receive(:routing_error_class)
        .and_return(routing_error_class)
    end

    it "includes error, path, method, and timestamp" do
      router = described_class.new(routing_error_app) do |config|
        config.route_handlers = []
      end

      env = Rack::MockRequest.env_for("/not-found", method: "POST")
      status, headers, body = router.call(env)

      response = JSON.parse(body.join)

      expect(response["error"]).to eq("Not Found")
      expect(response["path"]).to eq("/not-found")
      expect(response["method"]).to eq("POST")
      expect(response).to have_key("timestamp")
    end

    it "returns JSON content type" do
      router = described_class.new(routing_error_app) do |config|
        config.route_handlers = []
      end

      env = Rack::MockRequest.env_for("/not-found")
      status, headers, body = router.call(env)

      expect(headers["Content-Type"]).to eq("application/json")
    end
  end
end
