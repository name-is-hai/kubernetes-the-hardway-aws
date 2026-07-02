resource "aws_lb" "network" {
  name               = var.nlb_name
  load_balancer_type = "network"
  internal           = true

  subnets = var.nlb_subnets_ids
}

resource "aws_lb_listener" "network" {
  load_balancer_arn = aws_lb.network.arn
  port              = var.nlb_tg_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.network.arn
  }
}

resource "aws_lb_target_group" "network" {
  name     = "${var.nlb_name}-target-group"
  port     = var.nlb_tg_port
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol = "TCP"
    port     = tostring(var.nlb_tg_port)
  }
}

resource "aws_lb_target_group_attachment" "network" {
  count = length(var.cp_instance_ids)

  target_group_arn = aws_lb_target_group.network.arn
  target_id        = var.cp_instance_ids[count.index]
  port             = var.nlb_tg_port
}
