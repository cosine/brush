#
# Copyright (c) 2009, Michael H. Buselli
# See LICENSE for details on permitted use.
#

module Brush; end


module Brush::Pipeline

  #
  # Create and execute a pipeline consisting of commands.  Each
  # element of the pipeline is an array of command arguments and
  # options for that element of the pipeline.
  #
  # Options to each pipeline element include:
  #   :executable — specifies an alternative binary to run, instead of
  #   using the value for argv[0].
  #   :cd — change into this directory for this program.
  #   ---- probable future options
  #   :env — pass an alternative set of environment variables to the
  #   process.
  #   :stderr — file, pipe, or buffer to collect error information.
  #   :as_user — Array specifying user and credentials to run as.
  #
  # Options to the entire pipeline include:
  #   :stdin — file, pipe, or buffer to feed into the first element of
  #   the pipeline.
  #   :stdout — file, pipe, or buffer to collect the output of the
  #   last element of the pipeline.
  #
  # The return value is an Array reporting the success or failure of
  # each element of the pipeline.  Each element of the array is an
  # Object that emulates a Process::Status object.
  #
  # Example:
  #   extracted_files = String.new
  #   Brush::Pipeline.pipeline(
  #       ['gzip', '-cd', 'filename.tar.gz', :cd => 'Downloads'],
  #       ['tar', 'xvf', '-', :cd => 'Extractions'],
  #       :stdout => extracted_files)
  #
  def pipeline (*elements)
    options = {
      :stdin => $stdin,
      :stdout => $stdout
    }

    if elements[-1].respond_to?(:has_key?)
      options.merge!(elements.pop)
    end

    if elements.size == 0
      raise "invalid use of pipeline: no commands given"
    end

    # Don't modify the originals, and make sure we have an options hash
    # for each element.
    elements = elements.collect do |argv|
      argv = argv.dup
      argv.push(Hash.new) if not argv[-1].respond_to?(:has_key?)
      argv
    end

    # Feed the input and the output
    elements[0][-1][:stdin] = options[:stdin]
    elements[-1][-1][:stdout] = options[:stdout]

    # Build up the structure for the call to #sys.
    elements.each_with_index do |argv, index|
      argv[-1][:stdout] = elements[index + 1] if index < elements.size - 1
      argv[-1][:stderr] = options[:stderr] if options.has_key?(:stderr)
    end

    sys(*elements[0])
  end


  PARENT_PIPES = {}

  SysInfo = Struct.new(:process_infos, :threads)

  #
  # Options to each pipeline element include:
  #   :stdin — file, pipe, buffer, or :console to feed into the first
  #   element of the pipeline.
  #   :stdout — file, pipe, or buffer to collect the output of the
  #   last element of the pipeline.
  #   :stderr — file, pipe, or buffer to collect error information.
  #   :executable — specifies an alternative binary to run, instead of
  #   using the value for argv[0].
  #   :cd — change into this directory for this program.
  #   :close — File or IO.fileno values to close after fork() or set
  #   un-inheritable prior to calling ProcessCreate().
  #   ---- probable future options
  #   :keep — File or IO.fileno values to keep open in child.
  #   :timeout — terminate after a given time.
  #   :env — pass an alternative set of environment variables.
  #   :as_user — Array specifying user and credentials to run as.
  #   process.
  #
  # Returns an array of arrays:
  #   [process objects, threads, pipes]
  #
  # Process objects contain the pid and any relevent process and thread
  # handles.  Threads returned need to be joined to guarentee their
  # input or output is completely processed after the program
  # terminates.  Pipes returned need to be closed after the program
  # terminates.
  #
  def sys_start (*argv)
    options = {
      :stdin => $stdin,
      :stdout => $stdout,
      :stderr => $stderr,
      :executable => argv[0],
      :cd => '.',
      :close => []
    }

    if argv[-1].respond_to?(:has_key?)
      options.merge!(argv.pop)
    end

    options[:executable] = find_in_path(options[:executable])

    original_stdfiles = [:stdout, :stderr].collect do |io_sym|
      options[io_sym]
    end

    upper_child_pipes = []      # pipes for children up the pipeline
    lower_child_pipes = []      # pipes for children down the pipeline
    threads = []                # threads handling special needs I/O
    process_infos = []          # info for children down the pipeline

    [:stdin, :stdout, :stderr].each do |io_sym|
      pior = process_io(io_sym, options[io_sym], original_stdfiles,
          upper_child_pipes + lower_child_pipes + options[:close])
      options[io_sym] = pior.io

      upper_child_pipes << pior.io if pior.threads
      lower_child_pipes << pior.pipe if pior.pipe
      threads.push *pior.threads if pior.threads
      process_infos.push *pior.process_infos if pior.process_infos
    end

    process_infos.unshift(
        create_process(argv, options, lower_child_pipes + options[:close]))
    upper_child_pipes.each { |io| io.close }
    lower_child_pipes.each { |io| io.close }
    SysInfo.new(process_infos, threads)
  end


  def sys (*argv)
    sysinfo = sys_start(*argv)
    overall_result = nil

    results = sysinfo.process_infos.collect do |pi|
      status = sys_wait(pi)
      overall_result = status if overall_result.nil? and not status.success?
      status
    end

    sysinfo.threads.each { |t| t.join }
    overall_result = results[-1] if overall_result.nil?
    duck_type_status_object(results, overall_result)
  end


  ProcessIOResult = Struct.new(:io, :pipe, :threads, :process_infos)

  # File or IO, String (empty), String (filename), String (data),
  # StringIO, Integer, :stdout, :stderr, :null or nil, :zero, Symbol (other),
  # Array (new command)
  # ---- supported:
  # File or IO,
  # StringIO, Integer, :stdout, :stderr, :null or nil, :zero,
  # Array (new command)
  # ---- future:
  # String (empty), String (filename), String (data),
  # Symbol (other),
  #
  # Returns an array of stuff:
  #   [IO object, thread or threads, pipe or pipes, process info objects]
  #
  # The IO object is the processed IO object based on the input IO
  # object (+taret+), which may not have actually been an IO object.
  # Threads returned, if any, need to be joined after the process
  # terminates.  Pipes returned, if any, need to be closed after the
  # process terminates.  Process info objects, if any, refer to other
  # processes running in the pipeline that this call to process_io
  # created.
  #
  def process_io (io_sym, target, original_stdfiles, close_pipes)

    # Firstly, any File or IO value can be returned as it is.
    # We will duck-type recognize File and IO objects if they respond
    # to :fileno and the result of calling #fileno is not nil.
    if target.respond_to?(:fileno) and not target.fileno.nil?
      return ProcessIOResult.new(target)
    end

    # Integer (Fixnum in particular) arguments represent file
    # descriptors to attach this IO to.
    return ProcessIOResult.new(IO.new(target)) if target.is_a? Fixnum

    # Handle special symbol values for :stdin.  Valid symbols are
    # :null and :zero.  Using :null is the same as +nil+ (no input),
    # and using :zero is like sending an endless stream of null
    # characters to the process.
    if io_sym == :stdin
      if target.nil? or target == :null
        return input_pipe {}
      elsif target == :zero
        return input_pipe { |w| w.syswrite("\x00" * 1024) while true }
      elsif target.respond_to?(:sysread)      # "fake" IO and StringIO
        return input_pipe do |w|
          data = nil; w.syswrite(data) while data = target.sysread(1024)
        end
      else
        raise "Invalid input object in Brush#sys"
      end

    # Handle special symbol values for :stdout and :stderr.  Valid
    # symbols are :null, :zero, :stdout, and :stderr.  The symbols
    # :null and :zero mean the output is thrown away.  :stdout means
    # this output goes where standard output should go and :stderr
    # means this output goes where standard error should go.
    else      # io_sym is :stdout or :stderr
      if target.nil? or target == :null or target == :zero
        return output_pipe { |r| r.sysread(1024) while true }
      elsif target == :stdout
        return process_io(io_sym, original_stdfiles[0], nil, close_pipes)
      elsif target == :stderr
        return process_io(io_sym, original_stdfiles[1], nil, close_pipes)
      elsif target.respond_to?(:syswrite)     # "fake" IO and StringIO
        return output_pipe do |r|
          data = nil; target.syswrite(data) while data = r.sysread(1024)
        end
      elsif target.is_a?(Array)               # pipeline
        return child_pipe do |r, w|
          argv = target.dup
          argv.push(Hash.new) if not argv[-1].respond_to?(:has_key?)
          argv[-1].merge!(:stdin => r, :close => [w] + close_pipes)
          sys_start(*argv)
        end
      else
        raise "Invalid output object in Brush#sys"
      end
    end
  end


  def generic_pipe (p_pipe, ch_pipe)
    mark_parent_pipe(p_pipe)
    t = Thread.new do
      begin
        yield p_pipe
      rescue Exception
      ensure
        p_pipe.close
      end
    end
    ProcessIOResult.new(ch_pipe, nil, [t])
  end

  def mark_parent_pipe (pipe)
    class << pipe
      def close
        super
      ensure
        Brush::Pipeline::PARENT_PIPES.delete(self)
      end
    end

    Brush::Pipeline::PARENT_PIPES[pipe] = true
  end

  def input_pipe (&block)
    generic_pipe *IO.pipe.reverse, &block
  end

  def output_pipe (&block)
    generic_pipe *IO.pipe, &block
  end

  def child_pipe
    r, w = *IO.pipe
    sysinfo = yield r, w
    ProcessIOResult.new(w, r, sysinfo.threads, sysinfo.process_infos)
  end


  def each_path_element
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |dir|
      yield File.expand_path(dir)
    end
  end


  def duck_type_status_object (object, status_or_pid, status_integer = nil)
    if status_integer.nil? and status_or_pid.respond_to?(:success?)
      class << object
        # Act like the Process::Status @status.
        (Process::Status.instance_methods - self.instance_methods).each do |m|
          eval("def #{m} (*args); @status.#{m}(*args); end")
        end
      end
      object.instance_variable_set(:@status, status_or_pid)

    else
      class << object
      end

      object.instance_variable_set(:@status, status_or_pid)
      class << object
        attr_reader :to_i, :pid

        # We have no idea if we exited normally, coredumped, etc.  Just
        # pretend it's normal.
        def coredump?; false; end
        def exited?; true; end
        def signaled?; false; end
        def stopped?; false; end
        def stopsig; nil; end
        def success?; @to_i.zero?; end 
        def termsig; nil; end
        alias exitstatus to_i

        # Act like the Fixnum in @to_i.
        (Fixnum.instance_methods - self.instance_methods).each do |m|
          eval("def #{m} (*args); @to_i.#{m}(*args); end")
        end
      end 
      object.instance_variable_set(:@to_i, status_integer)
      object.instance_variable_set(:@pid, status_or_pid)
    end

    object
  end
