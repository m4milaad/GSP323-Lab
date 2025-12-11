#!/bin/bash

# Terminal colors
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

#----------------------------------------------#
#               Intro Banner                   #
#----------------------------------------------#                                      
echo "${CYAN}${BOLD}"
echo "███╗   ███╗██╗██╗      █████╗ ██████╗  "
echo "████╗ ████║██║██║     ██╔══██╗██╔══██╗ "
echo "██╔████╔██║██║██║     ███████║██║  ██║ "
echo "██║╚██╔╝██║██║██║     ██╔══██║██║  ██║ "
echo "██║ ╚═╝ ██║██║███████╗██║  ██║██████╔╝ "
echo "╚═╝     ╚═╝╚═╝╚══════╝╚═╝  ╚═╝╚═════╝  "
echo "${RESET}"

echo "${YELLOW}${BOLD} Stay curious. Explore cloud tech freely.${RESET}"
echo
echo "${GREEN}${BOLD}Launching setup workflow...${RESET}"
echo

#----------------------------------------------#
#       Function to read input values           #
#----------------------------------------------#

get_input() {
    local msg="$1"
    local var="$2"
    echo -ne "${CYAN}${BOLD}${msg}${RESET} "
    read value
    export "$var"="$value"
}

#----------------------------------------------#
#       User Variables                          #
#----------------------------------------------#

get_input "Dataset name:" DATASET
get_input "Bucket name:" BUCKET
get_input "Table name:" TABLE
get_input "Bucket URL 1:" BUCKET_URL_1
get_input "Bucket URL 2:" BUCKET_URL_2

echo

#----------------------------------------------#
#       Enabling & Creating API Keys            #
#----------------------------------------------#

echo "${BLUE}${BOLD}Activating API Keys service...${RESET}"
gcloud services enable apikeys.googleapis.com

echo "${GREEN}${BOLD}Generating an API key labeled 'awesome'...${RESET}"
gcloud alpha services api-keys create --display-name="awesome"

echo "${YELLOW}${BOLD}Fetching API key identifier...${RESET}"
KEY_NAME=$(gcloud alpha services api-keys list --format="value(name)" --filter="displayName=awesome")

echo "${MAGENTA}${BOLD}Extracting API key string...${RESET}"
API_KEY=$(gcloud alpha services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")

echo "${CYAN}${BOLD}Determining default compute region...${RESET}"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "${RED}${BOLD}Obtaining project ID...${RESET}"
PROJECT_ID=$(gcloud config get-value project)

echo "${GREEN}${BOLD}Resolving project number...${RESET}"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="json" | jq -r '.projectNumber')

#----------------------------------------------#
#       BigQuery & Storage setup                #
#----------------------------------------------#

echo "${BLUE}${BOLD}Creating BigQuery dataset '$DATASET'...${RESET}"
bq mk "$DATASET"

echo "${MAGENTA}${BOLD}Creating storage bucket: gs://$BUCKET${RESET}"
gsutil mb gs://$BUCKET

echo "${YELLOW}${BOLD}Downloading schema and sample files...${RESET}"
gsutil cp gs://cloud-training/gsp323/lab.csv .
gsutil cp gs://cloud-training/gsp323/lab.schema .

echo "${CYAN}${BOLD}Overwriting schema with local version...${RESET}"
cat > lab.schema <<EOF
[
    {"type":"STRING","name":"guid"},
    {"type":"BOOLEAN","name":"isActive"},
    {"type":"STRING","name":"firstname"},
    {"type":"STRING","name":"surname"},
    {"type":"STRING","name":"company"},
    {"type":"STRING","name":"email"},
    {"type":"STRING","name":"phone"},
    {"type":"STRING","name":"address"},
    {"type":"STRING","name":"about"},
    {"type":"TIMESTAMP","name":"registered"},
    {"type":"FLOAT","name":"latitude"},
    {"type":"FLOAT","name":"longitude"}
]
EOF

echo "${RED}${BOLD}Creating BigQuery table '$TABLE'...${RESET}"
bq mk --table "$DATASET.$TABLE" lab.schema

#----------------------------------------------#
#       Dataflow job for ingesting CSV          #
#----------------------------------------------#

echo "${GREEN}${BOLD}Submitting Dataflow template job...${RESET}"
gcloud dataflow jobs run awesome-jobs \
    --gcs-location gs://dataflow-templates-$REGION/latest/GCS_Text_to_BigQuery \
    --region "$REGION" \
    --worker-machine-type e2-standard-2 \
    --staging-location gs://$DEVSHELL_PROJECT_ID-marking/temp \
    --parameters \
        inputFilePattern=gs://cloud-training/gsp323/lab.csv,\
        JSONPath=gs://cloud-training/gsp323/lab.schema,\
        outputTable=$DEVSHELL_PROJECT_ID:$DATASET.$TABLE,\
        bigQueryLoadingTemporaryDirectory=gs://$DEVSHELL_PROJECT_ID-marking/bigquery_temp,\
        javascriptTextTransformGcsPath=gs://cloud-training/gsp323/lab.js,\
        javascriptTextTransformFunctionName=transform

#----------------------------------------------#
#       IAM role assignments                    #
#----------------------------------------------#

