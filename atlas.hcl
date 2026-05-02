env "default" {
  src = "file://migrations"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev"
}
