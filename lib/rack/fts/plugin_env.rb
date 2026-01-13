# frozen_string_literal: true

module Rack
  module FTS
    # Provides namespaced ENV variable access for plugins.
    #
    # Each plugin gets its own ENV namespace following the pattern:
    #   RACK_FTS_{PLUGIN_NAME}_{SETTING}
    #
    # @example Usage in a plugin
    #   class MetricsPlugin < Rack::FTS::RouteBase
    #     plugin_name :metrics
    #
    #     def some_method
    #       timeout = env.get(:timeout, default: "30")
    #       format = env.get(:format, default: "json")
    #     end
    #   end
    #
    # @example ENV variables
    #   RACK_FTS_METRICS_ENABLED=true
    #   RACK_FTS_METRICS_TIMEOUT=60
    #   RACK_FTS_METRICS_FORMAT=prometheus
    class PluginEnv
      # @param plugin_name [Symbol, String] The plugin name used for ENV prefix
      def initialize(plugin_name)
        @prefix = "RACK_FTS_#{plugin_name.to_s.upcase}"
      end

      # Get an ENV variable value for this plugin
      # @param key [Symbol, String] The setting key (without prefix)
      # @param default [String, nil] Default value if ENV variable not set
      # @return [String, nil] The ENV variable value or default
      def get(key, default: nil)
        ENV.fetch("#{@prefix}_#{key.to_s.upcase}", default)
      end

      # Check if this plugin is enabled via ENV
      # Defaults to true if RACK_FTS_{NAME}_ENABLED is not set
      # @return [Boolean] true if enabled
      def enabled?
        value = get(:enabled, default: "true")
        value.to_s.downcase == "true"
      end

      # Check if this plugin is disabled via ENV
      # @return [Boolean] true if disabled
      def disabled?
        !enabled?
      end

      # Get all ENV variables for this plugin as a hash
      # @return [Hash{Symbol => String}] ENV variables with prefix stripped
      def to_h
        ENV.select { |k, _| k.start_with?(@prefix) }
           .transform_keys { |k| k.sub("#{@prefix}_", "").downcase.to_sym }
      end

      # Check if a specific setting is set (not nil or empty)
      # @param key [Symbol, String] The setting key
      # @return [Boolean] true if the setting has a value
      def set?(key)
        value = get(key)
        !value.nil? && !value.empty?
      end

      # Get an integer value from ENV
      # @param key [Symbol, String] The setting key
      # @param default [Integer] Default value if not set or invalid
      # @return [Integer] The parsed integer value
      def get_int(key, default: 0)
        value = get(key)
        return default if value.nil? || value.empty?

        Integer(value)
      rescue ArgumentError
        default
      end

      # Get a boolean value from ENV
      # @param key [Symbol, String] The setting key
      # @param default [Boolean] Default value if not set
      # @return [Boolean] The parsed boolean value
      def get_bool(key, default: false)
        value = get(key)
        return default if value.nil? || value.empty?

        %w[true 1 yes on].include?(value.to_s.downcase)
      end

      # The ENV prefix for this plugin
      # @return [String] The prefix (e.g., "RACK_FTS_HEALTH")
      attr_reader :prefix
    end
  end
end
