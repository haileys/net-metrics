require "rack/static"
require "erb"
require "mysql2"
require "yaml"
require "json"

config = YAML.load_file(File.expand_path("config.yml", __dir__))
$db = Mysql2::Client.new(config["mysql"])

TEMPLATES = Hash.new do |h, k|
  path = File.expand_path("views/#{k}.erb", __dir__)
  erb = ERB.new(File.read(path))
  h[k] = eval("->request { #{erb.src} }", nil, path)
end

routes = {
  "/" => "index",
}

if ENV["RACK_ENV"] != "production"
  require "pry"
  require "better_errors"

  BetterErrors.application_root = __dir__
  use BetterErrors::Middleware

  TemplateReloader = Struct.new(:app) do
    def call(env)
      TEMPLATES.clear
      app.call(env)
    end
  end

  use TemplateReloader
end

run ->env {
  request = Rack::Request.new(env)

  if template_name = routes[request.fullpath]
    template = TEMPLATES[template_name]
    [200, {"Content-Type" => "text/html"}, [template.call(request)]]
  else
    [404, {"Content-Type" => "text/html"}, ["<h1>Not found</h1>"]]
  end
}
