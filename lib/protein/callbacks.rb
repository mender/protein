# -*- encoding : utf-8 -*-
module Protein
  class Callbacks
    def define(name, &block)
      callbacks[name] << block
      nil
    end

    def fire(name, *args)
      name = name.to_sym
      if callbacks.key?(name)
        callbacks[name].each{|callback| callback.call(*args) }
      end
      nil
    end

    def names
      self.class.names
    end

    def self.names
      @names ||= [
        :after_start,
        :after_fork,
        :before_exit,
        :after_loop
      ]
    end

    names.each do |callback|
      define_method callback do |&block|
        define(callback, &block)
      end
    end

    protected

    def callbacks
      @callbacks ||= Hash.new do |hash, name| 
        hash[name] = []
      end  
    end
  end
end
