provider "aws" {
  region = var.aws_region
}

# ==========================================
# BÀI TẬP 2 (PHẦN 1): CẤU HÌNH IAM ROLE CHO CLOUDWATCH AGENT
# ==========================================

# 1. Tạo Role cho phép EC2 có thể tương tác với các dịch vụ AWS
resource "aws_iam_role" "ec2_cw_agent_role" {
  name = "ec2-cloudwatch-agent-extensions-role"

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

# 2. Gắn chính sách bắt buộc "CloudWatchAgentServerPolicy" vào Role (Đúng như ảnh yêu cầu)
resource "aws_iam_role_policy_attachment" "cw_agent_policy_attach" {
  role       = aws_iam_role.ec2_cw_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Hỗ trợ kết nối Session Manager nếu cần
}

resource "aws_iam_role_policy_attachment" "cw_agent_server_policy_attach" {
  role       = aws_iam_role.ec2_cw_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" # Chính sách cốt lõi của bài 2
}

# 3. Tạo Instance Profile để đính kèm Role này vào thực thể EC2
resource "aws_iam_instance_profile" "ec2_cw_agent_profile" {
  name = "ec2-cloudwatch-agent-instance-profile"
  role = aws_iam_role.ec2_cw_agent_role.name
}


# ==========================================
# PHẦN KHỞI TẠO HẠ TẦNG EC2 CƠ BẢN
# ==========================================

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-monitoring-sg-combined"
  description = "Security group mo cong 22 de dang nhap"

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "my_test_ec2" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true 

  # ĐÂY LÀ ĐIỂM KẾT NỐI: Gắn quyền CloudWatch Agent vừa tạo ở trên vào con EC2 này
  iam_instance_profile = aws_iam_instance_profile.ec2_cw_agent_profile.name

  tags = {
    Name = "EC2-Combined-Lab-Testing"
  }
}


# ==========================================
# BÀI TẬP 1: SNS TOPIC & SUBSCRIPTION
# ==========================================

resource "aws_kms_key" "sns_encryption_key" {
  description             = "Khoa KMS ma hoa du lieu cho SNS Topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Quyền mặc định: Cho phép tài khoản Root quản lý khóa
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # QUYỀN BỔ SUNG: Cho phép CloudWatch Alarms sử dụng khóa để giải mã/mã hóa khi bắn SNS
        Sid    = "Allow CloudWatch Alarms to use the key"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })
}
resource "aws_sns_topic" "cpu_alert_topic" {
  name              = "ec2-cpu-high-alert-topic"
  kms_master_key_id = aws_kms_key.sns_encryption_key.id
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cpu_alert_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


# ==========================================
# BÀI TẬP 1: CLOUDWATCH ALARM
# ==========================================

resource "aws_cloudwatch_metric_alarm" "cpu_high_alarm" {
  alarm_name          = "ec2-high-cpu-utilization-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    InstanceId = aws_instance.my_test_ec2.id 
  }

  alarm_description = "Canh bao tu dong khi CPU cua EC2 vuot qua 80% trong vao 5 phut lien tuc."
  alarm_actions     = [aws_sns_topic.cpu_alert_topic.arn]
  ok_actions        = [aws_sns_topic.cpu_alert_topic.arn]
}