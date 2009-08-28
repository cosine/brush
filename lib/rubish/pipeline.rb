module Rubish; end


module Rubish::Pipeline

  #
  # Example of future +pipetree+ method.
  #
  # pipetree 'gzip', '-cd', 'file.tgz', :stderr => :errors,
  #     :stdout => ['tar', 'tf', '-', :stderr => :errors,
  #     :stdout => archive_files_buffer ],
  #     :errors => ['tee', 'errors_file.log']
  #

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
  #   Rubish::Pipeline.pipeline(
  #       ['gzip', '-cd', 'filename.tar.gz', :cd => 'Downloads'],
  #       ['tar', 'xvf', '-', :cd => 'Extractions'],
  #       :stdout => extracted_files)
  #
  def pipeline (*elements)
    options = {}
    if elements[-1].respond_to?(:has_key?)
      options.merge!(elements.pop)
    end

  end


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
  #   ---- probable future options
  #   :env — pass an alternative set of environment variables to the
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
      :cd => '.'
    }

    if argv[-1].respond_to?(:has_key?)
      options.merge!(argv.pop)
    end

    options[:executable] = find_in_path(options[:executable])

    original_stdfiles = [:stdout, :stderr].collect do |io_sym|
      options[io_sym]
    end

    process_infos = []
    pipe_threads = []
    child_pipes = []

    [:stdin, :stdout, :stderr].each do |io_sym|
      options[io_sym], threads, pipes, p_infos =
              *process_io(io_sym, options[io_sym], original_stdfiles)
      pipe_threads.push *[*threads] if threads
      child_pipes.push *[*pipes] if pipes
      process_infos.push *p_infos if p_infos
    end

    process_infos.unshift create_process(argv, options)
    [process_infos, pipe_threads, child_pipes]

  ensure
    [:stdin, :stdout, :stderr].each do |io_sym|
      io = options[io_sym]
      io.close if io.respond_to?(:rubish_pipe?) and not io.closed?
    end
  end


  def sys (*argv)
    process_infos, pipe_threads, child_pipes = *sys_start(*argv)
    results = process_infos.collect { |pi| sys_wait(pi) }
    pipe_threads.each { |t| t.join }
    child_pipes.each { |io| io.close }
    results
  end


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
  def process_io (io_sym, target, original_stdfiles)

    # Firstly, any File or IO value can be returned as it is.
    # We will duck-type recognize File and IO objects if they respond
    # to :fileno and the result of calling #fileno is not nil.
    return [target] if target.respond_to?(:fileno) and not target.fileno.nil?

    # Integer (Fixnum in particular) arguments represent file
    # descriptors to attach this IO to.
    return [IO.new(target)] if target.is_a? Fixnum

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
        raise "Invalid input object in Rubish#sys"
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
        return original_stdfiles[0] # FIXME: broken
      elsif target == :stderr
        return original_stdfiles[1] # FIXME: broken
      elsif target.respond_to?(:syswrite)     # "fake" IO and StringIO
        return output_pipe do |r|
          data = nil; target.syswrite(data) while data = r.sysread(1024)
        end
      elsif target.is_a?(Array)               # pipeline
        return child_pipe do |r|
          argv = target.dup
          argv.push(Hash.new) if not argv[-1].respond_to?(:has_key?)
          argv[-1].merge!(:stdin => r)
          sys_start(*argv)
        end
      else
        raise "Invalid output object in Rubish#sys"
      end
    end
  end


  def generic_pipe (p_pipe, ch_pipe)
    mark_pipes(p_pipe, ch_pipe)
    t = Thread.new do
      begin
        yield ch_pipe
      rescue Exception
      ensure
        ch_pipe.close
      end
    end
    [p_pipe, t]
  end

  def mark_pipes (p_pipe, ch_pipe)
    class << p_pipe; def rubish_pipe?; true; end; end
    class << ch_pipe; def rubish_child_pipe?; true; end; end
  end

  def input_pipe (&block)
    generic_pipe *IO.pipe, &block
  end

  def output_pipe (&block)
    generic_pipe *IO.pipe.reverse, &block
  end

  def child_pipe
    r, w = *IO.pipe
    mark_pipes(w, r)
    process_infos, threads, pipes = *yield(r)
    pipes << r
    [w, threads, pipes, process_infos]
  end


  def each_path_element
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |dir|
      yield File.expand_path(dir)
    end
  end
end


module Rubish::Pipeline::POSIX

  def sys_wait (process_info)
    Process.waitpid2(process_info.process_id)[1]
  end

  def create_process (argv, options)
    pid = fork

    if pid.nil?                # child process
      [:stdin, :stdout, :stderr].each do |io_sym|
        eval("$#{io_sym}").reopen(options[io_sym]) if options[io_sym]
      end

      Dir.chdir(options[:cd]) do
        exec [options[:executable], argv[0]], *argv[1..-1]
      end

      raise Error, "failed to exec"
    end

    process_info = Object.new
    process_info.instance_variable_set(:@process_id, pid)
    class << process_info; attr_reader :process_id; end
    process_info
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


module Rubish::Pipeline::Win32

  def sys_wait (process_info)
    numeric_status = Process.waitpid2(process_info.process_id)[1]
    Process.CloseHandle(process_info.process_handle)
    Process.CloseHandle(process_info.thread_handle)

    status = Object.new
    class << status
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

      def method_missing (meth, *args)  # Act like an Integer
        @to_i.send(meth, *args)
      end
    end 
    status.instance_variable_set(:@to_i, numeric_status)
    status.instance_variable_set(:@pid, process_info.process_id)

    status
  end


  def make_handle_inheritable (io)
    if not SetHandleInformation(
        get_osfhandle(io.fileno), Windows::Handle::HANDLE_FLAG_INHERIT,
        Windows::Handle::HANDLE_FLAG_INHERIT) \
    then
      raise Error, get_last_error
    end 
  end


  def create_process (argv, options)
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


module Rubish::Pipeline
  if RUBY_PLATFORM =~ /-(mswin|mingw)/
    gem 'win32-process', '>= 0.6.1'
    require 'win32/process'
    require 'escape'
    include Windows::Handle
    include Rubish::Pipeline::Win32
  else
    include Rubish::Pipeline::POSIX
  end
end
