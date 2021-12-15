import Config

config :etcd_client,
  endpoints: {:system, "AEON_ETCD_CLUSTER"},
  user: {:system, "AEON_ETCD_USER"},
  password: {:system, "AEON_ETCD_PASSWORD"}
