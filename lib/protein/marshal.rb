# encoding: utf-8
require 'oj'

module Protein
  class Marshal
    def self.dump(data)
      Oj.dump(data)
    end
    
    def self.load(data)
      Oj.load(data)
    rescue
      nil
    end
  end
end
