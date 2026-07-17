# Paved-road interface for this service. Day-to-day work should not require
# remembering raw aws-cli incantations; it should be a make target.

STACK  ?= cicd-demo
REGION ?= us-east-1

.PHONY: help test run audit scan infra-validate infra-deploy infra-delete \
        pipeline-status logs release scaffold provision verify-deploy

help: ## List available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

test: ## Run the app test suite
	cd app && npm test

run: ## Run the app locally on port 3000
	cd app && npm start

audit: ## Audit production dependencies (same gate as the pipeline)
	cd app && npm audit --omit=dev --audit-level=high

scan: ## Run every pre-commit gate against the whole tree
	pre-commit run --all-files

infra-validate: ## Validate the CloudFormation template
	aws cloudformation validate-template \
	  --template-body file://infra/pipeline.yml --region $(REGION) > /dev/null && echo "template valid"

infra-deploy: ## Deploy the full stack (needs GITHUB_OWNER, CONNECTION_ARN, VPC_ID, SUBNET_ID)
	@test -n "$(GITHUB_OWNER)" || (echo "Set GITHUB_OWNER=<user>"; exit 1)
	@test -n "$(CONNECTION_ARN)" || (echo "Set CONNECTION_ARN=<codestar arn>"; exit 1)
	@test -n "$(VPC_ID)" || (echo "Set VPC_ID=vpc-..."; exit 1)
	@test -n "$(SUBNET_ID)" || (echo "Set SUBNET_ID=subnet-..."; exit 1)
	aws cloudformation deploy \
	  --template-file infra/pipeline.yml \
	  --stack-name $(STACK) \
	  --region $(REGION) \
	  --capabilities CAPABILITY_NAMED_IAM \
	  --parameter-overrides \
	    GitHubOwner=$(GITHUB_OWNER) \
	    CodeStarConnectionArn=$(CONNECTION_ARN) \
	    VpcId=$(VPC_ID) \
	    SubnetId=$(SUBNET_ID)

infra-delete: ## Tear the stack down (empty the artifact bucket first)
	aws cloudformation delete-stack --stack-name $(STACK) --region $(REGION)

pipeline-status: ## Show the state of every pipeline stage
	aws codepipeline get-pipeline-state --name $(STACK)-pipeline --region $(REGION) \
	  --query "stageStates[].{stage:stageName,status:latestExecution.status}" --output table

logs: ## Tail the app's structured logs from CloudWatch
	aws logs tail /aws-cicd/app --follow --region $(REGION)

release: ## Ship: push main and let the pipeline take it from here
	git push origin main

scaffold: ## Scaffold a new service on this golden path: make scaffold NAME=my-service DEST=../my-service
	platform/new-service.sh $(NAME) $(DEST)

provision: ## Configure deployment targets with Ansible (copy ansible/inventory.ini.example first)
	ansible-playbook -i ansible/inventory.ini ansible/provision.yml

verify-deploy: ## Verify the deployed release end to end (health, metrics, pipeline)
	python3 platform/verify_deploy.py --stack $(STACK) --region $(REGION)
