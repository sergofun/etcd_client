defmodule EtcdClient.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do

    endpoints =
      :endpoints
      |> get_env("127.0.0.1:2379")
      |> String.split(",")
    user      = get_env(:user)
    password  = get_env(:password)

    credentials =
      case user do
        nil -> nil
        _   -> %{user: user, password: password}
      end

    children = [
      {Registry, [keys: :unique, name: EtcdClient.Registry]},
      {EtcdClient.Etcd, [endpoints: endpoints, credentials: credentials]}
    ]

    opts = [strategy: :one_for_one, name: EtcdClient.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_env(env, default_value \\ nil) do
    :etcd_client
    |> Application.get_env(env)
    |> read_env_variable(default_value)
  end

  defp read_env_variable({:system, env_name}, default_value) do
    env_name
    |> System.get_env(env_name)
    |> read_env_variable(default_value)
  end

  defp read_env_variable(nil, default_value), do: default_value
  defp read_env_variable(value, _default_value), do: value

end
