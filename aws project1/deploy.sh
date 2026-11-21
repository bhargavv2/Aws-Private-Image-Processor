#!/usr/bin/env bash
# ==============================================================================
# Deployment Script: Automated Private Image/Document Processor
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}====================================================================${NC}"
echo -e "${BLUE}${BOLD}  AWS Free Tier - Automated Private Image/Document Processor        ${NC}"
echo -e "${BLUE}${BOLD}  Enterprise Terraform Deployment                                    ${NC}"
echo -e "${BLUE}${BOLD}====================================================================${NC}"

# 1. Verify Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}[ERROR] Terraform is not found in PATH.${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Terraform is installed: $(terraform -version | head -n 1)${NC}"

# 2. Check AWS Credentials
echo -e "\n${BLUE}[i] Checking AWS credentials...${NC}"
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ ! -f "$HOME/.aws/credentials" ]; then
    echo -e "${YELLOW}[!] AWS credentials not detected in terminal environment.${NC}"
    echo -e "${YELLOW}Since you are already logged into AWS Console in Chrome:${NC}"
    echo -e "  1. In AWS Console search bar, type: ${BOLD}IAM${NC} and go to ${BOLD}Users${NC} (or click your username at top-right -> Security credentials)"
    echo -e "  2. Click ${BOLD}Create access key${NC} -> Select ${BOLD}Command Line Interface (CLI)${NC}"
    echo -e "  3. Copy your Access Key ID and Secret Access Key, then run:"
    echo -e "     ${BOLD}export AWS_ACCESS_KEY_ID=\"<your-key-id>\"${NC}"
    echo -e "     ${BOLD}export AWS_SECRET_ACCESS_KEY=\"<your-secret-key>\"${NC}"
    echo -e "     ${BOLD}export AWS_DEFAULT_REGION=\"us-east-1\"${NC}"
    echo -e "\nThen re-run this script: ${BOLD}./deploy.sh${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] AWS credentials found!${NC}"

# 3. Terraform Lifecycle
ACTION="${1:-apply}"

case "$ACTION" in
    init)
        echo -e "\n${BLUE}[i] Initializing Terraform...${NC}"
        terraform init
        ;;
    plan)
        echo -e "\n${BLUE}[i] Generating Terraform Plan...${NC}"
        terraform init -upgrade
        terraform plan
        ;;
    apply)
        echo -e "\n${BLUE}[i] Deploying Infrastructure with Terraform...${NC}"
        terraform init
        terraform apply -auto-approve
        echo -e "\n${GREEN}[✓] Deployment complete!${NC}"
        terraform output
        ;;
    destroy)
        echo -e "\n${YELLOW}[!] Destroying Infrastructure...${NC}"
        terraform destroy -auto-approve
        echo -e "${GREEN}[✓] Teardown complete. All Free Tier resources cleaned up.${NC}"
        ;;
    *)
        echo -e "Usage: $0 [init|plan|apply|destroy]"
        exit 1
        ;;
esac
