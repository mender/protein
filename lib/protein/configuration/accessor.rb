# encoding: utf-8
module Protein
  class Configuration
    module Accessor
      def config_accessor(name)
        define_setter(name)
        define_getter(name)
        nil
      end

      def define_setter(name)
        name = symbolize(name)
        define_method("#{name}=") do |value|
          raise Protein::ConfigurationError.new("Attempt to modify finalized configuration") if finalized?
          config[name] = value
        end
      end

      def define_getter(name)
        name = symbolize(name)
        define_method(name) do
          finalize
          config.fetch(name, default[name])
        end
      end

      protected

      def symbolize(name)
        name.to_s.to_sym
      end
    end
  end
end