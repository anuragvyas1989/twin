param(
    [string]$Environment = "dev",   # dev | test | prod
    [string]$ProjectName = "twin"
)
$ErrorActionPreference = "Stop"

Write-Host "Deploying $ProjectName to $Environment ..." -ForegroundColor Green

# 1. Build Lambda package
Write-Host "Building Lambda package..." -ForegroundColor Yellow
Set-Location backend
uv run deploy.py
Set-Location ..

# 2. Terraform workspace & apply
Set-Location terraform
$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"

if (-not (terraform workspace list | Select-String $Environment)) {
    terraform workspace new $Environment
} else {
    terraform workspace select $Environment
}

# Pass -var as separate quoted args so Terraform does not see "too many positional arguments"
# Use terraform.tfvars for prod; otherwise use environment-specific tfvars if it exists (e.g. dev.tfvars, test.tfvars)
if ($Environment -eq "prod") {
    & terraform apply -var-file="terraform.tfvars" "-var=project_name=$ProjectName" "-var=environment=$Environment" -auto-approve
} elseif (Test-Path "$Environment.tfvars") {
    & terraform apply -var-file="$Environment.tfvars" "-var=project_name=$ProjectName" "-var=environment=$Environment" -auto-approve
} else {
    & terraform apply "-var=project_name=$ProjectName" "-var=environment=$Environment" -auto-approve
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Terraform apply failed. Stopping." -ForegroundColor Red
    Set-Location ..
    exit 1
}

$ApiUrl         = (terraform output -raw api_gateway_url 2>$null)
$FrontendBucket = (terraform output -raw s3_frontend_bucket 2>$null)
$CfUrl          = (terraform output -raw cloudfront_url 2>$null)
if (-not $FrontendBucket -or $FrontendBucket -match "Warning|Error|output") {
    Write-Host "Could not get Terraform outputs (apply may have failed or workspace is empty)." -ForegroundColor Red
    Set-Location ..
    exit 1
}
try { $CustomUrl = (terraform output -raw custom_domain_url 2>$null) } catch { $CustomUrl = "" }

# 3. Build + deploy frontend
Set-Location ..\frontend

# Create production environment file with API URL
Write-Host "Setting API URL for production..." -ForegroundColor Yellow
"NEXT_PUBLIC_API_URL=$ApiUrl" | Out-File .env.production -Encoding utf8

npm install
npm run build
aws s3 sync .\out "s3://$FrontendBucket/" --delete
Set-Location ..

# 4. Final summary
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "CloudFront URL : $CfUrl" -ForegroundColor Cyan
if ($CustomUrl) {
    Write-Host "Custom domain  : $CustomUrl" -ForegroundColor Cyan
}
Write-Host "API Gateway    : $ApiUrl" -ForegroundColor Cyan
