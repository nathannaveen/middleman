# frozen_string_literal: true

require 'monitor'
require 'middleman-core/core_extensions/collections/pagination'
require 'middleman-core/core_extensions/collections/step_context'
require 'middleman-core/core_extensions/collections/lazy_root'
require 'middleman-core/core_extensions/collections/lazy_step'

# Super "class-y" injection of array helpers
class Array
  include Middleman::Pagination::ArrayHelpers
end

module Middleman
  module CoreExtensions
    module Collections
      class CollectionsExtension < Extension
        # This should run after most other sitemap manipulators so that it
        # gets a chance to modify any new resources that get added.
        self.resource_list_manipulator_priority = 110

        attr_accessor :leaves

        # Expose `resources`, `data`, and `collection` to config.
        expose_to_config resources: :sitemap_collector,
                         data: :data_collector,
                         collection: :register_collector,
                         live: :live_collector

        # Exposes `collection` to templates
        expose_to_template collection: :collector_value

        helpers do
          def pagination
            current_resource.data.pagination
          end
        end

        def initialize(app, options_hash = ::Middleman::EMPTY_HASH, &block)
          super

          @leaves = Set.new
          @collectors_by_name = {}
          @values_by_name = {}

          @collector_roots = []

          @lock = Monitor.new
        end

        def before_configuration
          @leaves.clear
        end

        def register_collector(label, endpoint)
          @collectors_by_name[label] = endpoint
        end

        def sitemap_collector
          live_collector { |_, resources| resources.to_a }
        end

        def data_collector
          live_collector { |app, _| app.data }
        end

        def live_collector(&block)
          root = LazyCollectorRoot.new(self)

          @collector_roots << {
            root: root,
            block: block
          }

          root
        end

        Contract Symbol => Any
        def collector_value(label)
          @values_by_name[label]
        end

        Contract IsA['Middleman::Sitemap::ResourceListContainer'] => Any
        def manipulate_resource_list_container!(resource_list)
          @lock.synchronize do
            @collector_roots.each do |pair|
              dataset = pair[:block].call(app, resource_list)
              pair[:root].realize!(dataset)
            end

            ctx = StepContext.new(app)
            StepContext.current = ctx

            leaves = @leaves.dup

            @collectors_by_name.each do |k, v|
              @values_by_name[k] = v.value(ctx)
              leaves.delete v
            end

            # Execute code paths
            leaves.each do |v|
              v.value(ctx)
            end

            # Inject descriptors
            ctx.descriptors.each do |d|
              d.execute_descriptor(app, resource_list)
            end

            StepContext.current = nil
          end
        end
      end
    end
  end
end
