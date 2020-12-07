# frozen_string_literal: true

require 'open3'

# Creates child processes to run commands.
class Helli::Process
  attr_reader :wd, :cmd, :stdin, :exitstatus
  attr_accessor :stdout, :stderr, :other

  # Creates a Process in at given working directory.
  def initialize(wd = nil)
    @wd = wd
  end

  # Opens a process and captures the standard output and the standard error of a command.
  # Raises Timeout::Error if process timeout is exceeded. Returns itself.
  def open(*cmd, stdin: '', timeout: 5)
    @cmd = cmd.join(' ')
    @stdin = stdin

    # Avoid unnecessary chdir
    if @wd
      Dir.chdir(@wd) do
        _popen3_timeout(timeout)
      end
    else
      _popen3_timeout(timeout)
    end

    self
  end

  # Behaves as same as Helli::Process#open, but also raises Helli::Process::Error if the process exits with a non-zero status.
  def open!(*cmd, stdin: '', timeout: 5)
    open(*cmd, stdin: stdin, timeout: timeout)
    raise Helli::Process::Error, @cmd + ":\n" + @stderr unless @exitstatus.zero?

    self
  end

  private def _popen3_timeout(timeout)
    Open3.popen3(@cmd) do |i, o, e, t|
      i.puts @stdin
      i.close

      begin
        Timeout.timeout(timeout) do
          @stdout = o.read
          @stderr = e.read
          @exitstatus = t.value.exitstatus
        end
      rescue Timeout::Error
        Process.kill('KILL', t.pid)
        raise Timeout::Error, 'process timeout exceeded'
      end
    end
  end

  class Error < StandardError; end
end