# Set up Bastion boxes for ssh/tunneling

Steps to refresh a bastion box.

## EC2 Setup

1. Navigate to EC2 ➝ Click "Launch Instances" dropdown
2. Select "Launch Instance from Template"
3. Choose the (Prod-VPC-Bastion|Test-VPC-Bastion) template, latest revision.<br>
![Template Selection](../images/bastion-template.png)

4. Check OS, if needed, update to newer via "Quick Start"
    - (if updating OS, ensure: Under "Architecture", select "64-bit (Arm)")
    - (if you need to update the OS, please consider updating the Template revision)
5. The rest should be already filled out per the defaults from the Template
6. ~~Launch Instance, note that it should have a public IP auto-assigned~~
7. <b>REQUIRED</b>: Update name - must include the word "Bastion" (ie: Test VPC Bastion | Prod VPC Bastion)
8. <b>OPTIONAL</b>: Test by opening the instance in the AWS console, click the Connect button and connect to the instance via SSM<br>
![SSM Connect](../images/ssm-connect.png)

9. Wait before trying to [connect using the script](README.md), as the `User data` portion of the Template may take a minute or two to complete

### User data script for template

```
#!/bin/bash
# Create ssm-user used by connect.sh script and ssm
adduser ssm-user
# update almost all of the things
yum update
yum upgrade -y
# Ensure latest version of ssm-agent is installed on ARM
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm
```

### Required Labels

Bastion box must have the following labels:

- Environment: Test (or Prod) (or Dev)
- Name: Bastion (Bastion must be <i>somewhere</i> in the name of the machine)