end


module Brush::Pipeline::POSIX
  ProcessInfo = Struct.new(:process_id)

  def sys_wait (process_info)
    #system("ls -l /proc/#{$$}/fd /proc/#{process_info.process_id}/fd")
    Process.waitpid2(process_info.process_id)[1]
  end

  def create_process (argv, options, close_pipes)

    # The following is used for manual specification testing to verify
    # that pipes are correctly closed after fork.  This is extremely
    # difficult to write an RSpec test for, and it is only possible on
    # platforms that have a /proc filesystem anyway.  Regardless, this
    # will be moved into an RSpec test at some point.
    #
    #$stderr.puts "===== P #{$$}: #{ %x"ls -l /proc/#{$$}/fd" }"

    pid = fork do               # child process
      [:stdin, :stdout, :stderr].each do |io_sym|
        io = options[io_sym]
        if io != Kernel.const_get(io_sym.to_s.upcase)
          Kernel.const_get(io_sym.to_s.upcase).reopen(io)
          io.close
        end
      end

      close_pipes.each { |io| io.close }
      Brush::Pipeline::PARENT_PIPES.each_key { |io| io.close }

      # This is the second half of the manual specification testing
      # started above.  See comment above for more information.
      #
      #$stderr.puts "===== C #{$$}: #{ %x"ls -l /proc/#{$$}/fd" }"

      Dir.chdir(options[:cd]) do
        exec [options[:executable], argv[0]], *argv[1..-1]
      end

      raise Error, "failed to exec"
    end

    ProcessInfo.new(pid)
  end

  def find_in_path (name)
    if name.index(File::SEPARATOR)      # Path is absolute or relative.
      return File.expand_path(name)
    else
      each_path_element do |dir|
        chkname = nil
        return chkname if File.exists?(chkname = File.join(dir, name))
      end
    end

    nil                                 # Didn't find a match. :(
  end
