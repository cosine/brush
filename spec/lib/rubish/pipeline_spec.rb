require './spec/spec_helper.rb'
require 'rubish/pipeline'

require 'stringio'

include Rubish::Pipeline


describe Rubish::Pipeline do
  describe ".sys" do
    if RUBY_PLATFORM =~ /-(mswin|mingw)/
      TRUE_CMD = [ENV['COMSPEC'], '/C', 'exit 0']
      FAIL_CMD = [ENV['COMSPEC'], '/C', 'exit 1']
      ECHO_CMD = [ENV['COMSPEC'], '/C', 'echo hello world']
      PWD_CMD = [ENV['COMSPEC'], '/C', 'cd']
    else
      TRUE_CMD = ['true']
      FAIL_CMD = ['false']
      ECHO_CMD = ['echo', 'hello', 'world']
      PWD_CMD = ['pwd']
    end

    it "should return a process status" do
      status = sys(*TRUE_CMD)
      status.is_a?(Process::Status).should be_true
    end

    it "should succeed to run a given command" do
      status = sys(*TRUE_CMD)
      status.success?.should be_true
    end

    it "should succeed to report failure of a failed command" do
      status = sys(*FAIL_CMD)
      status.success?.should be_false
    end

    it "should be able to redirect output into a StringIO" do
      io = StringIO.new
      sys(*ECHO_CMD + [{:stdout => io}])
      io.string.should == "hello world\n"
    end

    it "should be able to redirect output into a File"
  end
end
