#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true
#
# aspp - Assembly Preprocessor in Ruby
# Copyright (C) 2016 Jeffrey Sharp
#
# aspp is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# aspp is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See
# the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with aspp.  If not, see <http://www.gnu.org/licenses/>.
#
# FEATURES
#
# - Global labels
#
#     foo::             foo: .global foo
#
# - Local labels
#
#     .foo:             L(foo)
#
# - Label macro invocation
#
#     foo:              .label foo
#
# - Local symbol scopes
#
#     foo: {            .label foo
#       ...             #define scope foo
#       ...
#     }                 #undef scope
#
# - Local aliases
#
#     op  foo = a0      _(foo)a0
#     op  foo           _(foo)a0
#     op  bar = a0      _(bar)a0    // undefines foo
#
# - Square brackets for indirect addressing
#
#     [8, fp]           (8, fp)
#
# - Immediate-mode prefix removal for macros
#
#     cmp$.l #4, d0     cmp$.l _(#)4, d0
#
# - Predefined macros
#
#     .macro .label name:req          // default .macro label
#       \name\():
#     .endm
#
#     #define _(x)                    // inline comment
#     #define L(name) .L$scope$name   // reference to local symbol
#

module Aspp
  class Processor
    def initialize(file)
      @file    = file         # source file name
      @line    = 1            # line number in source file
      @bol     = true         # if at beginning of line in output

      @aliases = Aliases.new  # identifier aliases
      @scopes  = []           # scope name stack
      @gensym  = 0            # number of next anonymous scope

      print Aspp::preamble(file)
      sync
    end

    def process(input)
      input.scan(STATEMENT) do |ws, name, colon, args, rest, brace|
        if    colon then on_label      ws, name, colon
        elsif args  then on_statement  ws, name, args, rest
        elsif brace then on_block      brace
        else             on_other      $&
        end

        @line += $&.count("\n")
      end
    end

    private

    WS   = %r{ (?: [ \t] | \\\n )++ }x
    ID   = %r{ (?!\d) [\w.$]++ }x
    STR  = %r{ " (?: [^\\"] | \\.?+ )*+ "?+ }x
    ARGS = %r{ (?: #{STR} | /(?!/) | \\.?+ | [^/\n;] )*+ }x

    STATEMENT = %r< \G
      (#{WS})?+
      (?:
        (?# label or op #)
        (#{ID})
        (?: (::?+) | (#{ARGS}) ( ; | (?://.*+)?+ \n?+ ) )
      |
        (?# block begin or end #)
        ({|})
      |
        (?# unrecognized #)
        .*+ \n?+
      )
    >x

    SPECIAL = %r{
      (?:
        (?# identifier or alias #)
        (#{ID}) (?: #{WS}?+ = #{WS}?+ (#{ID}) )?+
      |
        (?# chars with special handling #)
        [\[\]\#]
      | 
        (?# string #)
        #{STR}
      )
    }x

    def on_label(ws, name, sigil)
      if local?(name)
        print ws, localize(name), ":"
      else
        print ws, ".label ", name, ";"
      end

      if global?(sigil)
        print " .global ", name, ";"
      end

      @label = name
      @bol   = false
    end

    def on_statement(ws, name, args, rest)
      pseudo = pseudo?(name)

      args.gsub!(SPECIAL) do |s|
        case s[0]
        when "["  then "("
        when "]"  then ")"
        when "#"  then pseudo ? "_(#)" : "#"
        when '"'  then s
        else           on_identifier $1, $2
        end
      end

      print ws, name, args, rest

      @label = nil
      @bol   = rest.end_with?("\n")
    end

    def on_block(char)
      case char
      when '{'
        old      = @scopes.last
        new      = @label || gensym
        @aliases = Aliases.new(@aliases)
        @scopes.push old ? "#{old}$#{new}" : new
      when '}'
        old      = @scopes.pop
        new      = @scopes.last
        @aliases = @aliases.parent
      end

      puts unless @bol
      puts
      puts "#undef scope"         if old
      puts "#define scope #{new}" if new
      sync

      @label = nil
      @bol   = true
    end

    def on_other(line)
      print line
      @bol = true
    end

    def on_identifier(id, val)
      name = if val
               @aliases[id] = val
             else
               val = @aliases[id] or id
             end

      name = localize(name) if local?(name)

      val ? "_(#{id})#{name}" : name
    end

    def sync
      puts "# #{@line} \"#{@file}\""
    end

    def local?(id)
      id.start_with?(".")
    end

    def localize(id)
      "L(#{id[1..-1]})"
    end

    def global?(sigil)
      sigil == "::"
    end

    def gensym
      @gensym.tap { @gensym += 1 }
    end

    def pseudo?(id)
      id.start_with?(".") || id.include?("$")
    end
  end # Processor

  def self.preamble(name)
    <<~EOS
      # 1 "(ampp-preamble)"
      .macro .label name:req                  // default label macro:
        \\name\\():                             //   just emit a label
      .endm

      #define _(x)                            // inline comment
      #define L(name)        .L$scope$name    // local symbol in current scope
      #define S(scope, name) .L$scope$name    // local symbol in given   scope

    EOS
  end

  # A scope for aliases:
  # - An alias/key maps to a value.
  # - One value has one alias/key.
  # - On insert conflicts, older mappings are deleted.
  # - A child scope overrides its parent.
  #
  class Aliases
    attr_reader :parent

    def initialize(parent = nil)
      @parent = parent
      @k2v    = {}
      @v2k    = {}
    end

    def [](key)
      @k2v[key] or @parent &.[] key
    end

    def []=(key, val)
      @v2k.delete(@k2v[key]) # Remove map: new key <- old val
      @k2v.delete(@v2k[val]) # Remove map: old key -> new val
      @k2v[key] = val
      @v2k[val] = key
      val
    end
  end
end # Aspp

if __FILE__ == $0
  # Running as script
  trap "PIPE", "SYSTEM_DEFAULT"
  loop do
    Aspp::Processor
      .new(ARGF.filename)
      .process(ARGF.file.read)
    ARGF.skip
    break if ARGV.empty?
  end
end

