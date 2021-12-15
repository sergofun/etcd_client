# EtcdClient

Elixir etcd client

## Installation

```elixir

def deps do
  [
      {:etcd_client, git: "https://github.com/sergofun/etcd_client.git"},
  ]
end
```
## Configuration

### None authentication
```elixir
config :etcd_client,
  endpoints: ["172.20.0.5:2379"]
```

### Authentication via system variables
```elixir
config :etcd_client,
  endpoints: ["172.20.0.5:2379"],
  user: {:system, "ETCD_USER"},
  password: {:system, "ETCD_PASSWD"} 
```

### Authentication with explicit credentials
```elixir
config :etcd_client,
  endpoints: ["172.20.0.5:2379"],
  user: "root",
  password: "qwerty" 
```
## API and examples

### Put
```elixir
iex(2)> EtcdClient.Client.put("key1", "some value")
{:ok,
 %Etcdserverpb.PutResponse{
   header: %Etcdserverpb.ResponseHeader{
     cluster_id: 14841639068965178418,
     member_id: 10276657743932975437,
     raft_term: 27,
     revision: 8
   },
   prev_kv: nil
 }}
```

### Get
```elixir
iex(6)> EtcdClient.Client.get("key1")
check_channel_state, pid: #PID<0.231.0>
{:ok,
 %Etcdserverpb.RangeResponse{
   count: 1,
   header: %Etcdserverpb.ResponseHeader{
     cluster_id: 14841639068965178418,
     member_id: 10276657743932975437,
     raft_term: 27,
     revision: 8
   },
   kvs: [
     %Mvccpb.KeyValue{
       create_revision: 7,
       key: "key1",
       lease: 0,
       mod_revision: 8,
       value: "some value",
       version: 2
     }
   ],
   more: false
 }}
```

### Delete

```elixir
iex(8)> EtcdClient.Client.delete("key1")
{:ok,
 %Etcdserverpb.DeleteRangeResponse{
   deleted: 1,
   header: %Etcdserverpb.ResponseHeader{
     cluster_id: 14841639068965178418,
     member_id: 10276657743932975437,
     raft_term: 27,
     revision: 9
   },
   prev_kvs: []
 }}
iex(9)>
```

### Watch
Etcd client library sends watch events({:watch_events, events}) in accordance with provided filter to the caller process.
It's strongly recommended to monitor watch process.

```elixir
   {:ok, pid} = EtcdClient.Client.watch("key1", [:NOPUT])
    Process.monitor(pid)
```

### Lease
lease_grant API call starts keep alive sending every 50ms

```elixir 
iex(4)> EtcdClient.Client.lease_grant(120)
{:ok,
 %Etcdserverpb.LeaseGrantResponse{
   ID: 7587853166505588501,
   TTL: 120,
   error: "",
   header: %Etcdserverpb.ResponseHeader{
     cluster_id: 14841639068965178418,
     member_id: 10276657743932975437,
     raft_term: 27,
     revision: 9
   }
 }}
iex(5)> EtcdClient.Client.lease_revoke(7587853166505588501)
{:ok,
 %Etcdserverpb.LeaseRevokeResponse{
   header: %Etcdserverpb.ResponseHeader{
     cluster_id: 14841639068965178418,
     member_id: 10276657743932975437,
     raft_term: 27,
     revision: 9
   }
 }}
``` 

### Txn

```elixir
  iex(2)> compare = EtcdClient.Client.compare_value("new_key", "24", "==")
  %Etcdserverpb.Compare{
    key: "new_key",
    range_end: "",
    result: :EQUAL,
    target: :VALUE,
    target_union: {:value, "24"}
  }
  iex(3)> success = EtcdClient.Client.request_op_put(%{key: "new_key", value: "new_value"})
  %Etcdserverpb.RequestOp{
    request: {:request_put,
      %Etcdserverpb.PutRequest{
        ignore_lease: false,
        ignore_value: false,
        key: "new_key",
        lease: 0,
        prev_kv: false,
        value: "new_value"
      }}
  }
  iex(4)> EtcdClient.Client.txn([compare], [success], [])
  {:ok,
    %Etcdserverpb.TxnResponse{
      header: %Etcdserverpb.ResponseHeader{
        cluster_id: 14841639068965178418,
        member_id: 10276657743932975437,
         raft_term: 4,
        revision: 64
      },
      responses: [
        %Etcdserverpb.ResponseOp{
          response: {:response_put,
            %Etcdserverpb.PutResponse{
              header: %Etcdserverpb.ResponseHeader{
                cluster_id: 0,
                member_id: 0,
                raft_term: 0,
                revision: 64
              },
              prev_kv: nil
            }}
        }
      ],
      succeeded: true
    }}
```



