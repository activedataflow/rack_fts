# frozen_string_literal: true

require "singleton"

module Rack
  module FTS
    # Central registry for all FTS plugins with metadata for introspection.
    #
    # The registry maintains information about all registered plugins including
    # their version, requirements, and relationships.
    #
    # @example Registering a plugin
    #   PluginRegistry.instance.register(MyPlugin)
    #
    # @example Finding a plugin
    #   PluginRegistry.instance.find(:my_plugin)
    #
    # @example Listing all plugins
    #   PluginRegistry.instance.all
    class PluginRegistry
      include Singleton

      # @return [Hash{Symbol => Hash}] All registered plugins keyed by name
      attr_reader :plugins

      def initialize
        @plugins = {}
        @load_order = []
        @mutex = Mutex.new
      end

      # Register a plugin class in the registry
      # @param plugin_class [Class] The plugin class to register
      # @return [Hash] The plugin metadata
      def register(plugin_class)
        @mutex.synchronize do
          name = extract_plugin_name(plugin_class)
          metadata = build_metadata(plugin_class)
          @plugins[name] = metadata
          @load_order << name unless @load_order.include?(name)
          metadata
        end
      end

      # Unregister a plugin from the registry
      # @param name [Symbol, String] The plugin name
      # @return [Hash, nil] The removed plugin metadata or nil
      def unregister(name)
        @mutex.synchronize do
          name_sym = name.to_sym
          @load_order.delete(name_sym)
          @plugins.delete(name_sym)
        end
      end

      # Find a plugin by name
      # @param name [Symbol, String] The plugin name
      # @return [Hash, nil] The plugin metadata or nil if not found
      def find(name)
        @plugins[name.to_sym]
      end

      # Check if a plugin is registered
      # @param name [Symbol, String] The plugin name
      # @return [Boolean] true if registered
      def registered?(name)
        @plugins.key?(name.to_sym)
      end

      # Get all registered plugins in load order
      # @return [Array<Hash>] Array of plugin metadata
      def all
        @load_order.map { |name| @plugins[name] }
      end

      # Get all enabled plugins (based on ENV configuration)
      # @return [Array<Hash>] Array of enabled plugin metadata
      def enabled_plugins
        all.select do |plugin|
          plugin[:class].respond_to?(:env) && plugin[:class].env.enabled?
        end
      end

      # Get all disabled plugins
      # @return [Array<Hash>] Array of disabled plugin metadata
      def disabled_plugins
        all.reject do |plugin|
          plugin[:class].respond_to?(:env) && plugin[:class].env.enabled?
        end
      end

      # Get plugins sorted by priority (highest first)
      # @return [Array<Hash>] Array of plugin metadata sorted by priority
      def by_priority
        all.sort_by { |p| -(p[:priority] || 0) }
      end

      # Clear all registered plugins
      def clear!
        @mutex.synchronize do
          @plugins.clear
          @load_order.clear
        end
      end

      # Get count of registered plugins
      # @return [Integer] Number of registered plugins
      def count
        @plugins.size
      end

      # Iterate over all plugins
      # @yield [name, metadata] Each plugin name and metadata
      def each(&block)
        @load_order.each do |name|
          block.call(name, @plugins[name])
        end
      end

      private

      # Extract plugin name from class
      # @param plugin_class [Class] The plugin class
      # @return [Symbol] The plugin name
      def extract_plugin_name(plugin_class)
        if plugin_class.respond_to?(:plugin_name)
          plugin_class.plugin_name.to_sym
        else
          demodulize(plugin_class.name || "unknown").underscore.to_sym
        end
      end

      # Build metadata hash for a plugin
      # @param plugin_class [Class] The plugin class
      # @return [Hash] The plugin metadata
      def build_metadata(plugin_class)
        {
          class: plugin_class,
          name: extract_plugin_name(plugin_class),
          version: extract_version(plugin_class),
          rack_fts_requirement: extract_requirement(plugin_class),
          priority: extract_priority(plugin_class),
          route_pattern: extract_route_pattern(plugin_class),
          http_methods: extract_http_methods(plugin_class),
          mounted_plugins: extract_mounted_plugins(plugin_class),
          registered_at: Time.now
        }
      end

      # Extract version from plugin class
      def extract_version(plugin_class)
        return "0.0.0" unless plugin_class.respond_to?(:plugin_version)

        plugin_class.plugin_version || "0.0.0"
      end

      # Extract rack-fts version requirement
      def extract_requirement(plugin_class)
        return nil unless plugin_class.respond_to?(:rack_fts_version_requirement)

        plugin_class.rack_fts_version_requirement
      end

      # Extract priority from plugin class
      def extract_priority(plugin_class)
        return 0 unless plugin_class.respond_to?(:priority)

        plugin_class.priority || 0
      end

      # Extract route pattern from plugin class
      def extract_route_pattern(plugin_class)
        return nil unless plugin_class.respond_to?(:route_pattern)

        plugin_class.route_pattern
      end

      # Extract HTTP methods from plugin class
      def extract_http_methods(plugin_class)
        return [] unless plugin_class.respond_to?(:http_methods)

        plugin_class.http_methods || []
      end

      # Extract mounted sub-plugins
      def extract_mounted_plugins(plugin_class)
        return [] unless plugin_class.respond_to?(:mounted_plugins)

        plugin_class.mounted_plugins || []
      end

      # Simple demodulize (without ActiveSupport dependency)
      def demodulize(path)
        path.to_s.split("::").last || path.to_s
      end
    end
  end
end
