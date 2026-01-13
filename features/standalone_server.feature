Feature: Standalone FTS Server
  As a developer
  I want to use Rack-fts as a standalone server
  So that I can build API services with FTS pipeline

  Background:
    Given I have a standalone FTS application

  Scenario: Successful request with authentication
    Given I have a valid authentication token
    When I make a GET request to "/api/resource"
    Then the response status should be 200
    And the response should be JSON
    And the response should contain "status"

  Scenario: Request without authentication
    When I make a GET request to "/api/resource"
    Then the response status should be 401
    And the response should be JSON
    And the response should contain an error about authentication

  Scenario: Request with invalid authentication
    Given I have an invalid authentication token
    When I make a GET request to "/api/resource"
    Then the response status should be 401
    And the response should contain an error about authentication

  Scenario: POST request with authentication
    Given I have a valid authentication token
    When I make a POST request to "/api/resource" with data
    Then the response status should be 200
    And the response should contain the request method "POST"

  Scenario: Custom stage configuration
    Given I have a standalone FTS application with custom stages
    And I have a valid authentication token
    When I make a GET request to "/api/resource"
    Then the response status should be 200
    And the response should contain custom stage data
