
module Rubish
  class Shell
    DEFAULT_EXEC_MATCH = %r"^(\S.*)"
    DEFAULT_RUBY_MATCH = %r"^\s+(.*)"
    DEFAULT_PS1 = "% "
    DEFAULT_PS2 = "%-"
    DEFAULT_RPS1 = "\#=> "
    DEFAULT_RPS2 = "\# > "

    def initialize (inp = $stdin, out = $stdout, err = $stderr, binding = nil)
      @in, @out, @err = inp, out, err
      @exec_match = DEFAULT_EXEC_MATCH
      @ruby_match = DEFAULT_RUBY_MATCH
      @ps1, @ps2 = DEFAULT_PS1, DEFAULT_PS2
      @rps1, @rps2 = DEFAULT_RPS1, DEFAULT_RPS2
      @binding ||= binding
      @out.sync = true
      @err.sync = true
    end

    def start
      while not @in.eof?
        @out.print @ps1
        line = @in.gets.chomp
        if line =~ @ruby_match
          repl line[@ruby_match, 1]
        elsif line =~ @exec_match
          system line[@exec_match, 1]
        else
          repl line
        end
      end
    end

    def repl (code)
      result = eval(code, @binding)
      @out.puts "#{@rps1}#{result.inspect}"
    end
  end
end

