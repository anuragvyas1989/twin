project_name             = "twin"
environment              = "prod"
# If the Lambda IAM role already exists (e.g. EntityAlreadyExists), set it to skip creation:
# existing_lambda_role_name = "twin-dev-lambda-role"   # for dev workspace
# existing_lambda_role_name = "twin-prod-lambda-role"  # for prod workspace
bedrock_model_id         = "amazon.nova-lite-v1:0"  # Use better model for production
lambda_timeout           = 60
api_throttle_burst_limit = 20
api_throttle_rate_limit  = 10
use_custom_domain        = true
root_domain              = "anuragdigitaltwin.com"  # Replace with your actual domain