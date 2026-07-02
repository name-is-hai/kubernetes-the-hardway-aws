# packer
resource "aws_iam_role" "packer_ssm_role" {
  name = "packer-ssm-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "packer_ssm_attach" {
  role       = aws_iam_role.packer_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "packer_ssm_profile" {
  name = "packer-ssm-instance-profile"
  role = aws_iam_role.packer_ssm_role.name
}

# control-plane
resource "aws_iam_role" "control_plane_ssm_role" {
  name = "control-plane-ssm-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "control_plane_ssm_attach" {
  role       = aws_iam_role.control_plane_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "control_plane_ssm_profile" {
  name = "control-plane-ssm-instance-profile"
  role = aws_iam_role.control_plane_ssm_role.name
}

# worker
resource "aws_iam_role" "worker_ssm_role" {
  name = "worker-ssm-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_ssm_attach" {
  role       = aws_iam_role.worker_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker_ssm_profile" {
  name = "worker-ssm-instance-profile"
  role = aws_iam_role.worker_ssm_role.name
}
