module RSpec
  module Matchers
    class HaveJob
      include BaseMatcher

      def initialize(*args)
        super(args)
      end

      def matches?(actual)
        super(actual)

        raise NoMethodError.new("#{actual.inspect} does not respond to #have_job?") unless actual.respond_to?(:have_job?)

        actual.have_job?(*expected)
      end
    end

    # Passes if `actual.have_job?`
    #
    # @example
    #   bg.should have_job(:make_coffee)
    def have_job(*args)
      HaveJob.new(*args)
    end
  end
end