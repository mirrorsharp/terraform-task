#Get ASG instances ids
data "aws_instances" "i_id" {

  filter {
    name   = "tag:Name"
    values = ["${var.name}-asg-webserver"]
  }
  depends_on = [
    aws_autoscaling_group.lb_asg
  ]
}

output "ins_id" {
  value = data.aws_instances.i_id.ids
}