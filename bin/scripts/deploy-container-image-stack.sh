#!/usr/bin/env bash

######################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. #
# SPDX-License-Identifier: MIT-0                                     #
######################################################################

GREEN="\033[1;32m"
YELLOW="\033[1;33m"

#############################################################################
# Container image resources
##############################################################################
echo -e "${GREEN}Start building the container image stack resources...."

export AWS_ACCOUNT_ID="253739243553"
export AWS_DEFAULT_REGION="us-east-2"
export CODE_REPO_NAME=nginx-sample

cdk bootstrap aws://$AWS_ACCOUNT_ID/$AWS_DEFAULT_REGION

cdk --app "npx ts-node bin/container-image-stack.ts" deploy --require-approval never

echo -e "${GREEN}Completed building the container image stack resources...."

