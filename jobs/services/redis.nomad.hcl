job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis" {
    count = 1

    network {
      mode = "host"
      port "redis" {
        static = 6379
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image        = "redis:7-alpine"
        network_mode = "host"
        ports        = ["redis"]
        privileged   = true
        
        args = [
          "redis-server",
          "--appendonly", "yes",
          "--appendfsync", "everysec",
          "--maxmemory", "256mb",
          "--maxmemory-policy", "allkeys-lru",
        ]
      }

      resources {
        cpu    = 100
        memory = 256
      }

      service {
        name = "redis"
        port = "redis"
        
        tags = [
          "cache",
          "session-store",
          "authelia",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
