#!/bin/bash
# Deploy whole infrastructure of DevSecOps openhack.

IFS=$'\n\t'

echo "$@"

usage() { echo "Usage provision_azure_resources.sh -l <resourceGroupLocation> -t <teamNumber>" 1>&2; exit 1; }

declare resourceGroupLocation=""
declare teamName="devsecopsohlite"
declare teamNumber=""

while getopts ":l:t:o:d:" arg; do
    case "${arg}" in
        l)
            resourceGroupLocation=${OPTARG}
        ;;
        t)
            teamNumber=${OPTARG}
        ;;
    esac
done

shift $((OPTIND-1))



declare resourceGroupName="${teamName}${teamNumber}rg";
declare keyVaultName="${teamName}${teamNumber}kv";
declare registryName="${teamName}${teamNumber}acr";
declare webAppName="${teamName}${teamNumber}web";
declare storageAccountName="${teamName}${teamNumber}sa"
declare devopsProjectName="${teamName}${teamNumber}";
declare imageName="eshoponweb"
declare tenantId=$(az account show --query tenantId -o tsv)
declare subscriptionId=$(az account show --query id -o tsv)
declare subscriptionName=$(az account show --query name -o tsv)

echo "=========================================="
echo " VARIABLES"
echo "=========================================="
echo "subscriptionId            = "${subscriptionId}
echo "subscriptionName          = "${subscriptionName}
echo "tenantId                  = "${tenantId}
echo "resourceGroupLocation     = "${resourceGroupLocation}
echo "resourceGroupName         = "${resourceGroupName}
echo "teamName                  = "${teamName}
echo "teamNumber                = "${teamNumber}
echo "keyVaultName              = "${keyVaultName}
echo "registryName              = "${registryName}
echo "storageAccountName        = "${storageAccountName}
echo "webAppName                = "${webAppName}
echo "=========================================="

# create resourceGroup

az group create -n $resourceGroupName -l $resourceGroupLocation

# Provision KeyVault
az keyvault create -g $resourceGroupName --name $keyVaultName --location $resourceGroupLocation

# Provision ACR
az acr create -g $resourceGroupName --name $registryName --location $resourceGroupLocation --sku Basic --admin-enabled true
az acr update -n $registryName --admin-enabled true

# Fetch the data of ACR
cred=$(az acr credential show -n $registryName)
acrUsername=$(echo $cred | jq .username | xargs )
acrPassword=$(echo $cred | jq .passwords[0].value | xargs )
conf=$(az acr show -n $registryName)
acrLoginServer=$(echo $conf | jq .loginServer | xargs )

acrImageName=${acrLoginServer}/${imageName}

echo "ACR UserName: $acrUsername"
echo "ACR Password: $acrPassword"
echo "ACR Login Server: $acrLoginServer"
echo "Image Name: $acrImageName"

# Build and Publish images
pushd .
cd ..
docker build . -t ${acrImageName}:latest
docker login -u ${acrUsername} -p ${acrPassword} ${acrLoginServer}
docker push ${acrImageName}:latest
popd

# Provision Storage Account

az storage account create --name $storageAccountName --location $resourceGroupLocation --resource-group $resourceGroupName --sku Standard_LRS

# Provision WebApp

# App Service Plan
declare appServicePlanName="${webAppName}plan"
az appservice plan create -n ${appServicePlanName} -g $resourceGroupName --is-linux -l $resourceGroupLocation --sku S1

# WebApp
az webapp create -n $webAppName -g $resourceGroupName -p $appServicePlanName -i $acrImageName
az webapp config container set -n $webAppName -g $resourceGroupName -c $acrImageName -r $acrLoginServer -u $registryName -p $acrPassword

# Activate Docker Container Logging
az webapp log config -n $webAppName -g $resourceGroupName --web-server-logging filesystem

# Setup Continuous Deployment (https://docs.microsoft.com/en-us/azure/app-service/containers/app-service-linux-cli)
WEB_HOOK_URL=$(az webapp deployment container config -n ${webAppName} -g ${resourceGroupName} -e true | jq .CI_CD_URL | xargs )
az acr webhook create -n WebAppDeployment -r ${registryName} --uri ${WEB_HOOK_URL} --actions push

# output ACR info
jq -n --arg acrU $acrUsername --arg acrP $acrPassword --arg acrLs $acrLoginServer --arg acrIn $acrImageName '{
    acrUserName: $acrU, acrPassword: $acrP, acrLoginServer: $acrLs, acrImageName: $acrIn}' > acr.json

# Create Service Principal and output to sp_config.json
export SP_JSON=`az ad sp create-for-rbac --role="Contributor" -o json`
echo $SP_JSON | jq --arg subId ${subscriptionId} --arg subName ${subscriptionName} '. + {subscriptionId: $subId, subscriptionName: $subName}' | jq . > subscription.json

# Add the required kv access-policy for the service principal
declare sp=$(cat subscription.json | jq .appId | xargs)
az keyvault set-policy -n $keyVaultName --object-id $(az ad sp show --id ${sp} | jq .objectId | xargs ) --secret-permissions get list --key-permissions get list
 