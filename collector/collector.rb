require "bundler/setup"
require "mysql2"
require "yaml"
require "thread"

Datapoint = Struct.new(:host, :latency)

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

  params = {
    host: mysql.escape(datapoint.host),
    latency: datapoint.latency.to_i
  }

  mysql.query(<<-"SQL" % params)
    INSERT INTO ping_stats (host, created_at, latency)
    VALUES ("%{host}", UTC_TIMESTAMP(), %{latency})
  SQL
end
