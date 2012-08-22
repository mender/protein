# -*- encoding : utf-8 -*-
module RSpec
  module Mocks
    # Methods that are added to every object.
    module Methods
      def should_enqueue_job
        Protein::Client.instance.should_receive(:queue_job!)
      end

      def should_not_enqueue_job
        Protein::Client.instance.should_not_receive(:queue_job!)
      end
    end
  end
end
