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

  mysql.query(<<-"SQL")
    INSERT INTO ping_stats (
      host,
      created_at,
      latency
    ) VALUES (
      "#{mysql.escape(datapoint.host)}",
      UTC_TIMESTAMP(),
      "#{datapoint.latency.to_i}"
    )
  SQL
end
