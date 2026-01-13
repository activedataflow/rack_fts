# frozen_string_literal: true

Given("I have a standalone FTS application") do
  set_app(Rack::FTS::Application.new)
end

Given("I have a standalone FTS application with custom stages") do
  custom_action = Class.new(Rack::FTS::Stages::Action) do
    protected
    def execute_action(request, identity, permissions)
      { custom: true, message: "Custom stage executed" }
    end
  end
  
  set_app(Rack::FTS::Application.new do |config|
    config.action_stage = custom_action
  end)
end

Given("I have a valid authentication token") do
  header "Authorization", "Bearer valid_token_123"
end

Given("I have an invalid authentication token") do
  header "Authorization", "Invalid token_format"
end

When("I make a GET request to {string}") do |path|
  get path
end

When("I make a POST request to {string} with data") do |path|
  post path, { data: "test" }.to_json, { "CONTENT_TYPE" => "application/json" }
end

Then("the response status should be {int}") do |status|
  expect(last_response.status).to eq(status)
end

Then("the response should be JSON") do
  expect(last_response.content_type).to eq("application/json")
end

Then("the response should contain {string}") do |key|
  body = last_json_response
  expect(body).to have_key(key)
end

Then("the response should contain an error about authentication") do
  body = last_json_response
  expect(body["error"]).to match(/authentication/i)
end

Then("the response should contain the request method {string}") do |method|
  body = last_json_response
  expect(body["request_method"]).to eq(method)
end

Then("the response should contain custom stage data") do
  body = last_json_response
  expect(body["custom"]).to eq(true)
  expect(body["message"]).to eq("Custom stage executed")
end
