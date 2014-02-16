require "bundler/setup"
require "mysql2"
require "yaml"
require "thread"

class Datapoint < Struct.new(:host, :latency, :time)
  def initialize(host, latency)
    super(host, latency, Time.now)
  end
end

config = YAML.load_file(File.expand_path("config.yml", __dir__))
mysql = Mysql2::Client.new(config["mysql"])
queue = Queue.new

worker_threads = config["ping"]["hosts"].map { |host|
  Thread.new do
    io = IO.popen(["ping", "-i", config["ping"]["interval"].to_s, host])
    while line = io.gets
      if /time=([0-9.]+) ms/ =~ line
        queue << Datapoint.new(host, $1.to_f.round)
      end
    end
  end
}

running = true

trap "TERM" do
  running = false
end

while running
  datapoint = queue.deq

  row = {
    host:       mysql.escape(datapoint.host),
    created_at: mysql.escape(datapoint.time.strftime("%Y-%m-%d %H:%M:%S")),
    latency:    datapoint.latency.to_i,
  }

  mysql.query(<<-"SQL" % row)
    INSERT INTO ping_stats (host, created_at, latency)
    VALUES ("%{host}", "%{created_at}", %{latency})
  SQL
end
