# frozen_string_literal: true

module Rack
  module FTS
    # Rails Engine for Rack-FTS plugin discovery and initialization.
    #
    # This engine provides Rails integration with proper lifecycle hooks for:
    # - Automatic plugin discovery from configured directories
    # - Plugin registration during Rails initialization
    # - Router middleware insertion
    #
    # @example Configuration in Rails initializer
    #   # config/initializers/rack_fts.rb
    #   Rack::FTS.configure do |config|
    #     config.plugin_directories = [
    #       Rails.root.join("app/fts_plugins"),
    #       Rails.root.join("lib/fts_plugins")
    #     ]
    #     config.auto_discover = true
    #     config.version_check_mode = :warn
    #   end
    #
    # @example Directory structure
    #   app/
    #   └── fts_plugins/
    #       ├── health_plugin.rb
    #       └── api_docs_plugin.rb
    class Engine < ::Rails::Engine
      isolate_namespace Rack::FTS

      # Configuration options accessible via Rails config
      config.rack_fts = ActiveSupport::OrderedOptions.new
      config.rack_fts.plugin_directories = nil # Will use defaults if nil
      config.rack_fts.auto_discover = true
      config.rack_fts.insert_router = true

      # Set default plugin directories before loading initializers
      initializer "rack_fts.configure", before: :load_config_initializers do |app|
        # Set default directories relative to Rails.root if not configured
        if config.rack_fts.plugin_directories.nil?
          config.rack_fts.plugin_directories = %w[app/fts_plugins lib/fts_plugins]
        end

        # Convert to full paths and update configuration
        full_paths = config.rack_fts.plugin_directories.map do |dir|
          app.root.join(dir)
        end.select(&:exist?)

        Configuration.instance.plugin_directories = full_paths
      end

      # Discover and register plugins after user initializers have run
      initializer "rack_fts.discover_plugins", after: :load_config_initializers do |_app|
        if config.rack_fts.auto_discover && Configuration.instance.auto_discover
          begin
            PluginDiscovery.scan_and_register!
          rescue StandardError => e
            Rails.logger.error("[rack-fts] Plugin discovery failed: #{e.message}")
            Rails.logger.error(e.backtrace.first(10).join("\n")) if Rails.logger.debug?
          end
        end
      end

      # Insert router middleware if configured
      initializer "rack_fts.insert_router" do |app|
        if config.rack_fts.insert_router
          # Insert before ShowExceptions to catch RoutingError
          app.middleware.insert_before(
            ActionDispatch::ShowExceptions,
            Rack::FTS::Router
          )
        end
      end

      # Log initialization summary in development
      config.after_initialize do
        if Rails.env.development?
          plugin_count = Configuration.instance.route_handlers.size
          if plugin_count.positive?
            Rails.logger.info(
              "[rack-fts] Initialized with #{plugin_count} plugin(s): " \
              "#{Configuration.instance.route_handlers.map { |h| h.respond_to?(:plugin_name) ? h.plugin_name : h.name }.join(', ')}"
            )
          end
        end
      end
    end
  end
end
