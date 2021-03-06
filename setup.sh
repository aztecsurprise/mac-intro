#! /bin/bash

# gcp project
echo ""
export PROJECT="$(gcloud config get-value project)"
echo "Your current configured gcloud project is $PROJECT"
echo ""
echo "Note! This will take some time to deploy and gitlab takes time to completely come up."
echo "Prepare to be wating at least 30 minutes from start to finish."
sleep 2
echo ""

# sets git specific variables
export URL="$(git config --get remote.origin.url)"
export EMAIL="$(git config --get user.email)"

# if a git email isnt configured for the user, it will exit and refer them to do so
if [[ -z $EMAIL ]]
then
    echo ""
    echo "This implmentation relies on git and requires having global user specific variables set."
    echo "Before executing run the following: "
    echo "
    git config --global user.email \"EMAIL\"
    git config --global user.name \"USERNAME\"
    "
    echo ""
    sleep 2
    exit 0
fi

echo "Your Git user.email global variable is set to : $EMAIL"
echo ""
sleep 2

basename=$(basename $URL)
re="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/(.+).git$"
if [[ $URL =~ $re ]]; then
    USERNAME=${BASH_REMATCH[4]}
    REPO=${BASH_REMATCH[5]}
fi
echo ""
echo "Git is configured for user $USERNAME on the $REPO repository."
echo ""
sleep 2


TOKEN=$(cat token)
if [[ -z $TOKEN ]]
then
    # prompts for github personal access token
    read -p "Enter a github personal access token: " TOKEN
    cat <<EOF >> token 
    $TOKEN
EOF
fi

# checks if terraform state file exists, if it does - sets the cluster_name to the output in the state file
if [[ ! -f './terraform.tfstate' ]]
then
    read -p "Enter a cluster name: " NAME
fi
if [[ -f './terraform.tfstate' ]]
then
    export NAME="$(cat terraform.tfstate|jq -r '.outputs.cluster_name.value')"
    echo "Your existing cluster is called $NAME"
    echo ""
    sleep 2
fi

# creates gcp project to use for example
echo ""
terraform fmt --recursive
terraform init
sleep 5
terraform apply -var "repo=${REPO}" -var "github_token=${TOKEN}" -var "username=${USERNAME}" -var "certmanager_email=${EMAIL}" -var "cluster_name=${NAME}" -var "project_id=${PROJECT}" -auto-approve
sleep 5


# gets k8s cluster name and generates credentials
export REGION=$(cat terraform.tfstate|jq -r '.outputs.location.value')

if [[ -z $(kubectl get secrets -o json|jq -r '.items[].metadata.name'|grep my-secret) ]]
then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=fake.gitlab.com"
    kubectl create secret tls my-secret --key="tls.key" --cert="tls.crt"
    rm tls.*
fi

if [[ -z $(kubectl get clusterrolebinding cluster-admin-binding) ]]
then
    echo "Setting current user as cluster admin"
    echo ""
    sleep 2
    kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin \
    --user $(gcloud config get-value account)
    echo ""
fi