# -*- encoding : utf-8 -*-
module Protein
  if RUBY_VERSION < "1.9"
    require 'uuidtools'
    class Uuid
      def self.generate
        UUIDTools::UUID.random_create.to_s
      end
    end
  else
    class Uuid
      def self.generate
        SecureRandom.uuid
      end
    end
  end
end