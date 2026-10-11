require "./commandant_bench_cli/cli"

begin
  exit Commandant::Bench::CLI.run(ARGV)
rescue ex : IO::Error
  exit 0 if ex.os_error == Errno::EPIPE
  raise ex
end
