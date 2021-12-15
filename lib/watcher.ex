defmodule EtcdClient.Watcher do
  @moduledoc false
  use GenServer

  require Logger

  alias EtcdClient.Etcd
  alias Etcdserverpb.Watch.Stub
  alias GRPC.Client.Stream
  alias GRPC.Codec.Proto

  @spec start_link(GenServer.server()):: GenServer.on_start()
  def start_link(report_to), do:
    GenServer.start_link(__MODULE__, report_to)

  @spec send_request(struct(), GenServer.server()) :: Stream.t()
  def send_request(request, send_to), do:
     GenServer.call(send_to, {:request, request})

  @impl true
  def init(report_to) do
    with {:ok, %GRPC.Channel{adapter_payload: %{conn_pid: conn_pid}} = channel} <- Etcd.get_channel(),
        true <- Process.alive?(conn_pid) do
          stream = Stub.watch(channel, timeout: :infinity)
          {:ok, %{stream: stream, report_to: report_to}}
    else
      _ -> {:stop, :error}
    end
  end

  @impl true
  def handle_call({:request, request}, _from, %{stream: stream} = state) do
    response = Stream.send_request(stream, request, end_stream: false, timeout: :infinity)
    {:reply, response, state}
  end

  @impl true
  def handle_info({:gun_data, _, _, _, data}, %{report_to: report_to} = state) do

    message =
      data
      |> GRPC.Message.from_data()
      |> Proto.decode(Etcdserverpb.WatchResponse)

    %Etcdserverpb.WatchResponse{canceled: canceled, events: events} = message

    if canceled do
      Logger.warn("Got #{inspect(message)}, terminate stream")
      {:stop, :error, state}
    else
      unless events == [], do: Process.send(report_to, {:watch_events, message}, [])
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_error, _, _, _} = message, state) do
    Logger.warn("Got #{inspect(message)}, terminate stream")
    {:stop, :disconnected, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.debug("Got #{inspect(message)}, don't handle")
    {:noreply, state}
  end

end
