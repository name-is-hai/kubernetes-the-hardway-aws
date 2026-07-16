module "cp_nlb" {
  source             = "../../modules/load-balancers"
  nlb_name           = "cp-nlb"
  cp_instance_ids    = module.control_plane_intances.instance_ids
  nlb_subnets_ids    = values(module.vpc.private_subnet_ids)
  vpc_id             = module.vpc.vpc_id
  nlb_tg_port        = 6443
  security_group_ids = [module.api_nlb_security_group.security_group_id]
}

resource "aws_lb" "public_network" {
  name               = "public-network-load-balancer"
  load_balancer_type = "network"

  security_groups = [module.public_nlb_security_group.security_group_id]
  subnets         = values(module.vpc.public_subnet_ids)
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public_network.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_http_network.arn
  }

}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.public_network.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_https_network.arn
  }
}

resource "aws_lb_target_group" "public_http_network" {
  name     = "public-http-network-tg"
  port     = "30080"
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    protocol = "TCP"
    port     = "30080"
  }
}

resource "aws_lb_target_group" "public_https_network" {
  name     = "public-https-network-tg"
  port     = "30443"
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    protocol = "TCP"
    port     = "30443"
  }
}

resource "aws_lb_target_group_attachment" "public_http_network" {
  count = length(module.worker_intances.instance_ids)

  target_group_arn = aws_lb_target_group.public_http_network.arn
  target_id        = module.worker_intances.instance_ids[count.index]
  port             = "30080"
}

resource "aws_lb_target_group_attachment" "public_https_network" {
  count = length(module.worker_intances.instance_ids)

  target_group_arn = aws_lb_target_group.public_https_network.arn
  target_id        = module.worker_intances.instance_ids[count.index]
  port             = "30443"
}
