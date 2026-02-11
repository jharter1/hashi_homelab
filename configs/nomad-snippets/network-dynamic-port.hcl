# Network Pattern: Dynamic Port
# Use for services that can use dynamic port allocation

network {
  port "http" {
    to = 80  # Internal container port
  }
}
