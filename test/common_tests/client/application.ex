defmodule Test.Etcd.Client.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    Application.ensure_started(:etcd_client, permanent)
    children = []
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Test.Etcd.Client.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
