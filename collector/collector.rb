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
$mysql = Mysql2::Client.new(config["mysql"])
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

def format_time(time)
  $mysql.escape(time.strftime("%Y-%m-%d %H:%M:%S"))
end

while running
  datapoint = queue.deq

  params = {
    host:       $mysql.escape(datapoint.host),
    created_at: format_time(datapoint.time),
    latency:    datapoint.latency.to_i,

    # rounded data:
    created_at_5_min: format_time(
        Time.utc(
          datapoint.time.year,
          datapoint.time.month,
          datapoint.time.day,
          datapoint.time.hour,
          datapoint.time.min - datapoint.time.min % 5)),

    created_at_1_hour: format_time(
        Time.utc(
          datapoint.time.year,
          datapoint.time.month,
          datapoint.time.day,
          datapoint.time.hour)),
  }

  queries = [
    <<-SQL,
      INSERT INTO ping_stats (host, created_at, latency)
      VALUES ("%{host}", "%{created_at}", %{latency})
    SQL
    <<-SQL,
      INSERT IGNORE INTO aggregated_stats_5_min (host, created_at, latency_samples, latency_sum)
      VALUES ("%{host}", "%{created_at_5_min}", 0, 0)
    SQL
    <<-SQL,
      INSERT IGNORE INTO aggregated_stats_1_hour (host, created_at, latency_samples, latency_sum)
      VALUES ("%{host}", "%{created_at_1_hour}", 0, 0)
    SQL
    <<-SQL,
      UPDATE aggregated_stats_5_min
      SET latency_samples = latency_samples + 1,
          latency_sum = latency_sum + %{latency}
      WHERE host = "%{host}" AND created_at = "%{created_at_5_min}"
    SQL
    <<-SQL,
      UPDATE aggregated_stats_1_hour
      SET latency_samples = latency_samples + 1,
          latency_sum = latency_sum + %{latency}
      WHERE host = "%{host}" AND created_at = "%{created_at_1_hour}"
    SQL
  ]

  queries.each do |query|
    $mysql.query(query % params)
  end
end
