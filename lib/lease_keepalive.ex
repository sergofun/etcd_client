defmodule EtcdClient.LeaseKeepAlive do
  @moduledoc false

  use GenServer

  require Logger

  @keep_alive_timeout 50
  alias Etcdserverpb.Lease

  @spec process_name(integer()) :: String.t()
  def process_name(lease_id), do: "lease_" <> Integer.to_string(lease_id)

  @spec start_link(GRPC.Channel.t(), integer()) :: GenServer.on_start()
  def start_link(channel, lease_id), do:
    GenServer.start_link(
      __MODULE__,
      [channel, lease_id],
      name: {:via, Registry, {EtcdClient.Registry, process_name(lease_id)}})

  @impl true
  def init([channel, lease_id]) do
    stream = Lease.Stub.lease_keep_alive(channel, timeout: :infinity)
    Process.send(self(), :keep_alive, [])
    {:ok, %{stream: stream, lease_id: lease_id}}
  end

  @impl true
  def handle_info(:keep_alive, %{stream: stream, lease_id: lease_id} = state) do
    live_request = Etcdserverpb.LeaseKeepAliveRequest.new(ID: lease_id)
    GRPC.Client.Stream.send_request(stream, live_request, end_stream: false, timeout: :infinity)
    Process.send_after(self(), :keep_alive, @keep_alive_timeout)
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_data, _, _, _, _}, state),
      do: {:noreply, state}

  @impl true
  def handle_info({:gun_response, _, _, _, _, _}, state),
      do: {:noreply, state}

  @impl true
  def handle_info({:gun_error, _, _, _} = message, state) do
    Logger.warn("Got #{inspect(message)}, terminate stream")
    {:stop, :normal, state}
  end

end
