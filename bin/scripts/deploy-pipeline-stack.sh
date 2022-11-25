#!/usr/bin/env bash

######################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. #
# SPDX-License-Identifier: MIT-0                                     #
######################################################################

GREEN="\033[1;32m"
YELLOW="\033[1;33m"

#############################################################################
# CodePipeline resources
##############################################################################

echo -e "${GREEN}Exporting the cloudformation stack outputs...."

export AWS_ACCOUNT_ID="253739243553"
export AWS_DEFAULT_REGION="us-east-2"
export AWS_REGION="us-east-2"

# export CODE_REPO_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`repositoryName`].OutputValue' --output text)
# export CODE_REPO_URL=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`repositoryCloneUrlHttp`].OutputValue' --output text)
export ECR_REPO_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`ecrRepoName`].OutputValue' --output text)
export ECR_REPO_URI=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`ecrRepoUri`].OutputValue' --output text)
# export CODE_BUILD_PROJECT_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`codeBuildProjectName`].OutputValue' --output text)
export ECS_TASK_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name BlueGreenContainerImageStack --query 'Stacks[*].Outputs[?ExportName==`ecsTaskRoleArn`].OutputValue' --output text)

echo -e "${GREEN}Initiating the code build to create the container image...."

IMAGE_TAG=$(git log --pretty=format:'%h' -n 1)
cd nginx-sample
docker build -t ${ECR_REPO_URI}:latest -t ${ECR_REPO_URI}:${IMAGE_TAG} -f Dockerfile .
docker tag nginx-sample:latest ${ECR_REPO_URI}:latest
docker tag nginx-sample:latest ${ECR_REPO_URI}:${IMAGE_TAG}

echo -e "${GREEN}Docker build and tagging completed on `date`"
echo -e "${GREEN}Pushing the docker images..."
docker push $ECR_REPO_URI:latest
docker push $ECR_REPO_URI:$IMAGE_TAG
echo -e "${GREEN}Update the $ECR_REPO_URI:$IMAGE_TAG in task definition..."
echo -e "${GREEN}Container image to be used $ECR_REPO_URI:$IMAGE_TAG"
sed -i 's@REPOSITORY_URI@'$ECR_REPO_URI'@g' taskdef.json
sed -i 's@IMAGE_TAG@'$IMAGE_TAG'@g' taskdef.json
echo -e "${GREEN}update the REGION in task definition..."
sed -i 's@AWS_REGION@'$AWS_REGION'@g' taskdef.json
echo -e "${GREEN}update the roles in task definition..."
sed -i 's@TASK_EXECUTION_ARN@'$ECS_TASK_ROLE_ARN'@g' taskdef.json

cd ..

# export BUILD_ID=$(aws codebuild start-build --project-name $CODE_BUILD_PROJECT_NAME --query build.id --output text)
# BUILD_STATUS=$(aws codebuild batch-get-builds --ids $BUILD_ID --query 'builds[*].buildStatus' --output text | xargs)

# # Wait till the CodeBuild status is SUCCEEDED
# while [ "$BUILD_STATUS" != "SUCCEEDED" ];
# do
#   sleep 10
#   BUILD_STATUS=$(aws codebuild batch-get-builds --ids $BUILD_ID --query 'builds[*].buildStatus' --output text | xargs)
#   echo -e "${YELLOW}Awaiting SUCCEEDED status....Current status: ${BUILD_STATUS}"
# done

# echo -e "${GREEN}Completed CodeBuild...ECR image is available"

echo -e "${GREEN}Start deployment of resources...."

export API_NAME=nginx-sample
export CONTAINER_PORT=80
export CIDR_RANGE=10.0.0.0/16
# export ECR_REPO_NAME="${ECR_REPO_NAME}:${IMAGE_TAG}"
cdk --app "npx ts-node bin/pipeline-stack.ts" deploy --require-approval never
export ALB_DNS=$(aws cloudformation describe-stacks --stack-name BlueGreenPipelineStack --query 'Stacks[*].Outputs[?ExportName==`ecsBlueGreenLBDns`].OutputValue' --output text)

echo -e "${GREEN}Completed building the CodePipeline resources...."

echo -e "${GREEN}Let's curl the below URL for API...."

echo "http://$ALB_DNS"
curl http://$ALB_DNS

export ARTIFACTS_BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenPipelineStack --query 'Stacks[*].Outputs[?ExportName==`artifactsBucketName`].OutputValue' --output text)
export TASK_DEF_ARN=$(aws cloudformation describe-stacks --stack-name BlueGreenPipelineStack --query 'Stacks[*].Outputs[?ExportName==`taskDefinitionArn`].OutputValue' --output text)
export DEPLOYMENT_GROUP_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenPipelineStack --query 'Stacks[*].Outputs[?ExportName==`deploymentGroupName`].OutputValue' --output text)
export APPLICATION_NAME=$(aws cloudformation describe-stacks --stack-name BlueGreenPipelineStack --query 'Stacks[*].Outputs[?ExportName==`applicationName`].OutputValue' --output text)
echo -e "${YELLOW}ARTIFACTS_BUCKET_NAME : ${ARTIFACTS_BUCKET_NAME}, APPLICATION_NAME : ${APPLICATION_NAME}, DEPLOYMENT_GROUP_NAME : ${DEPLOYMENT_GROUP_NAME}, TASK_DEF_ARN : ${TASK_DEF_ARN}"

echo -e "${GREEN}Update appspec.yaml..."
sed -i 's@TASK_DEFINITION@'$TASK_DEF_ARN'@g' nginx-sample/appspec.yaml
echo -e "${GREEN}Update create-deployment.json..."
sed -i 's@APPLICATION_NAME@'$APPLICATION_NAME'@g' nginx-sample/create-deployment.json
sed -i 's@DEPLOYMENT_GROUP_NAME@'$DEPLOYMENT_GROUP_NAME'@g' nginx-sample/create-deployment.json
sed -i 's@ARTIFACT_BUCKET_NAME@'$ARTIFACTS_BUCKET_NAME'@g' nginx-sample/create-deployment.json

echo -e "${GREEN}Upload deployment artifacts to S3..."
aws s3 cp nginx-sample/appspec.yaml "s3://${ARTIFACTS_BUCKET_NAME}/codedeploy/" --region $AWS_REGION --sse aws:kms --quiet
aws s3 cp nginx-sample/taskdef.json "s3://${ARTIFACTS_BUCKET_NAME}/codedeploy/" --region $AWS_REGION --sse aws:kms --quiet

export DEPLOYMENT_ID=$(aws deploy create-deployment --cli-input-json file://nginx-sample/create-deployment.json --region ${AWS_REGION} | jq -r .deploymentId)

echo -e "${GREEN}Deployment triggered. Please navigate to https://${AWS_REGION}.console.aws.amazon.com/codesuite/codedeploy/deployments/${DEPLOYMENT_ID}?region=${AWS_REGION} to check status.."
