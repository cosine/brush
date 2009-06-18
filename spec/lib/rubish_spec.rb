require './spec/spec_helper.rb'
require 'rubish'


describe Rubish::Shell do
  describe ".new" do
    it "should succeed" do
      proc { Rubish::Shell.new }.should_not raise_error
    end

    it "should succeed with an alternate input, output, error, and binding" do
      f = Array.new(3) { StringIO.new }
      proc { Rubish::Shell.new(f[0], f[1], f[2], binding) }.
          should_not raise_error
    end
  end

  describe ".start" do
    before :each do
      @f = Array.new(3) { StringIO.new }
      @sh = Rubish::Shell.new(@f[0], @f[1], @f[2])
    end

    it "should pass shell command input to system" do
      @f[0].string = "ls -l\n"
      @sh.should_receive(:system).with("ls -l")
      @sh.start
    end

    it "should pass Ruby code to eval" do
      @f[0].string = " @foo_bar = 12345\n"
      @sh.should_receive(:eval).with("@foo_bar = 12345", anything)
      @sh.start
    end

    it "should print a prompt" do
      @f[0].string = "ls -l\n"
      @sh.stub!(:system)
      @sh.start
      @f[1].string.should =~ %r"\A% "
    end

    it "should print the result of Ruby code evaled" do
      @f[0].string = " @foo_bar = 12345\n"
      @sh.start
      @f[1].string.should =~ %r"\#=> 12345\n\Z"
    end

    it "should print multi-line results using RPS2"
  end
end
