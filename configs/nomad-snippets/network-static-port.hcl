# Network Pattern: Static Port
# Use for services that require specific ports (e.g., Traefik on 80/443)

network {
  mode = "host"
  port "http" {
    static = 8080  # Change to your required port
  }
}
