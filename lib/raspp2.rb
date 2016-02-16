#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true
#
# raspp.rb - Assembly Preprocessor in Ruby
# Copyright (C) 2016 Jeffrey Sharp
#
# FEATURES:
#
# Function Labels
#
#   foo():  -->  #declare SCOPE foo
#               .fn SCOPE
#
#

module Raspp
  def self.process(input, file = "(stdin)", line = 1)
    input.gsub!(MACROS) do
      p $~
      if (text = $~[:skip])
        text
      elsif (text = $~[:fn])
        "#define SCOPE #{text}\n" +
        ".fn SCOPE\n"
      end
    end
    print input
  end

  private

  ID   = / [a-zA-Z._$][a-zA-Z0-9._$]*  /mx
  CHAR = / ' (?: [^\\'] | \\.?+ )*+ '? /mx
  STR  = / " (?: [^\\"] | \\.?+ )*+ "? /mx
  RUBY = / ` (?: [^`]           )*+ `? /mx

  EOL  = / \n | \r\n?      /x
  EOLF = / \n | \r\n? | \z /x

  WS   = / [ \t]   | \\ #{EOL} /x
  ANY  = / [^\r\n] | \\ #{EOL} /x

  MACROS =
  / (?<skip> #{STR}         (?# double-quoted string   )
           | ^ \# #{ANY}*+  (?# preprocessor directive )
    )
  | (?: ^ (?<fn>#{ID}) \(\): )
  /mx

end

if __FILE__ == $0
  # Running as script
  trap "PIPE", "SYSTEM_DEFAULT"
  loop do
    Raspp::process(ARGF.file.read, ARGF.filename)
    ARGF.skip
    break if ARGV.empty?
  end
end

