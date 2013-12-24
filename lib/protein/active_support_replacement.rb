# encoding: utf-8
def delegate(*methods)
  options = methods.pop
  unless options.is_a?(Hash) && to = options[:to]
    raise ArgumentError, "Delegation needs a target. Supply an options hash with a :to key as the last argument (e.g. delegate :hello, :to => :greeter)."
  end
  prefix, to, allow_nil = options[:prefix], options[:to], options[:allow_nil]

  if prefix == true && to.to_s =~ /^[^a-z_]/
    raise ArgumentError, "Can only automatically set the delegation prefix when delegating to a method."
  end

  method_prefix =
    if prefix
      "#{prefix == true ? to : prefix}_"
    else
      ''
    end

  file, line = caller.first.split(':', 2)
  line = line.to_i

  methods.each do |method|
    method = method.to_s

    if allow_nil
      module_eval(<<-EOS, file, line - 2)
        def #{method_prefix}#{method}(*args, &block)        # def customer_name(*args, &block)
          if #{to} || #{to}.respond_to?(:#{method})         #   if client || client.respond_to?(:name)
            #{to}.__send__(:#{method}, *args, &block)       #     client.__send__(:name, *args, &block)
          end                                               #   end
        end                                                 # end
      EOS
    else
      exception = %(raise "#{self}##{method_prefix}#{method} delegated to #{to}.#{method}, but #{to} is nil: \#{self.inspect}")

      module_eval(<<-EOS, file, line - 1)
        def #{method_prefix}#{method}(*args, &block)        # def customer_name(*args, &block)
          #{to}.__send__(:#{method}, *args, &block)         #   client.__send__(:name, *args, &block)
        rescue NoMethodError                                # rescue NoMethodError
          if #{to}.nil?                                     #   if client.nil?
            #{exception}                                    #     # add helpful message to the exception
          else                                              #   else
            raise                                           #     raise
          end                                               #   end
        end                                                 # end
      EOS
    end
  end
end

# Wrapping a string in this class gives you a prettier way to test
# for equality. The value returned by <tt>Rails.env</tt> is wrapped
# in a StringInquirer object so instead of calling this:
#
#   Rails.env == 'production'
#
# you can call this:
#
#   Rails.env.production?
module Protein
  class StringInquirer < String
    private

      def respond_to_missing?(method_name, include_private = false)
        method_name[-1] == '?'
      end

      def method_missing(method_name, *arguments)
        if method_name[-1] == '?'
          self == method_name[0..-2]
        else
          super
        end
      end
  end
end

class Object
  # An object is blank if it's false, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} are all blank.
  #
  # This simplifies:
  #
  #   if address.nil? || address.empty?
  #
  # ...to:
  #
  #   if address.blank?
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  # An object is present if it's not <tt>blank?</tt>.
  def present?
    !blank?
  end

  # Returns object if it's <tt>present?</tt> otherwise returns +nil+.
  # <tt>object.presence</tt> is equivalent to <tt>object.present? ? object : nil</tt>.
  #
  # This is handy for any representation of objects where blank is the same
  # as not present at all. For example, this simplifies a common check for
  # HTTP POST/query parameters:
  #
  #   state   = params[:state]   if params[:state].present?
  #   country = params[:country] if params[:country].present?
  #   region  = state || country || 'US'
  #
  # ...becomes:
  #
  #   region = params[:state].presence || params[:country].presence || 'US'
  def presence
    self if present?
  end
end

class String
  # Converts the first character to uppercase and the remainder to lowercase.
  #
  # Example:
  #  'über'.mb_chars.capitalize.to_s # => "Über"
  def capitalize
    (slice(0) || chars('')).upcase + (slice(1..-1) || chars('')).downcase
  end

  # Ruby 1.9 introduces an inherit argument for Module#const_get and
  # #const_defined? and changes their default behavior.
  if Module.method(:const_get).arity == 1
    # Tries to find a constant with the name specified in the argument string:
    #
    #   "Module".constantize     # => Module
    #   "Test::Unit".constantize # => Test::Unit
    #
    # The name is assumed to be the one of a top-level constant, no matter whether
    # it starts with "::" or not. No lexical context is taken into account:
    #
    #   C = 'outside'
    #   module M
    #     C = 'inside'
    #     C               # => 'inside'
    #     "C".constantize # => 'outside', same as ::C
    #   end
    #
    # NameError is raised when the name is not in CamelCase or the constant is
    # unknown.
    def constantize
      names = split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end
  else
    def constantize #:nodoc:
      names = split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name, false) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end
  end
end