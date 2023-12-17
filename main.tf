data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
#EC2 instance creation

resource "aws_instance" "test_instance" {
  ami           = data.aws_ami.linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "Automation"
  }
}

# IAM Policy for Lambda to Start EC2 Instances
resource "aws_iam_policy" "lambda_start_ec2_policy" {
  name        = "LambdaStartEC2Policy"
  description = "IAM policy for Lambda to start EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:StartInstances",
          "ec2:DescribeInstances"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name = "LambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_start_ec2_policy.arn
  role       = aws_iam_role.lambda_role.name
}

# Lambda Function

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/startEc2Instance/python.py"
  output_path = "ec2-automation.zip"
}

resource "aws_lambda_function" "my_lambda_function" {
  function_name = "MyLambdaFunction"
  role          = aws_iam_role.lambda_role.arn
  handler       = "python.lambda_handler"
  runtime       = "python3.10"
  filename      = "ec2-automation.zip"
}

#create event rule to trigger lambda function when instance is stopped 

resource "aws_cloudwatch_event_rule" "ec2_stop_protection" {
  name        = "EC2-Stop-Protection"
  description = "Capture EC2 Stop Events"

  event_pattern = jsonencode({
    "source" : ["aws.ec2"],
    "detail-type" : ["EC2 Instance State-change Notification"],
    "detail" : {
      "state" : ["stopping", "stopped"],
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.ec2_stop_protection.name
  arn  = aws_lambda_function.my_lambda_function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_stop_protection.arn
}
