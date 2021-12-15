defmodule EtcdClient.Connection do
  @moduledoc false

  use GenServer

  require Logger

  @adapter_opts %{http2_opts: %{keepalive: :infinity}}
  @token_refresh_timeout 60_000
  @connect_timeout 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args), do:
    GenServer.start_link(
      __MODULE__,
      args,
      name: {:via, Registry, {EtcdClient.Registry, "etcd_conn", {args[:reg_name], {:nok, :disconnected}}}})

  @impl true
  def init(args) do
    state = initial_state(args)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, %{
    reg_name: reg_name,
    address: address,
    credentials: credentials
  } = state) do

    case do_connect(address, credentials) do
      {:ok, channel} ->
        Logger.info("Connected to etcd, channel: #{inspect(channel)}")
        Registry.update_value(EtcdClient.Registry, "etcd_conn", fn _ -> {reg_name, {:ok, channel}} end)
        {:noreply, state}
      {:error, :auth_fail} ->
        Logger.error("Authorization failed for: #{inspect(credentials)}")
        {:stop, :normal, state}
      {:error, error} ->
        Logger.error("Connection error: #{inspect(error)}")
        {:noreply, state, @connect_timeout}
    end
  end

  @impl true
  def handle_call(:get_channel, _from, %{channel: channel} = state) when not is_nil(channel),
      do: {:reply, {:ok, channel}, state}

  @impl true
  def handle_info(:timeout, %{channel: channel} = state) when not is_nil(channel) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:refresh_token, %{
    reg_name: reg_name,
    address: address,
    credentials: credentials} = state) do
    case get_token(address, credentials) do
      {:ok, token} ->
        #update headers for existing connection
        Logger.info("Refresh token: #{inspect(token)}")

        [{_, {_, {:ok, channel}}}] = Registry.match(EtcdClient.Registry, "etcd_conn", {reg_name, :_})
        new_channel = %{channel | headers: [{"authorization", token}]}
        Registry.update_value(EtcdClient.Registry, "etcd_conn", fn _ -> {reg_name, {:ok, new_channel}} end)
        {:noreply, state}
      {:error, :auth_fail} ->
        Logger.error("Authorization failed for: #{inspect(credentials)}")
        {:stop, :normal, state}
      {:error, error} ->
        Logger.warn("Error: #{inspect(error)}, during token refresh, try to refresh next time")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gun_down, _, :http2, _, _}, %{reg_name: reg_name} = state) do
    Logger.warn("etcd_conn #{inspect(reg_name)} went down, pid: #{inspect(self())}")
    {:noreply, state, @connect_timeout}
  end

  @impl true
  def handle_info(:timeout, :shutdown) do
    {:stop, :disconnected, :shutdown}
  end

  @impl true
  def handle_info(:timeout, _state) do
    {:noreply, :shutdown, @connect_timeout}
  end

  @impl true
  def handle_info(message, state) do
    Logger.debug("Got #{inspect(message)}, do nothing")
    {:noreply, state}
  end

  defp do_connect(address, nil),
       do: GRPC.Stub.connect(address, adapter_opts: @adapter_opts)

  defp do_connect(address, credentials) do
    with {:ok, token} <- get_token(address, credentials),
         {:ok, channel} <- GRPC.Stub.connect(address, [
           adapter_opts: @adapter_opts,
           headers: [{"authorization", token}]]) do
      {:ok, channel}
    end
  end

  defp get_token(address, %{user: user, password: password}) do
    auth_req = Etcdserverpb.AuthenticateRequest.new(name: user, password: password)

    Process.send_after(self(), :refresh_token, @token_refresh_timeout)
    case GRPC.Stub.connect(address, adapter_opts: @adapter_opts) do
      {:ok, channel} ->
        response =
          channel
          |> Etcdserverpb.Auth.Stub.authenticate(auth_req)
          |> case  do
               {:ok, %Etcdserverpb.AuthenticateResponse{token: token}} -> {:ok, token}
               {:error, %GRPC.RPCError{status: 3}} -> {:error, :auth_fail}
               _ -> {:error, :next_attempt}
             end
        GRPC.Stub.disconnect(channel)
        response
      _other -> {:error, :next_attempt}
    end
  end

  def initial_state(args) do
    %{
        reg_name: args[:reg_name],
        address: args[:address],
        credentials: args[:credentials]
     }
  end
end