echo "${BLUE}${BOLD}Assigning IAM permissions to compute service account...${RESET}"
gcloud projects add-iam-policy-binding "$DEVSHELL_PROJECT_ID" \
    --member "serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role roles/storage.admin

echo "${MAGENTA}${BOLD}Assigning user IAM roles...${RESET}"
gcloud projects add-iam-policy-binding "$DEVSHELL_PROJECT_ID" --member="user:$USER_EMAIL" --role=roles/dataproc.editor
gcloud projects add-iam-policy-binding "$DEVSHELL_PROJECT_ID" --member="user:$USER_EMAIL" --role=roles/storage.objectViewer

echo "${CYAN}${BOLD}Updating subnet for internal Google service reachability...${RESET}"
gcloud compute networks subnets update default --region "$REGION" --enable-private-ip-google-access

#----------------------------------------------#
#       Service account setup                   #
#----------------------------------------------#

echo "${RED}${BOLD}Creating service account 'awesome'...${RESET}"
gcloud iam service-accounts create awesome --display-name "Natural Language SA"

sleep 10

echo "${GREEN}${BOLD}Generating key for service account...${RESET}"
gcloud iam service-accounts keys create ~/key.json \
  --iam-account "awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"

sleep 10

echo "${YELLOW}${BOLD}Activating service account locally...${RESET}"
export GOOGLE_APPLICATION_CREDENTIALS="/home/$USER/key.json"
gcloud auth activate-service-account awesome@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com --key-file="$GOOGLE_APPLICATION_CREDENTIALS"

#----------------------------------------------#
#       Natural Language API Test               #
#----------------------------------------------#

echo "${BLUE}${BOLD}Running entity analysis request...${RESET}"
gcloud ml language analyze-entities \
    --content="Old Norse texts describe Odin as one-eyed, long-bearded, carrying Gungnir, and cloaked beneath a wide hat." \
    > result.json

echo "${MAGENTA}${BOLD}Uploading result to bucket...${RESET}"
gsutil cp result.json "$BUCKET_URL_2"

#----------------------------------------------#
#       Speech-to-Text                          #
#----------------------------------------------#

cat > request.json <<EOF
{
  "config": {
      "encoding":"FLAC",
      "languageCode": "en-US"
  },
  "audio": {
      "uri":"gs://cloud-training/gsp323/task3.flac"
  }
}
EOF

echo "${CYAN}${BOLD}Sending audio for transcription...${RESET}"
curl -s -X POST -H "Content-Type: application/json" --data-binary @request.json \
"https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" > result.json

gsutil cp result.json "$BUCKET_URL_1"

#----------------------------------------------#
#       Video Intelligence API Setup            #
#----------------------------------------------#

echo "${MAGENTA}${BOLD}Creating secondary service account 'quickstart'...${RESET}"
gcloud iam service-accounts create quickstart

sleep 10

echo "${BLUE}${BOLD}Issuing service account key...${RESET}"
gcloud iam service-accounts keys create key.json \
  --iam-account quickstart@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com

gcloud auth activate-service-account --key-file key.json

cat > request.json <<EOF
{
   "inputUri":"gs://spls/gsp154/video/train.mp4",
   "features": ["TEXT_DETECTION"]
}
EOF

echo "${GREEN}${BOLD}Submitting video annotation request...${RESET}"
curl -s -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    https://videointelligence.googleapis.com/v1/videos:annotate \
    -d @request.json

#----------------------------------------------#
#       Dataproc Cluster Deployment             #
#----------------------------------------------#

echo "${CYAN}${BOLD}Launching Dataproc cluster 'awesome'...${RESET}"
gcloud dataproc clusters create awesome \
    --enable-component-gateway \
    --region "$REGION" \
    --master-machine-type e2-standard-2 \
    --master-boot-disk-size 100 \
    --num-workers 2 \
    --worker-boot-disk-size 100 \
    --image-version 2.2-debian12 \
    --project "$DEVSHELL_PROJECT_ID"

#----------------------------------------------#
#       Spark Job Submission                    #
#----------------------------------------------#

VM_NAME=$(gcloud compute instances list --project="$DEVSHELL_PROJECT_ID" --format="value(name)" --limit=1)
ZONE=$(gcloud compute instances list "$VM_NAME" --format="value(zone)")

echo "${BLUE}${BOLD}Copying data into VM and HDFS...${RESET}"
gcloud compute ssh "$VM_NAME" --zone "$ZONE" --quiet \
    --command="hdfs dfs -cp gs://cloud-training/gsp323/data.txt /data.txt"

gcloud compute ssh "$VM_NAME" --zone "$ZONE" --quiet \
    --command="gsutil cp gs://cloud-training/gsp323/data.txt /data.txt"

echo "${MAGENTA}${BOLD}Submitting Spark PageRank job...${RESET}"
gcloud dataproc jobs submit spark \
  --cluster=awesome \
  --region="$REGION" \
  --class=org.apache.spark.examples.SparkPageRank \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
  --project="$DEVSHELL_PROJECT_ID" \
  -- /data.txt

echo
echo "${GREEN}${BOLD}All tasks completed successfully.${RESET}"
echo

#----------------------------------------------#
#                 Cleanup                       #
#----------------------------------------------#

cleanup_files() {
    for file in *; do
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            rm "$file"
            echo "Removed temporary file: $file"
        fi
    done
}
cleanup_files
