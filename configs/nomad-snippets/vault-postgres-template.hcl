# Vault Template: PostgreSQL Database Connection
# Template for PostgreSQL database connection secrets
# Replace SERVICE with your service name

template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/SERVICE" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}
DB_PORT=5432
DB_NAME=SERVICE
DB_USER=SERVICE
  EOH
}
