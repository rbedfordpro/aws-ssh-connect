# aws-ssh-connect
Bash script used to make connection to AWS using a temp key and session manager

## Bastion set up steps

[Bastion Setup](README-bastion-setup.md)

## What it does (why are we doing this??)

In order to further secure our internal access, we are doing away with one 'overall' ssh-key that we have been using to login to
the bastion boxes (and create the RDS tunnels).

This script will create a temporary ssh-key to be used for a temp-use tunnel session. The key is valid to be used for connection
for 60 seconds, then it cannot be used to connect. Any connection made during that 60-second window remains valid until disconnected.

It will then initiate the ssh tunnel through the specified bastion, to the specified database, using the specified ports for forwarding.

## Setup

### AWS

Script requires AWS CLI be installed and have profiles set up properly for access to environments

1. Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. Install [SSM Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
2. Set up Profiles in ~/.aws/config

Example:
```
[profile prodcli]
role_arn = arn:aws:iam::<account-you-want-to-access-id>:role/<cross-role-in-account-you-want-to-access>
source_profile = <your-default-dev-profile>
mfa_serial = arn:aws:iam::<mfa-info>
region = us-east-1
```

### RDS

You will need your own login for whichever database you need to access

## Running Script

This script can be run with or without options. If no options are provided (or one is missing), then the script will ask for data as it needs it.

### Calling the Script

`sh connect.sh`

`sh connect.sh --PROFILE robdev --notunnel`

`sh connect.sh --PROFILE robdev --instanceid i-234243lblahblah --rdsport 3306 --localport 3303`

`sh connect.sh --PROFILE robdev --environment Test --rdsport 3306 --localport 3303`

### Options

`--PROFILE <your profile from .aws/config>`

`--environment < Test | Prod | Dev>` - Allows auto-connecting to correct bastion box (<b>NOTE: Depends upon correct labeling of resources!</b>)

`--t, --p, --d` - Shorthand flags for environment \<Test | Prod | Dev\>

`--instanceid <bastion's-id>` - Instance ID of bastion box being used

`--rdsurl <database url>` - URL of the aws rds being connected to

`--rdsport <database port>` - Port of the aws rds being connected to

`--localport <local tunnel port>` - Local port for your mysql tool to use 

`--notunnel` - Allows user to directly ssh into box to issue commands (ie updates / installs)

`--user <username>` - Allows user to specify login name for box (User must exist on machine)

## Alternative Methods

### Aliases

If you have aliases already that you have been using to connect to the databases, those need to be updated to use the script instead.

Example:

`alias testdb="sh ~/your/path/to/connect.sh --PROFILE testprofile --environment Test --rdsurl testdburl.com --rdsport 3306 --localport 5432`

`alias proddb="sh ~/your/path/to/connect.sh --PROFILE prodprofile --environment Prod --rdsurl proddburl.com --rdsport 3306 --localport 3303`

## Connecting to the db

Now connect as you normally would via `mysql` commandline or TablePlus or other DB Management Tool

host: -h 127.0.0.1<BR>
port: -P localport setting<BR>
user: -u your personal db login<BR>
pass: -p (leave this blank if doing commandline so as not to save your password in bash_history)
