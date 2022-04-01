terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "4.5.0"
    }
  }
}

locals {
  region = "us-east-1"
}

provider "aws" {
  region = local.region
}

module "app_module" {
  source          = "./modules/app"
  name            = "mykyta"
  instance_type   = "t2.micro"
  add_volume_size = 20
  public_key      = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCouy0bYm7tMAhiMTZm9nNGcJP5l2EjDE8oCSwCp0ipIYJLkHc3ncyz7MnyUReqN/YVEZbfz2+UQcpGGa4HCDW/N2IJLIK1mE6AAScgEJ7xPt6RCSa1o0In/K7Ij0ad4lLmRiC7Si+UKHcPT+EGH4g9ZesgMjQjFjZ2yM/tDA01Tqai5kLGR39J0UioDvFCfBvGzW39q5ZjEhLLvE5aLD4Ezzbkmci1nn12INfBhxL5+EREhV941sHIkAbVcYD811gnYVTguIZNjMqs9E7IWdd+X2HaGJCbtjWCPir/HA63+Q2gB1W5MFZ912zZY+qoJ8PWyIdxQzp52nT1QcuUSThpif0cKXj7eId4EfDeSXqhUWtr0eZS+jxLTDRfWd+KYnNqSK0+QO358OC3IG45ZpHhvWW0wPuyATPW89OOYWn+FW2qhDasBLlWadHw0MXZ2ABU5Oys+E1inO5dQxti43z8D8mE7+y0v/NFVS48R06Z41UB2WbBj0bhrcrXsRDKOxs= iangodbx@EPUAKHAW0C79"
}








