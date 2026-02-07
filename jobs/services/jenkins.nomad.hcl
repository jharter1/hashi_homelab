job "jenkins" {
  datacenters = ["dc1"]
  type        = "service"

  group "jenkins" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
      port "agent" {
        to = 50000
      }
    }

    volume "jenkins_home" {
      type      = "host"
      read_only = false
      source    = "jenkins_home"
    }

    task "jenkins" {
      driver = "docker"
      
      user = "root"

      config {
        image = "jenkins/jenkins:lts"
        ports = ["http", "agent"]
      }

      volume_mount {
        volume      = "jenkins_home"
        destination = "/var/jenkins_home"
      }

      env {
        JAVA_OPTS = "-Djava.awt.headless=true"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "jenkins"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.jenkins.rule=Host(`jenkins.lab.hartr.net`)",
          "traefik.http.routers.jenkins.entrypoints=websecure",
          "traefik.http.routers.jenkins.tls=true",
          "traefik.http.routers.jenkins.tls.certresolver=letsencrypt",
          "traefik.http.routers.jenkins.middlewares=authelia@file",
        ]

        check {
          type     = "http"
          path     = "/login"
          interval = "30s"
          timeout  = "5s"
        }
      }

      service {
        name = "jenkins-agent"
        port = "agent"
        
        tags = ["jenkins", "agent"]
      }
    }
  }
}
