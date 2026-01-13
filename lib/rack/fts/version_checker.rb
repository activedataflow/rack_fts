# frozen_string_literal: true

require "rubygems/version"
require "rubygems/requirement"

module Rack
  module FTS
    # Validates plugin version requirements against current rack-fts version.
    #
    # Plugins can declare version requirements using standard RubyGems syntax:
    #   requires_rack_fts "~> 0.2.0"  # Allows 0.2.x
    #   requires_rack_fts ">= 0.2.0, < 1.0"  # Range
    #
    # @example Checking compatibility
    #   VersionChecker.compatible?(MyPlugin)  # => true/false
    #
    # @example Strict checking (raises on incompatibility)
    #   VersionChecker.check!(MyPlugin)  # raises IncompatibleVersionError
    class VersionChecker
      # Error raised when a plugin is incompatible with current rack-fts version
      class IncompatibleVersionError < StandardError; end

      class << self
        # Check if a plugin is compatible with current rack-fts version
        # @param plugin_class [Class] The plugin class to check
        # @return [Boolean] true if compatible
        def compatible?(plugin_class)
          new(plugin_class).compatible?
        end

        # Check compatibility and raise if incompatible (based on config mode)
        # @param plugin_class [Class] The plugin class to check
        # @raise [IncompatibleVersionError] if incompatible and mode is :strict
        def check!(plugin_class)
          new(plugin_class).check!
        end
      end

      # @param plugin_class [Class] The plugin class to check
      def initialize(plugin_class)
        @plugin_class = plugin_class
        @requirement_string = extract_requirement(plugin_class)
      end

      # Check if plugin is compatible with current rack-fts version
      # @return [Boolean] true if compatible (or no requirement specified)
      def compatible?
        return true if @requirement_string.nil?

        requirement.satisfied_by?(current_version)
      end

      # Check compatibility based on configuration mode
      # @raise [IncompatibleVersionError] if mode is :strict and incompatible
      def check!
        return if compatible?

        case Configuration.instance.version_check_mode
        when :strict
          raise IncompatibleVersionError, error_message
        when :warn
          warn_incompatible
        when :ignore
          # Do nothing
        end
      end

      # Get the error message for incompatibility
      # @return [String] Human-readable error message
      def error_message
        plugin_name = extract_plugin_name(@plugin_class)
        "Plugin '#{plugin_name}' requires rack-fts #{@requirement_string}, " \
          "but current version is #{VERSION}"
      end

      private

      # Extract version requirement from plugin class
      # @param plugin_class [Class] The plugin class
      # @return [String, nil] The requirement string or nil
      def extract_requirement(plugin_class)
        return nil unless plugin_class.respond_to?(:rack_fts_version_requirement)

        plugin_class.rack_fts_version_requirement
      end

      # Extract plugin name from class
      # @param plugin_class [Class] The plugin class
      # @return [String] The plugin name
      def extract_plugin_name(plugin_class)
        if plugin_class.respond_to?(:plugin_name)
          plugin_class.plugin_name.to_s
        else
          plugin_class.name || "Unknown"
        end
      end

      # Parse the requirement string into a Gem::Requirement
      # @return [Gem::Requirement] The parsed requirement
      def requirement
        Gem::Requirement.new(@requirement_string)
      end

      # Get the current rack-fts version as a Gem::Version
      # @return [Gem::Version] Current version
      def current_version
        Gem::Version.new(VERSION)
      end

      # Log a warning about incompatibility
      def warn_incompatible
        logger = Configuration.instance.logger
        if logger
          logger.warn(error_message)
        elsif defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn(error_message)
        else
          Kernel.warn("[rack-fts] WARNING: #{error_message}")
        end
      end
    end
  end
end
