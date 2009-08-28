require './spec/spec_helper.rb'
require 'rubish/pipeline'

require 'stringio'
require 'tempfile'

include Rubish::Pipeline


describe Rubish::Pipeline do
  describe ".sys" do
    DOUBLE_CHARS_CMD = ['ruby', 'spec/bin/double_chars']

    if RUBY_PLATFORM =~ /-(mswin|mingw)/
      TRUE_CMD = [ENV['COMSPEC'], '/C', 'exit 0']
      FAIL_CMD = [ENV['COMSPEC'], '/C', 'exit 1']
      ECHO_CMD = [ENV['COMSPEC'], '/C', 'echo hello world']
      PWD_CMD = [ENV['COMSPEC'], '/C', 'cd']
      CAT_CMD = DOUBLE_CHARS_CMD
    else
      TRUE_CMD = ['true']
      FAIL_CMD = ['false']
      ECHO_CMD = ['echo', 'hello', 'world']
      PWD_CMD = ['pwd']
      CAT_CMD = ['cat']
    end

    it "should return one process status for one command" do
      status = sys(*TRUE_CMD)
      status.size.should == 1
    end

    it "should return a process status" do
      status = sys(*TRUE_CMD)
      status[0].is_a?(Process::Status).should be_true
    end

    it "should succeed to run a given command" do
      status = sys(*TRUE_CMD)
      status[0].success?.should be_true
    end

    it "should succeed to report failure of a failed command" do
      status = sys(*FAIL_CMD)
      status[0].success?.should be_false
    end

    it "should be able to redirect output into a StringIO" do
      io = StringIO.new
      sys(*ECHO_CMD + [{:stdout => io}])
      io.string.should == "hello world\n"
    end

    it "should be able to redirect output into a File" do
      Tempfile.new('tmp') do |io|
        sys(*ECHO_CMD + [{:stdout => io}])
        File.read(io.path).should == "hello world\n"
      end
    end

    it "should return two process statuses for two commands" do
      status = sys(*TRUE_CMD + [{:stdout => [*TRUE_CMD]}])
      status.size.should == 2
    end

    it "should return the correct status for each command" do
      status = sys(*TRUE_CMD + [{:stdout => [*FAIL_CMD]}])
      status[0].success?.should be_true
      status[1].success?.should be_false
    end

    it "should accept input from a StringIO" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys(*CAT_CMD + [{:stdin => input, :stdout => output}])
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "should pipe output from one command to the next" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys(*CAT_CMD + [{:stdin => input, :stdout =>
          [*DOUBLE_CHARS_CMD + ['a', 'e', 'i', 'o', 'u', {:stdout => output}]]}])
      output.string.should ==
          "Thee quiick broown foox juumpeed ooveer thee laazy doog\n"
    end
  end
end
