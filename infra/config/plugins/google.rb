TerraspacePluginGoogle.configure do |config|
  # State storage has its own explicit bootstrap and must never be implicit.
  config.auto_create = false
end
