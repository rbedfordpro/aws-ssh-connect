#!/bin/bash

export AWS_PAGER=""

# check for aws cli, throw up install url and exit if not found
if ! command -v aws &> /dev/null
then
    echo "aws cli could not be found, please install aws-cli"
    echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit
fi
# check for session manager plugin, throw up install url and exit if not found
if ! command -v session-manager-plugin &> /dev/null
then
    echo "ssm plugin could not be found, please install session-manager-plugin"
    echo "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    exit
fi

socket=$(mktemp 2>/dev/null || mktemp -t 'mytmpdir')
rm ${socket} 

DATE=$(date +%s)
HOSTNAME=$(hostname)


exit_code=0

while [ $# -gt 0 ]; do

  if [[ $1 == *"--"* ]]; then
      param="${1/--/}"
      declare $param="$2"
      if [ $param == "notunnel" ]; then
        notunnel=true
      fi
      if [ $param == "t" ]; then
        environment="Test"
      elif [ $param == "p" ]; then
        environment="Prod"
      elif [ $param == "d" ]; then
        environment="Dev"
      fi
  fi

  shift
done


createkey_upload () {
  echo "\nDetermining Availability Zone..."
  az=`aws ec2 describe-instances --instance-ids $instanceid --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text --profile $PROFILE`
  retVal=$?
  if [ $retVal -ne 0 ]; then
      exit $retVal
  fi

  echo "Generating ssh-key..."
  keyFileName="$USERNAME.$PROFILE.$HOSTNAME-$DATE"

  retVal=$?
  if [ $retVal -ne 0 ]; then
      rm ~/.ssh/$keyFileName  ~/.ssh/$keyFileName .pub
      exit $retVal
  fi

  ssh-keygen -f ~/.ssh/$keyFileName -q -N ''
  echo "Uploading ssh-key to bastion (valid to use for connection for 60s starting now)..."
  aws ec2-instance-connect send-ssh-public-key \
    --instance-id $instanceid --availability-zone $az \
    --instance-os-user $USERNAME --ssh-public-key file://~/.ssh/$keyFileName.pub \
    --profile $PROFILE
}

createmenu () {
  select selected_option; do
    if [[ "$REPLY" == 0 ]]; then 
      break;
    fi
    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($#)) ]; then
      break;
    else
      echo "Please make a valid selection (0-$#)."
    fi
  done
}

checkport () {
  lsof_data=$(lsof -i:$localport | egrep "ESTABLISHED|LISTEN")
}

#>/dev/null
if [ -z "$PROFILE" ]
then
  echo "AWS profile: "
  read PROFILE
fi

if [ -z "$environment" ]
then
  echo "No Environment specified."
  environment_filter=""
else
  environment_filter="Name=tag:Environment,Values='${environment}'"
fi

if [ -z "$username" ]; then
  USERNAME=ssm-user
else
  USERNAME=$username
fi

if [ -z "$instanceid" ]; then
  echo "** BASTION LOGIN INFO **"
  BASTIONS=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,InstanceID:InstanceId}" \
  --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values='*Bastion*'" $environment_filter \
  --output text --profile $PROFILE)

  IFS=$'\n' read -rd '' -a BASTIONLIST <<<"$BASTIONS"
  # If only one bastion is found: use it, if 0: manual selection, if >1: menu.
  num_bastions=${#BASTIONLIST[@]}

  if [ $num_bastions -gt 1 ]; then
    echo "Select Bastion InstanceID (0 to input manually):"
    createmenu "${BASTIONLIST[@]}"
    instanceid=$(echo $selected_option | cut -d " " -f1)
  else
    instanceid=$(echo ${BASTIONLIST[@]} | cut -d " " -f1)
    if [ "$instanceid" != "" ]; then
      echo "Connecting to $environment Environment Bastion: ${BASTIONLIST[@]} as $USERNAME"
    else
      echo "Unable to find Bastion with Environment Tag: $environment"
    fi
  fi
fi

if [ -z "$instanceid" ]; then
  echo "Manually Input Bastion InstanceID: "
  read instanceid
fi

if [ "$notunnel" ]; then
  # Create the temp-key and upload it to the ec2 bastion box
  createkey_upload
  ssh -i ~/.ssh/$keyFileName -S ${socket} $USERNAME@$instanceid \
  -o "IdentitiesOnly yes" \
  -o "UserKnownHostsFile=/dev/null" \
  -o "StrictHostKeyChecking=no" \
  -o ProxyCommand="aws ssm start-session --target \"${instanceid}\" --document-name AWS-StartSSHSession --profile $PROFILE"

  rm ~/.ssh/$keyFileName ~/.ssh/$keyFileName.pub
  exit
fi

# if [ -z "$rdsurl" ] && [ -z "$rdsport"]; then
#   ARNS=$(aws rds describe-db-instances --query "DBInstances[].DBInstanceArn" --output text --profile $PROFILE)
#   for line in $ARNS; do
#     echo $line
#     TAGS=$(aws rds list-tags-for-resource --resource-name "$line" --output text --profile $PROFILE)
#     for tag in $TAGS; do
#       echo $tag
#     done
#   done
# fi

if [ -z "$rdsurl" ] && [ -z "$rdsport"]; then
  echo "\n** RDS CONNECTION INFO **"
  RDS=$(aws rds describe-db-instances --query "DBInstances[*].Endpoint.[Address,Port]" --output text --profile $PROFILE)
  IFS=$'\n' read -rd '' -a RDSLIST <<<"$RDS"
  echo "Select database (0 to input manually):"
  createmenu "${RDSLIST[@]}"
  rdsurl=$(echo $selected_option | cut -d " " -f1)
  rdsport=$(echo $selected_option | cut -d " " -f2)
fi

if [ -z "$rdsurl" ]; then
  echo "RDS Instance Url: "
  read rdsurl
fi

if [ -z "$rdsport" ]; then
  echo "RDS Instance port: "
  read rdsport
fi

if [ -z "$localport" ]; then
  echo "Localhost Tunnel port: "
  read localport
fi

while [ "$localport" == "$rdsport" ]; do
  echo "Localhost Tunnel Port (cannot be same as rdsport: $rdsport): "
  read localport
done

# quick sanity check to see if specified localport is already in use
checkport
while [[ ! -z $lsof_data ]]; do
  echo "Localport: $localport already in use - input a different port number:"
  read localport
  checkport
done

# Create the temp-key and upload it to the ec2 bastion box
createkey_upload

cleanup () {
    echo "running cleanup..."
    if [ -S ${socket} ]; then
        echo
        echo "Sending exit signal to SSH process"
        ssh -S ${socket} -O exit $USERNAME@$instanceid
        rm ~/.ssh/$keyFileName ~/.ssh/$keyFileName.pub
    fi
    exit $exit_code
}



echo "Creating tunnel through ${instanceid} to ${rdsurl}..."
echo "Use -h 127.0.0.1 -P ${localport} to connect to the database."
shift
ssh -i ~/.ssh/$keyFileName -N -f -M -S ${socket} -L $localport:$rdsurl:$rdsport $USERNAME@$instanceid \
  -o "IdentitiesOnly yes" \
  -o "UserKnownHostsFile=/dev/null" \
  -o "StrictHostKeyChecking=no" \
  -o ProxyCommand="aws ssm start-session --target \"${instanceid}\" --document-name AWS-StartSSHSession --profile $PROFILE"

ssh -S ${socket} -O check $USERNAME@$instanceid

echo "Tunnel Created!"

read -rsn1 -p "Press any key to close session."; echo

#ssh -S ${socket} -O exit $USERNAME@${instanceid}

#rm ~/.ssh/$keyFileName ~/.ssh/$keyFileName.pub

trap cleanup EXIT TERM
