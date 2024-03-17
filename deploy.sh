#!/bin/bash

# AWS and Git Variables
INSTANCE_ID="i-0340eb6dbefc41a83"
ASG_NAME="dev-asg"
LAUNCH_TEMPLATE_NAME="dev-asg-lt-20240316195517556900000004"
PRIVATE_KEY_PATH="./AutoScalingKey.pem"
EC2_PUBLIC_IP=""
FRONTEND_GIT_DIR="/var/www/html"
BACKEND_GIT_DIR="/var/www/backend"

aws configure set region ap-south-1

# 1. Start the EC2 instance
# Check current instance state
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)

# If the instance is in stopping state, wait until it's fully stopped
while [[ "$INSTANCE_STATE" == "stopping" ]]; do
    echo "Instance is in stopping state, waiting..."
    sleep 15
    INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)
done

# If the instance is stopped, start it
if [[ "$INSTANCE_STATE" == "stopped" ]]; then
    aws ec2 start-instances --instance-ids $INSTANCE_ID
    echo "Starting instance..."
fi

# 2. Wait until the EC2 instance is running
while [[ $(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text) != "running" ]]; do
    echo "Waiting for EC2 instance to start..."
    sleep 15
done
echo "EC2 instance is running."

# Fetch the public IP of the EC2 instance
EC2_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# 3. SSH into the EC2 instance and perform git pull
# Wait for SSH to become available
MAX_RETRIES=20
RETRIES=0
SSH_READY="no"

while [[ "$SSH_READY" == "no" && $RETRIES -lt $MAX_RETRIES ]]; do
    echo "Attempting to SSH & Pulling the code from git"
    sudo ssh -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ec2-user@$EC2_PUBLIC_IP "sudo sh -c 'cd $FRONTEND_GIT_DIR && git pull && cd $BACKEND_GIT_DIR && git pull && chmod +x ./gradlew && ./gradlew build && nohup java -jar build/libs/backend.jar &'">> ssh_output.log 2>&1
    if [[ $? == 0 ]]; then
        SSH_READY="yes"
    else
        RETRIES=$((RETRIES+1))
        sleep 10
    fi
done

if [[ "$SSH_READY" == "no" ]]; then
    echo "Failed to connect via SSH after multiple retries."
    exit 1
fi

echo "Creating AMI..."
AMI_NAME="GA-V1-AUTO-$(date '+%Y-%m-%d-%H%M%S')"
AMI_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "$AMI_NAME" --no-reboot --query 'ImageId' --output text)
echo "AMI ID: $AMI_ID"


# Wait until the AMI is available
while [[ $(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].State' --output text) != "available" ]]; do
    echo "Waiting for AMI to be available..."
    sleep 15
done
echo "AMI is available."

echo "Updating Launch Template..."
VERSION=$(aws ec2 create-launch-template-version --launch-template-name $LAUNCH_TEMPLATE_NAME --source-version 24 --launch-template-data "{\"ImageId\":\"$AMI_ID\"}" --query 'LaunchTemplateVersion.VersionNumber' --output text)
echo "New version of launch template: $VERSION"

# Check if there's an ongoing instance refresh
while [[ $(aws autoscaling describe-instance-refreshes --auto-scaling-group-name $ASG_NAME --query "InstanceRefreshes[?InstanceRefreshId=='$REFRESH_ID'].Status" --output text) == "InProgress" ]]; do
    echo "Instance refresh is still in progress, waiting..."
    sleep 60
done
echo "Instance refresh is completed or not in progress."

echo "Requesting an instance refresh..."
REFRESH_ID=$(aws autoscaling start-instance-refresh --auto-scaling-group-name $ASG_NAME --preferences "MinHealthyPercentage=90,InstanceWarmup=300" --query 'InstanceRefreshId' --output text)
echo "Instance refresh ID: $REFRESH_ID"

# Get a list of all AMIs created from the instance, sorted by creation date in descending order
ALL_AMIS=$(aws ec2 describe-images --filters "Name=name,Values=GA-V1-AUTO*" --query 'reverse(sort_by(Images, &CreationDate))[*].ImageId' --output text)

# Convert the AMIs list to an array
AMI_ARRAY=($ALL_AMIS)

# Skip the two latest AMIs (the first two in the array)
for ((i=2; i<${#AMI_ARRAY[@]}; i++)); do
    AMI=${AMI_ARRAY[$i]}
    # Get the associated snapshot ID(s) for the AMI
    SNAPSHOT_ID=$(aws ec2 describe-images --image-ids $AMI --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)

    # Deregister the AMI
    aws ec2 deregister-image --image-id $AMI
    echo "Deregistered AMI: $AMI"

    # Ensure SNAPSHOT_ID is not empty before attempting to delete it
    if [[ $SNAPSHOT_ID != "None" && $SNAPSHOT_ID == snap-* ]]; then
        aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
        echo "Deleted snapshot: $SNAPSHOT_ID"
    else
        echo "Invalid or missing snapshot ID for AMI: $AMI"
    fi
done

echo "Finished cleaning up old AMIs and snapshots."

# Stopping the EC2 instance
echo "Stopping the EC2 instance..."
aws ec2 stop-instances --instance-ids $INSTANCE_ID
echo "Instance is being stopped."