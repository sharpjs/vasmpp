# frozen_string_literal: true
# encoding: utf-8
#
# RAS - Ruby ASsembler
# Copyright (C) 2019 Jeffrey Sharp
#
# RAS is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# RAS is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See
# the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with RAS.  If not, see <http://www.gnu.org/licenses/>.

module RAS

  # ----------------------------------------------------------------------------
  # Refinements

  # refine Object do
  # end

  #using self # Activate refinements

  # ----------------------------------------------------------------------------
  # Context

  class CleanObject < BasicObject
    # public  methods: __send__, __eval__, __exec__, __id__
    # private methods: initialize, method_missing, singleton_method_added,
    #                  singleton_method_removed, singleton_method_undefined

    define_method :__send__, ::Object.instance_method(:public_send)
    define_method :__eval__,          instance_method(:instance_eval)
    define_method :__exec__,          instance_method(:instance_exec)

    undef_method :!, :!=, :==, :equal?, :instance_eval, :instance_exec

    freeze
  end

  class Sandbox < CleanObject
    undef_method :__id__
    private

    def initialize(context)
      raise "required: context" unless CleanObject === context
      @__context__ = context
    end

    def method_missing(name, *args, &block)
      # Redirect all invocations to internal context.
      @__context__.__send__(name, *args, &block)
    end

    def respond_to_missing?(name, all)
      # Redirect all invocations to internal context.
      @__context__.respond_to?(name, false)
    end

    def self.const_missing(name)
      # Make 'uninitialized constant' errors prettier.
      ::Object.const_get(name)
    end
  end

  class Context < CleanObject
    def initialize(out, parent, name)
      @out     = out
      @parent  = parent
     #@name    = parent&.__symbol__(name, :hidden)
      @aliases = AliasMap.new #parent&.@aliases

      @symbols    = {}
      @local_num  = -1
      @visibility = :local
    end

    ##
    # Evaluates the given ruby code in the context.
    #
    def eval(ruby, name="(stdin)", line=1)
      case ruby
      when ::Proc then Sandbox.new(self).__eval__(&ruby)
      else             Sandbox.new(self).__eval__(ruby, name, line)
      end
    end

    def my
      @aliases
    end

    def print *xs, prefix: nil
      loc = source_location
      $stderr.puts *xs.map { |x| "#{loc}: #{prefix}#{x}" }
    end

    def warning *xs
      print *xs, prefix: "WARNING: "
    end

    def error msg
      print msg, prefix: "ERROR: "
      ::Kernel.raise Error, msg
    end

    protected

    def int(val, bits)
      case val = ::Kernel.Integer(val)
      when -128..255 then val
      else ::Kernel.raise ::RangeError, "#{val} does not fit into #{bits} bits"
      end
    end

    private

    def source_location
      dir  = ::File.join(::Kernel.__dir__, "")
      locs = ::Kernel.caller_locations
      loc  = locs.find { |l| !l.absolute_path.start_with?(dir) } || locs[0]
      "#{loc.path}:#{loc.lineno}"
    end
  end

  ##
  # The top-level context.
  #
  # In a top-level context, symbols are file-scoped by default and can be made
  # global via the +global+ directive.
  #
  class TopLevel < Context
    def initialize(out)
      super(out, nil, nil)
      @visibility = :public
    end

    ##
    # Sets symbol visibility to public.
    def public #(*syms)
      @visibility = :public
    end

    ##
    # Sets symbol visibility to private.
    def private #(*syms)
      @visibility = :private
    end
  end

  # ----------------------------------------------------------------------------
  # 

  ##
  # A one-to-one map for expression aliases.
  #
  class AliasMap < CleanObject
    ##
    # Creates a new alias map as a child of +parent+.
    #
    def initialize(parent = nil)
      @parent = parent
      @k2v    = {} # key -> val (an alias has only one meaning)
      @v2k    = {} # val -> key (a meaning has only one alias)
    end

    def has_key?(key)
      @k2v.has_key?(key) || @parent&.has_key?(key) 
    end

    def [](key)
      @k2v[key] || @parent&.[](key)
    end

    def []=(key, val)
      @v2k.delete(@k2v[key]) # Remove map: new key <- old val
      @k2v.delete(@v2k[val]) # Remove map: old key -> new val
      @k2v[key] = val
      @v2k[val] = key
      val
    end

    private

    ALIAS_RE = /^([_[:lower:]][_[:alnum:]]*)(=)?$/

    def method_missing(name, *args, &block)
      if name !~ ALIAS_RE
        super
      elsif $2 # assignment
        __send__(:[]=, $1.to_sym, *args)
      else # reference
        __send__(:[], name, *args) or super
      end
    end

    def respond_to_missing?(name, all)
      name =~ ALIAS_RE and $2 || has_key?(name)
    end
  end

  class Output
    attr :sections

    def initialize
      @sections = []
    end
  end

  class Section
    attr :name, :flags, :content
  end

  class ByteSection < Section
    def initialize(name)
      @content = "".b
    end

    def data8(*xs)
      @content << xs.pack("C")
    end
  end

  class BigEndianSection < ByteSection
    def data16(*xs)
      @content << xs.pack("S>") # big endian
    end

    def data32(*xs)
      @content << xs.pack("L>") # big endian
    end

    def data64(*xs)
      @content << xs.pack("Q>") # big endian
    end
  end

  class LittleEndianSection < ByteSection
    def data16(*xs)
      @content << xs.pack("S<") # big endian
    end

    def data32(*xs)
      @content << xs.pack("L<") # big endian
    end

    def data64(*xs)
      @content << xs.pack("Q<") # big endian
    end
  end

  class WordSection < Section
    def initialize(name)
      @content = []
    end

    def data(*xs)
      @content << xs.map(&::Kernel.Integer)
    end
  end

  class Error < RuntimeError
    def location
      backtrace_locations
    end
  end

end # module RAS

#require_relative 'arch-cf'
#require_relative 'syntax-mot'

