# -*- encoding : utf-8 -*-
require 'protein/strategy/base'
require 'protein/strategy/single'
require 'protein/strategy/multi'

module Protein::Strategy
  def self.create(type)
    "Protein::Strategy::#{type.to_s.camelize}".constantize.new
  end
end
