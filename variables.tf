variable "aws_region" {
  type        = string
  default     = "ap-southeast-1" # Region Singapore
  description = "AWS Region de trien khai ha tang"
}

variable "instance_id" {
  type        = string
  default     = "i-0123456789abcdef0" # Thay bang ID cua EC2 that cua ban
  description = "ID cua EC2 Instance can giam sat CPU"
}

variable "alert_email" {
  type        = string
  default     = "trang.bui26@student.passerellesnumeriques.org" 
  description = "Email nhan canh bao tu SNS"
}