#
# Copyright (c) 2009, Michael H. Buselli
# See LICENSE for details on permitted use.
#

require './spec/spec_helper.rb'
require 'brush/pipeline'

require 'stringio'
require 'tempfile'
require 'timeout'

include Brush::Pipeline


describe Brush::Pipeline do

  # Brush::Pipeline#sys and Brush::Pipeline#pipeline are two interfaces
  # to the same thing.  Which one you use just depends on convenience.
  # Thus, they are tested together.
  #
  describe ".sys/pipeline" do

    DOUBLE_CHARS_CMD = ['ruby', 'spec/bin/double_chars', 'the']

    if RUBY_PLATFORM =~ /-(mswin|mingw)/
      TRUE_CMD = [ENV['COMSPEC'], '/C', 'exit 0']
      FAIL_CMD = [ENV['COMSPEC'], '/C', 'exit 1']
      ECHO_CMD = [ENV['COMSPEC'], '/C', 'echo hello world']
      PWD_CMD = [ENV['COMSPEC'], '/C', 'cd']
      CAT_CMD = DOUBLE_CHARS_CMD[0...2]
    else
      TRUE_CMD = ['true']
      FAIL_CMD = ['false']
      ECHO_CMD = ['echo', 'hello', 'world']
      PWD_CMD = ['pwd']
      CAT_CMD = ['cat']
    end


    # Call Brush::Pipeline#sys or Brush::Pipeline#pipeline and wait two
    # seconds before barfing.  It keeps the tests moving if something
    # gets stuck due to pipes not getting closed, though if triggered it
    # may leave unattached processes that need to be killed manually if
    # the un-closed pipe is in the same process waiting for it to be
    # closed.

    def sys_to (*args)
      Timeout.timeout(2) { sys(*args) }
    end

    def pipeline_to (*args)
      Timeout.timeout(2) { pipeline(*args) }
    end


    it "(sys) should return one process status for one command" do
      status = sys_to(*TRUE_CMD)
      status.size.should == 1
    end

    it "(pipeline) should return one process status for one command" do
      status = pipeline_to(TRUE_CMD)
      status.size.should == 1
    end

    it "(sys) should succeed to run a given command" do
      status = sys_to(*TRUE_CMD)
      status[0].success?.should be_true
    end

    it "(pipeline) should succeed to run a given command" do
      status = pipeline_to(TRUE_CMD)
      status[0].success?.should be_true
    end

    it "(sys) should succeed to report failure of a failed command" do
      status = sys_to(*FAIL_CMD)
      status[0].success?.should be_false
    end

    it "(pipeline) should succeed to report failure of a failed command" do
      status = pipeline_to(FAIL_CMD)
      status[0].success?.should be_false
    end

    it "(sys) should be able to redirect output into a StringIO" do
      io = StringIO.new
      sys_to(*ECHO_CMD + [{:stdout => io}])
      io.string.should == "hello world\n"
    end

    it "(pipeline) should be able to redirect output into a StringIO" do
      io = StringIO.new
      pipeline_to(ECHO_CMD, :stdout => io)
      io.string.should == "hello world\n"
    end

    it "(sys) should be able to redirect output into a File" do
      Tempfile.open('tmp') do |tmp|
        sys_to(*ECHO_CMD + [{:stdout => tmp}])
        File.read(tmp.path).should == "hello world\n"
      end
    end

    it "(pipeline) should be able to redirect output into a File" do
      Tempfile.open('tmp') do |tmp|
        pipeline_to(ECHO_CMD, :stdout => tmp)
        File.read(tmp.path).should == "hello world\n"
      end
    end

    it "(sys) should return two process statuses for two commands" do
      status = sys_to(*TRUE_CMD + [{:stdout => [*TRUE_CMD]}])
      status.size.should == 2
    end

    it "(pipeline) should return two process statuses for two commands" do
      status = pipeline_to(TRUE_CMD, TRUE_CMD)
      status.size.should == 2
    end

    it "(sys) should return the correct status for each command" do
      status = sys_to(*TRUE_CMD + [{:stdout => [*FAIL_CMD]}])
      status[0].success?.should be_true
      status[1].success?.should be_false
    end

    it "(pipeline) should return the correct status for each command" do
      status = pipeline_to(TRUE_CMD, FAIL_CMD)
      status[0].success?.should be_true
      status[1].success?.should be_false
    end

    it "(sys) should accept input from a StringIO (cat)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys_to(*CAT_CMD + [{:stdin => input, :stdout => output}])
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(pipeline) should accept input from a StringIO (cat)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      pipeline_to(CAT_CMD, :stdin => input, :stdout => output)
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(sys) should accept input from a StringIO (double chars)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys_to(*DOUBLE_CHARS_CMD + [{:stdin => input, :stdout => output}])
      output.string.should ==
          "The quick brown fox jumped over thethe lazy dog\n"
    end

    it "(pipeline) should accept input from a StringIO (double chars)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      pipeline_to(DOUBLE_CHARS_CMD, :stdin => input, :stdout => output)
      output.string.should ==
          "The quick brown fox jumped over thethe lazy dog\n"
    end

    it "(sys) should accept input from a File" do
      output = StringIO.new
      Tempfile.open('tmp') do |tmp|
        tmp.print("The quick brown fox jumped over the lazy dog\n")
        tmp.close
        File.open(tmp.path) do |f|
          sys_to(*CAT_CMD + [{:stdin => f, :stdout => output}])
        end
      end
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(pipeline) should accept input from a File" do
      output = StringIO.new
      Tempfile.open('tmp') do |tmp|
        tmp.print("The quick brown fox jumped over the lazy dog\n")
        tmp.close
        File.open(tmp.path) do |f|
          pipeline_to(CAT_CMD, :stdin => f, :stdout => output)
        end
      end
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(sys) should pipe output from one command to the next (cat)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys_to(*CAT_CMD + [{:stdin => input, :stdout =>
          [*CAT_CMD + [{:stdout => output}]]}])
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(pipeline) should pipe output from one command to the next (cat)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      pipeline_to(CAT_CMD, CAT_CMD, :stdin => input, :stdout => output)
      output.string.should == "The quick brown fox jumped over the lazy dog\n"
    end

    it "(sys) should pipe output from one command to the next (double chars)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      sys_to(*CAT_CMD + [{:stdin => input, :stdout =>
          [*DOUBLE_CHARS_CMD + [{:stdout => output}]]}])
      output.string.should ==
          "The quick brown fox jumped over thethe lazy dog\n"
    end

    it "(pipeline) should pipe output from one command to the next (double chars)" do
      input = StringIO.new("The quick brown fox jumped over the lazy dog\n")
      output = StringIO.new
      pipeline_to(CAT_CMD, DOUBLE_CHARS_CMD, :stdin => input, :stdout => output)
      output.string.should ==
          "The quick brown fox jumped over thethe lazy dog\n"
    end

    it "(sys) should return an overall status for a series of commands" do
      status = sys_to(*TRUE_CMD +
          [{:stdout => [*TRUE_CMD + [{:stdout => TRUE_CMD}]]}])
      status.success?.should be_true
    end

    it "(pipeline) should return an overall status for a series of commands" do
      status = pipeline_to(TRUE_CMD, TRUE_CMD, TRUE_CMD)
      status.success?.should be_true
    end

    it "(sys) should return a failed overall status if the first command fails" do
      status = sys_to(*FAIL_CMD +
          [{:stdout => [*TRUE_CMD + [{:stdout => TRUE_CMD}]]}])
      status.success?.should be_false
    end

    it "(pipeline) should return a failed overall status if the first command fails" do
      status = pipeline_to(FAIL_CMD, TRUE_CMD, TRUE_CMD)
      status.success?.should be_false
    end

    it "(sys) should return a failed overall status if a middle command fails" do
      status = sys_to(*TRUE_CMD +
          [{:stdout => [*FAIL_CMD + [{:stdout => TRUE_CMD}]]}])
      status.success?.should be_false
    end

    it "(pipeline) should return a failed overall status if a middle command fails" do
      status = pipeline_to(TRUE_CMD, FAIL_CMD, TRUE_CMD)
      status.success?.should be_false
    end

    it "(sys) should return a failed overall status if the last command fails" do
      status = sys_to(*TRUE_CMD +
          [{:stdout => [*TRUE_CMD + [{:stdout => FAIL_CMD}]]}])
      status.success?.should be_false
    end

    it "(pipeline) should return a failed overall status if the last command fails" do
      status = pipeline_to(TRUE_CMD, TRUE_CMD, FAIL_CMD)
      status.success?.should be_false
    end

    it "(sys) should return an overall value that quacks like a Process::Status" do
      status = sys_to(*TRUE_CMD +
          [{:stdout => [*TRUE_CMD + [{:stdout => TRUE_CMD}]]}])
      status.should quack_like_a(Process::Status)
    end

    it "(pipeline) should return an overall value that quacks like a Process::Status" do
      status = pipeline_to(TRUE_CMD, TRUE_CMD, TRUE_CMD)
      status.should quack_like_a(Process::Status)
    end

    it "(sys) should return an Array where every element quacks like a Process::Status" do
      status = sys_to(*TRUE_CMD +
          [{:stdout => [*TRUE_CMD + [{:stdout => TRUE_CMD}]]}])
      status.each { |elt| elt.should quack_like_a(Process::Status) }
    end

    it "(pipeline) should return an Array where every element quacks like a Process::Status" do
      status = pipeline_to(TRUE_CMD, TRUE_CMD, TRUE_CMD)
      status.each { |elt| elt.should quack_like_a(Process::Status) }
    end

  end
end
