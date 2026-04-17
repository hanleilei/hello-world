terraform {
  backend "s3" {
    bucket         = "hello-world-terraform-state-472303294041-2026"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
