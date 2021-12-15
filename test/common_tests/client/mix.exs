defmodule Meta.Saga.Test.Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_etcd_client,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: ["./"],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :common_test, :etcd_client],
      mod: {Test.Etcd.Client.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps, do: []

end
