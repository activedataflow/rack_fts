# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::FTS::Application do
  def app
    @app ||= described_class.new
  end
  
  describe "#call" do
    context "with valid authentication" do
      it "returns successful response" do
        header "Authorization", "Bearer test_token"
        get "/test"
        
        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to eq("application/json")
        
        body = JSON.parse(last_response.body)
        expect(body["status"]).to eq("success")
      end
    end
    
    context "without authentication" do
      it "returns 401 Unauthorized" do
        get "/test"
        
        expect(last_response.status).to eq(401)
        expect(last_response.content_type).to eq("application/json")
        
        body = JSON.parse(last_response.body)
        expect(body["error"]).to include("authentication")
        expect(body["stage"]).to eq("authenticate")
      end
    end
    
    context "with custom configuration" do
      let(:custom_action_stage) do
        Class.new(Rack::FTS::Stages::Action) do
          protected
          def execute_action(request, identity, permissions)
            { custom: "result", message: "Custom action executed" }
          end
        end
      end
      
      def app
        @app ||= described_class.new do |config|
          config.action_stage = custom_action_stage
        end
      end
      
      it "uses custom stage" do
        header "Authorization", "Bearer test_token"
        get "/test"
        
        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        expect(body["custom"]).to eq("result")
        expect(body["message"]).to eq("Custom action executed")
      end
    end
  end
  
  describe "error handling" do
    context "when authenticate stage fails" do
      it "returns 401 with error details" do
        get "/test"
        
        expect(last_response.status).to eq(401)
        body = JSON.parse(last_response.body)
        expect(body).to have_key("error")
        expect(body).to have_key("stage")
        expect(body).to have_key("timestamp")
      end
    end
  end
end
