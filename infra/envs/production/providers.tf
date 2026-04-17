provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      Region      = "primary"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      Region      = "secondary"
      ManagedBy   = "terraform"
    }
  }
}
