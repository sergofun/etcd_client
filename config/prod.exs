import Config

config :etcd_client,
  endpoints: {:system, "ETCD_CLUSTER"},
  user: {:system, "ETCD_USER"},
  password: {:system, "ETCD_PASSWORD"}
