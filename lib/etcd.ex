defmodule EtcdClient.Etcd do
  @moduledoc false

  use Supervisor

  alias EtcdClient.Connection

  require Logger

  @spec get_channel() :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def get_channel do
    case Process.whereis(EtcdClient.Registry) do
      nil ->
        {:error, :no_channels}
      _pid ->
        get_channel_from_registry()
    end
  end

  def get_channel_from_registry do
    EtcdClient.Registry
    |> Registry.lookup("etcd_conn")
    |> case do
         [] -> {:error, :no_channels}
         channels ->
           Enum.reduce_while(channels, {:error, :no_channels},
             fn
               {_pid, {_, {:ok, channel}}}, _error_response -> {:halt, {:ok, channel}}
               {_pid, {_, _}}, error_response -> {:cont, error_response}
             end)
       end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args), do:
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)

  @impl true
  def init(options) do
    options
    |> connection_children_specs
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp connection_children_specs([endpoints: endpoints, credentials: credentials]) do
    endpoints
    |> Enum.with_index
    |> Enum.map(&connection_children_spec(&1, credentials))
  end

  defp connection_children_spec({endpoint, index}, credentials) do
      {Connection, [
          address: endpoint,
          reg_name: index,
          credentials: credentials
        ]}
  end
end
