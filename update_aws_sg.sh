#!/usr/bin/env bash

# Usage: ./update_aws_sg.sh <security group id> <protocol> <port> <rule description>

# Standardised error process, prints errors to STDERR
function exit_with_error() {
    echo -e "[ERROR] ${1}" >&2;
    exit 1;
}

declare access_granted="false";
declare allowed_cidrs;

declare group_id="${1}";
declare protocol="${2}";
declare port="${3}";
declare rule_description="${4}";

declare my_cidr;
declare my_ip;


# Get my public IP
my_ip="$(curl -s curlmyip.org || echo "Failed")";

[ "${my_ip}" == "Failed" ] \
 && exit_with_error "Failed to retrieve my IP from v4.ifconfig.co";

allowed_cidrs="$(aws ec2 describe-security-groups \
                   --output text \
                   --query '
                     SecurityGroups[?
                       GroupId==`'${group_id}'`
                     ].
                     [
                       IpPermissions[?
                         ToPort==`'${port}'` && FromPort==`'${port}'` && IpProtocol==`tcp`
                       ].
                       IpRanges[?Description!=`null` && Description==`'${rule_description}'`].
                       CidrIp
                     ]' \
                   || echo "Failed")";

[ "${allowed_cidrs}" == "Failed" ] \
 && exit_with_error "Failed to retrieve SSH ingress rules for ${group_id}";

# With my_ip and allowed_cidrs known, clean-house by revoking all access that isn't from here.
my_cidr="${my_ip}/32";

for cidr in ${allowed_cidrs}; do
# Don't quote this string, bash needs to tokenise it and it's not an array.
    if [ "${cidr}" == "${my_cidr}" ]; then
        access_granted="true";
    else
        echo -en "Revoking SSH access to ${group_id} from ${cidr}... ";
        aws ec2 revoke-security-group-ingress \
 --group-id ${group_id} \
 --protocol ${protocol} \
 --port ${port} \
 --cidr ${cidr} \
 && echo -e "Done." \
 || echo -e "Failed.";
    fi;
done;

if [ "${access_granted}" == "true" ]; then
    echo -e "Access already authorised from ${my_cidr}";
else
    echo -en "Authorising SSH access to ${group_id} from ${my_cidr}... ";
    aws ec2 authorize-security-group-ingress \
 --group-id ${group_id} \
 --ip-permissions IpProtocol="${protocol}",FromPort="${port}",ToPort="${port}",\
IpRanges='[{CidrIp='${my_cidr}',Description="'${rule_description}'"}]' \
 && echo -e "Done." \
 || exit_with_error "Failed.";
fi;

exit 0;