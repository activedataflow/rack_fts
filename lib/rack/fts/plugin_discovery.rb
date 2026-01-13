# frozen_string_literal: true

module Rack
  module FTS
    # Scans configured directories and loads plugin classes.
    #
    # Plugin discovery follows these rules:
    # - Scans directories listed in Configuration.instance.plugin_directories
    # - Looks for files matching *_plugin.rb pattern
    # - Validates version compatibility
    # - Sorts by priority (higher priority checked first)
    # - Registers discovered plugins in the route_handlers configuration
    #
    # @example Triggering discovery
    #   PluginDiscovery.scan_and_register!
    #
    # @example Manual discovery without registration
    #   discovery = PluginDiscovery.new
    #   plugins = discovery.discover
    class PluginDiscovery
      # File pattern for plugin files
      PLUGIN_FILE_PATTERN = "*_plugin.rb"

      class << self
        # Scan directories and register all discovered plugins
        # @return [Array<Class>] The registered plugin classes
        def scan_and_register!
          new.scan_and_register!
        end

        # Discover plugins without registering them
        # @return [Array<Class>] The discovered plugin classes
        def discover
          new.discover
        end
      end

      # Scan and register all discovered plugins
      # @return [Array<Class>] The registered plugin classes
      def scan_and_register!
        discovered = discover
        validated = validate_versions(discovered)
        sorted = sort_by_priority(validated)
        register_plugins(sorted)
        sorted
      end

      # Discover plugins from configured directories
      # @return [Array<Class>] Array of discovered plugin classes
      def discover
        return [] if plugin_directories.empty?

        classes_before = route_base_subclasses
        load_plugin_files
        classes_after = route_base_subclasses

        # Return only newly loaded classes
        (classes_after - classes_before).select { |klass| valid_plugin?(klass) }
      end

      private

      # Get configured plugin directories
      # @return [Array<Pathname, String>] Directories to scan
      def plugin_directories
        Configuration.instance.plugin_directories || []
      end

      # Get all files matching the plugin pattern
      # @return [Array<String>] File paths
      def plugin_files
        plugin_directories.flat_map do |dir|
          pattern = File.join(dir.to_s, "**", PLUGIN_FILE_PATTERN)
          Dir.glob(pattern)
        end.uniq
      end

      # Load all plugin files
      def load_plugin_files
        plugin_files.each do |file|
          load_plugin_file(file)
        end
      end

      # Load a single plugin file
      # @param file [String] The file path to load
      def load_plugin_file(file)
        require file
      rescue LoadError => e
        log_error("Failed to load plugin file #{file}: #{e.message}")
      rescue StandardError => e
        log_error("Error loading plugin file #{file}: #{e.message}")
      end

      # Get all current RouteBase subclasses
      # @return [Array<Class>] RouteBase subclasses
      def route_base_subclasses
        ObjectSpace.each_object(Class).select do |klass|
          klass < RouteBase && klass != RouteBase
        end
      end

      # Check if a class is a valid plugin
      # @param klass [Class] The class to check
      # @return [Boolean] true if valid
      def valid_plugin?(klass)
        return false if klass.nil?
        return false unless klass.respond_to?(:route_pattern)
        return false if klass.route_pattern.nil?

        true
      end

      # Validate version compatibility for all plugins
      # @param plugins [Array<Class>] Plugin classes to validate
      # @return [Array<Class>] Validated plugin classes
      def validate_versions(plugins)
        plugins.select do |plugin|
          begin
            VersionChecker.check!(plugin)
            true
          rescue VersionChecker::IncompatibleVersionError
            false
          end
        end
      end

      # Sort plugins by priority (highest first)
      # @param plugins [Array<Class>] Plugin classes to sort
      # @return [Array<Class>] Sorted plugin classes
      def sort_by_priority(plugins)
        plugins.sort_by do |plugin|
          priority = plugin.respond_to?(:priority) ? plugin.priority : 0
          -(priority || 0)
        end
      end

      # Register plugins in configuration
      # @param plugins [Array<Class>] Plugin classes to register
      def register_plugins(plugins)
        existing = Configuration.instance.route_handlers || []
        new_plugins = plugins - existing
        Configuration.instance.route_handlers = existing + new_plugins

        # Also register in the registry for introspection
        new_plugins.each do |plugin|
          PluginRegistry.instance.register(plugin)
        end
      end

      # Log an error message
      # @param message [String] The error message
      def log_error(message)
        logger = Configuration.instance.logger
        if logger
          logger.error("[rack-fts] #{message}")
        elsif defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error("[rack-fts] #{message}")
        else
          Kernel.warn("[rack-fts] ERROR: #{message}")
        end
      end
    end
  end
end
