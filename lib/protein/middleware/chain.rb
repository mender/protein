module Protein
  module Middleware
    class Chain
      attr_reader :entries

      def initialize
        @entries = []
        yield self if block_given?
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
        @chain = nil
        entries
      end

      def add(klass, *args)
        entries << Entry.new(klass, *args) unless exists?(klass)
        @chain = nil
        entries
      end

      def exists?(klass)
        entries.any? { |entry| entry.klass == klass }
      end

      def retrieve
        @chain ||= entries.map(&:make_new)
      end

      def clear
        entries.clear
      end

      def invoke(*args, &final_action)
        chain   = retrieve
        current = 0
        traverse_chain = lambda do
          if chain[current].nil?
            final_action.call
          else
            current += 1
            chain[current-1].call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    class Entry
      attr_reader :klass
      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