end


module Brush::Pipeline::Win32

  def sys_wait (process_info)
    numeric_status = Process.waitpid2(process_info.process_id)[1]
    Process.CloseHandle(process_info.process_handle)
    Process.CloseHandle(process_info.thread_handle)
    duck_type_status_object(Object.new, process_info.process_id, numeric_status)
  end


  def make_handle_inheritable (io, inheritable = true)
    if not SetHandleInformation(
        get_osfhandle(io.fileno), Windows::Handle::HANDLE_FLAG_INHERIT,
        inheritable ? Windows::Handle::HANDLE_FLAG_INHERIT : 0) \
    then
      raise Error, get_last_error
    end 
  end


  def create_process (argv, options, close_pipes)
    close_pipes.each do |io|
      make_handle_inheritable(io, false)
    end

    Brush::Pipeline::PARENT_PIPES.each_key do |io|
      make_handle_inheritable(io, false)
    end

    [:stdin, :stdout, :stderr].each do |io_sym|
      make_handle_inheritable(options[io_sym]) if options[io_sym]
    end

    Dir.chdir(options[:cd]) do
      return Process.create(
          :app_name => options[:executable],
          :command_line => Escape.shell_command(argv),
          :inherit => true,
          :close_handles => false,
          :creation_flags => Process::CREATE_NO_WINDOW,
          :startup_info => {
              :startf_flags => Process::STARTF_USESTDHANDLES,
              :stdin => options[:stdin],
              :stdout => options[:stdout],
              :stderr => options[:stderr]
          })
    end
  end


  def find_in_path (name)
    chkname = nil

    if name =~ %r"[:/\\]"     # Path is absolute or relative.
      basename = File.basename(name)
      fullname = File.expand_path(name)

      if basename =~ /\./     # Path comes with extension.
        return fullname
      else                    # Need to find extension.
        each_pathext_element do |ext|
          return chkname if File.exists?(chkname = [fullname, ext].join)
        end
      end

    elsif name =~ /\./        # Given extension.
      each_path_element do |dir|
        return chkname if File.exists?(chkname = File.join(dir, name))
      end

    else                      # Just a name—no path or extension.
      each_path_element do |dir|
        each_pathext_element do |ext|
          if File.exists?(chkname = File.join(dir, [name, ext].join))
            return chkname
          end
        end
      end
    end

    nil                       # Didn't find a match. :(
  end


  def each_pathext_element
    ENV['PATHEXT'].split(File::PATH_SEPARATOR).each { |ext| yield ext }
  end

end


module Brush::Pipeline
  if RUBY_PLATFORM =~ /-(mswin|mingw)/
    gem 'win32-process', '>= 0.6.1'
    require 'win32/process'
    require 'escape'
    include Windows::Handle
    include Brush::Pipeline::Win32
  else
    include Brush::Pipeline::POSIX
  end
end
