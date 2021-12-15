import Config

config :logger,
  backends: [:console]

config :logger, :console,
  truncate: :infinity,
  format: "{ date=$date time=$time level=$level event=$message $metadata }\n",
  metadata: [
    :tag
  ]

if File.exists?("./config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
