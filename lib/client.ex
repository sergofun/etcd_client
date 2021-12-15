defmodule EtcdClient.Client do
  @moduledoc false

  alias EtcdClient.{Etcd, LeaseKeepAlive, Watcher}

  @type watch_filter :: :NOPUT | :NODELETE
  @type watch_filters :: [watch_filter()] | nil
  @type txn_cond :: String.t()
  @type txn_compare :: [Etcdserverpb.Compare.t()]
  @type txn_success :: [Etcdserverpb.RequestOp.t()] | []
  @type txn_failure :: [Etcdserverpb.RequestOp.t()] | []

  @spec status() :: {:ok, Etcdserverpb.StatusResponse.t()} | {:error, term()}
  def status do
    request = Etcdserverpb.StatusRequest.new()
    with {:ok, channel} <- Etcd.get_channel() do
      Etcdserverpb.Maintenance.Stub.status(channel, request)
    end
  end

  @spec put(binary(), binary()) :: {:ok, Etcdserverpb.PutResponse.t()} | {:error, term()}
  def put(key, value),
    do: put(key: key, value: value)

  @spec put(binary(), binary(), integer()) :: {:ok, Etcdserverpb.PutResponse.t()} | {:error, term()}
  def put(key, value, lease_id),
    do: put(key: key, value: value, lease: lease_id)

  @spec put(keyword()) :: {:ok, Etcdserverpb.PutResponse.t()} | {:error, term()}
  def put(request_args) do
    with {:ok, channel} <- Etcd.get_channel() do
      request = Etcdserverpb.PutRequest.new(request_args)
      Etcdserverpb.KV.Stub.put(channel, request)
    end
  end

  @spec get(keyword()) :: {:ok, Etcdserverpb.RangeResponse.t()} | {:error, term()}
  def get(request_args) when is_list(request_args) do
    with {:ok, channel} <- Etcd.get_channel() do
      request = Etcdserverpb.RangeRequest.new(request_args)
      Etcdserverpb.KV.Stub.range(channel, request)
    end
  end

  @spec get(binary()) :: {:ok, Etcdserverpb.RangeResponse.t()} | {:error, term()}
  def get(key) when is_binary(key) do
    range_end = range_end(key)
    get(key, range_end)
  end

  @spec get(binary(), binary()) :: {:ok, Etcdserverpb.RangeResponse.t()} | {:error, term()}
  def get(key, range_end),
    do: get(key: key, range_end: range_end)

  @spec range_end(binary() | list()) :: binary()
  def range_end(prefix) when is_binary(prefix) do
    prefix
    |> String.to_charlist
    |> range_end
  end

  def range_end([]), do: "\0"

  def range_end(prefix) do
    {range_prefix, range_suffix} = Enum.split_with(prefix, &(&1 < 255))
    case range_prefix do
      [] ->
        prefix
      range_prefix ->
        len = length(range_prefix)
        {range_prefix_short, last} = Enum.split(range_prefix, len - 1)
        last_ascii = hd(last)
        List.to_string([range_prefix_short, <<last_ascii + 1>>, range_suffix])
    end
  end

  @spec delete(binary()) :: {:ok, Etcdserverpb.DeleteRangeResponse.t()} | {:error, term()}
  def delete(key) do
    with {:ok, channel} <- Etcd.get_channel() do
      delete_request = Etcdserverpb.DeleteRangeRequest.new(key: key)
      Etcdserverpb.KV.Stub.delete_range(channel, delete_request)
    end
  end

  @spec unwatch(pid(), integer()) :: :ok | {:error, term()}
  def unwatch(watcher_pid, watch_id) do
    request = Etcdserverpb.WatchCancelRequest.new(watch_id)
    Watcher.send_request(request, watcher_pid)
    GenServer.stop(watcher_pid, :normal)
  end

  @spec watch(binary(), integer(), watch_filters()) :: {:ok, map()} | {:error, term()}
  def watch(key, start_revision, filters) when is_number(start_revision) do
    report_to = self()
    watch_id = System.unique_integer()
    range_end = range_end(key)

    watch_create_request = Etcdserverpb.WatchCreateRequest.new(
      start_revision: start_revision,
      watch_id: watch_id,
      key: key,
      range_end: range_end,
      filters: filters)
    request =
      %{request_union: {:create_request, watch_create_request}}
      |> Etcdserverpb.WatchRequest.new()

    with {:ok, pid} <- Watcher.start_link(report_to) do
      Watcher.send_request(request, pid)
      {:ok, %{watcher_pid: pid, watch_id: watch_id}}
    end
  end

  @spec watch(binary(), watch_filters()) :: {:ok, map()} | {:error, term()}
  def watch(key, filters), do: watch(key, 0, filters)

  @spec watch(binary()) :: {:ok, map()} | {:error, term()}
  def watch(key), do: watch(key, 0, nil)

  @spec lease_grant(integer()) :: {:ok, Etcdserverpb.LeaseGrantResponse.t()} | {:error, term()}
  def lease_grant(ttl) do
    with {:ok, channel} <- Etcd.get_channel() do
      grant_request = Etcdserverpb.LeaseGrantRequest.new(ID: 0, TTL: ttl) #ID = 0, server assigns proper value

      channel
      |> Etcdserverpb.Lease.Stub.lease_grant(grant_request)
      |> case do
           {:ok, %{ID: lease_id} = response} ->
             LeaseKeepAlive.start_link(channel, lease_id)
             {:ok, response}
           {:error, error} ->
             {:error, error}
        end
    end
  end

  @spec lease_revoke(integer()) :: {:ok, Etcdserverpb.LeaseRevokeResponse.t()} | {:error, term()}
  def lease_revoke(lease_id) do
    with {:ok, channel} <- Etcd.get_channel() do

      EtcdClient.Registry
      |> Registry.lookup(LeaseKeepAlive.process_name(lease_id))
      |> case  do
           [{pid, _}] -> GenServer.stop(pid)
           [] -> :do_nothing
         end

      revoke_request = Etcdserverpb.LeaseRevokeRequest.new(ID: lease_id)
      Etcdserverpb.Lease.Stub.lease_revoke(channel, revoke_request)
    end
  end

  @spec compare_version(binary(), integer(), txn_cond()) :: Etcdserverpb.Compare.t()
  def compare_version(key, version, result) do
    Etcdserverpb.Compare.new(
      target_union: {:version, version},
      result: to_result(result),
      target: :VERSION,
      key: key)
  end

  @spec compare_create(binary(), integer(), txn_cond()) :: Etcdserverpb.Compare.t()
  def compare_create(key, revision, result) do
    Etcdserverpb.Compare.new(
      target_union: {:create_revision, revision},
      result: to_result(result),
      target: :CREATE,
      key: key)
  end

  @spec compare_mod(binary(), integer(), txn_cond()) :: Etcdserverpb.Compare.t()
  def compare_mod(key, revision, result) do
    Etcdserverpb.Compare.new(
      target_union: {:mod_revision, revision},
      result: to_result(result),
      target: :MOD,
      key: key)
  end

  @spec compare_value(binary(), binary(), txn_cond()) :: Etcdserverpb.Compare.t()
  def compare_value(key, value, result) do
    Etcdserverpb.Compare.new(
      target_union: {:value, value},
      result: to_result(result),
      target: :VALUE,
      key: key)
  end

  @spec compare_lease(binary(), integer(), txn_cond()) :: Etcdserverpb.Compare.t()
  def compare_lease(key, lease, result) do
    Etcdserverpb.Compare.new(
      target_union: {:lease, lease},
      result: to_result(result),
      target: :LEASE,
      key: key)
  end

  @spec request_op_range(map()) :: Etcdserverpb.RequestOp.t()
  def request_op_range(range_params) do
    request_range = Etcdserverpb.RangeRequest.new(range_params)
    Etcdserverpb.RequestOp.new(
      request: {:request_range, request_range}
    )
  end

  @spec request_op_put(list()) :: Etcdserverpb.RequestOp.t()
  def request_op_put(put_params) do
    request_put = Etcdserverpb.PutRequest.new(put_params)
    Etcdserverpb.RequestOp.new(
      request: {:request_put, request_put}
    )
  end

  @spec request_op_delete(list()) :: Etcdserverpb.RequestOp.t()
  def request_op_delete(delete_params) do
    request_delete = Etcdserverpb.DeleteRangeRequest.new(delete_params)
    Etcdserverpb.RequestOp.new(
      request: {:request_delete_range, request_delete}
    )
  end

  @spec request_op_txn(list()) :: Etcdserverpb.RequestOp.t()
  def request_op_txn(txn_params) do
    request_txn = Etcdserverpb.TxnRequest.new(txn_params)
    Etcdserverpb.RequestOp.new(
      request: {:request_txn, request_txn}
    )
  end

  @spec txn(txn_compare(), txn_success(), txn_failure()) :: {:ok, Etcdserverpb.TxnResponse.t()} | {:error, term()}
  def txn(compare, success, failure) do
    with {:ok, channel} <- Etcd.get_channel() do
      request = Etcdserverpb.TxnRequest.new(compare: compare, success: success, failure: failure)
      Etcdserverpb.KV.Stub.txn(channel, request)
    end
  end

  defp to_result("="),   do: :EQUAL
  defp to_result("=="),  do: :EQUAL
  defp to_result("!="),  do: :NOT_EQUAL
  defp to_result("!=="), do: :NOT_EQUAL
  defp to_result("<"),   do: :LESS
  defp to_result(">"),   do: :GREATER

end
