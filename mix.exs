defmodule MetaEtcd.MixProject do
  use Mix.Project

  def project do
    [
      app: :etcd_client,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EtcdClient.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:grpc, github: "elixir-grpc/grpc"},
      # Devops dependencies
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:redbug, git: "https://github.com/massemanet/redbug.git"}
    ]
  end

  defp aliases do
    [
      ct: "cmd rebar3 ct --name etcd_client@127.0.0.1 --setcookie aeon",
      lint: "credo --strict"
    ]
  end

end
