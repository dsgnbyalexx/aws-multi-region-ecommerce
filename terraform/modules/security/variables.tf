variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the security groups in."
  type        = string
}

variable "app_port" {
  description = "Port the application listens on inside each instance."
  type        = number
  default     = 3000
}

variable "allowed_ingress_cidrs" {
  description = "Who may reach the load balancer. Use your own IP (x.x.x.x/32) while testing; 0.0.0.0/0 for a public site."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
