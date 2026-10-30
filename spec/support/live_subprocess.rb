require "open3"
require "timeout"

module LiveSubprocess
  def self.capture(environment, *command, timeout:, stdin_data: "")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    Open3.popen3(environment, *command, pgroup: true) do |input, output, errors, process|
      workers = [Thread.new { output.read }, Thread.new { errors.read }]
      workers << Thread.new do
        input.write(stdin_data)
      rescue Errno::EPIPE, IOError
        nil
      ensure
        input.close unless input.closed?
      end
      workers.each { |thread| thread.report_on_exception = false }
      completed = false
      begin
        # Bound both process exit and pipe draining: a descendant can inherit pipes
        # even after the immediate child has exited.
        [workers.last, process, *workers.first(2)].each do |thread|
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Timeout::Error, "live subprocess timed out" if remaining <= 0 || !thread.join(remaining)
        end
        result = [workers[0].value, workers[1].value, process.value]
        completed = true
        result
      ensure
        unless completed
          begin
            Process.kill("KILL", -process.pid)
          rescue Errno::ESRCH
            # The process group has already exited.
          end
        end
        workers.each { |thread| thread.kill if thread.alive? }
        workers.each(&:join)
        # Open3 reaps the immediate child after the killed workers release the pipes.
      end
    end
  end
end
