#!/bin/bash

# -------------------------------- Single thread --------------------------------
LOCKFILE="/tmp/.provision.lock"

if [ -e "${LOCKFILE}" ]; then
echo "Already running. We cannot run this script as multithread due to tagging and bootstraping"
exit 99

else

echo $! > "${LOCKFILE}"
chmod 644 "${LOCKFILE}"


# -------------------------------- Usage--------------------------------
usage()
{
echo "Usage: $0 --nodename [hostname] --noderole [noderole] --task [task]
Example:
    $0 --nodename tike1-web1 --noderole webserver --task create
Required parameters:
--nodename               The hostnme for spinned box
--noderole               The role for spinned box [used by chef]
--subnetzone 		 The SubnetZone (public/pub or private/prv or internal/int)
--task                   The task for this script to run [e.g spin or knife]

Optional parameters:
--baseimage           Default: (ami-01001010)
--count              	Default: (1)
--instance-type		    Default: (t2.micro)	
--vpc-security-grp	  Default: (sg-deep0101) #Not in use
--env_value		        Default: (stg) 
--azzone    		      Default: (eu-west-1)   #Not in use
--help                   Print this help message and exit
--version                Print version information and exit
"
    rm -f /tmp/.provision.lock
    exit 0
}

# ----------------------------------------------------------------
function version()
{
    echo "$0 version 1.0.0"
    echo "Written by Tikejhya"
    rm -f "${LOCKFILE}"
    exit 0
}


init_variables()
{
	BASE_IMAGE="${BASE_IMAGE:-ami-01001010}"
	OUTFILE="/tmp/running-instance-output"
	AWS=$(which aws)
	SGID="${SGID:-sg-dee12121212}"
	ENVIRO="${ENVIRO:-stg}"
	INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
	COUNT="${COUNT:-1}"
	AZZONE="${AZZONE:-eu-west-1}"

}

sanityCheck()
{
	if [[ ! $ENVIRO =~ ^(dev|uat|stg|prod)$ ]]; then
        echo "ENV validation failed: $ENVIRO"
        exit 1
        else
                echo "ENV Validation: Pass [OK] $ENVIRO"
        fi

	if [[ ! $HOST_NAME =~ ^[a-zA-Z]{0,99}[0-9]{1,2}-${ENVIRO}[0-9]{1}$ ]]; then
	echo "Hostname validation failed: $HOST_NAME"
	exit 1 
	else 
		echo "Hostname Validation: Pass [OK] $HOST_NAME"
	fi
	if [[ ! $ROLE_TYPE =~ ^(web|mysql|varnish)$ ]]; then
        echo "Role Type validation failed: $ROLE_TYPE"
        exit 1
        else
                echo "Role Type Validation: Pass [OK] $ROLE_TYPE"
        fi

	if [[ ! $HOST_ZONE =~ ^(public|pub|private|prv|internal|int)$ ]]; then
        echo "Host Zone validation failed: $HOST_ZONE"
        exit 1
        else
                echo "Host Zone Validation: Pass [OK] $HOST_ZONE"
		if [[ $HOST_ZONE =~ ^(public|pub)$ ]]; then
			HOST_ZONE="pub"
		elif [[ $HOST_ZONE =~ ^(private|prv)$ ]]; then
			HOST_ZONE="prv"
		elif [[ $HOST_ZONE =~ ^(internal|int)$ ]]; then
			HOST_ZONE="int"
		fi
        fi
}

generateSubnetDescription()
{
	aws ec2 describe-subnets 
        FILTER="--filters Name=vpc-id,Values=vpc-some-vpc-id"
	QUERY="--query 'Subnets[].[Tags[?Key==`Name`].Value[],SubnetId,AvailabilityZone]'" 
        TEXTOUTPUT="--output text | sed '$!N;s/\n/ /' > ~/.describe-subnets"
	
	aws ec2 describe-subnets $FILTER $QUERY $TEXTOUTPUT
}


assignSubnetId()
{
 # Change this logic into function
 if [[ $HOST_NAME =~ ^[a-zA-Z]{0,99}(1|4|7|10|13|16|19|22)-[a-zA-Z]{0,99}[0-9]{1}$ ]]; then
    HOST_ZONE_CLASS='ZoneA'
    AZ=${AZZONE}a
 unset MAXPOOL;
 elif [[ $HOST_NAME =~ ^[a-zA-Z]{0,99}(2|5|8|11|14|17|20|23)-[a-zA-Z]{0,99}[0-9]{1}$ ]]; then
    HOST_ZONE_CLASS='ZoneB'
    AZ=${AZZONE}b
 unset MAXPOOL;
 elif [[ $HOST_NAME =~ ^[a-zA-Z]{0,99}(3|6|9|12|15|18|21)-[a-zA-Z]{0,99}[0-9]{1}$ ]]; then
    HOST_ZONE_CLASS='ZoneC'
    AZ=${AZZONE}c	
 else
    echo "assignSubnetId: i was here but why?"
    exit 1
 fi
 SUBNETID=$(cat ~/.describe-subnets | grep -i ${HOST_ZONE_CLASS} | grep -i ${ENVIRO} | grep -i ${HOST_ZONE} | awk '{print $1}' )
}

assignPemFile()
{
  if [[ $ENVIRO == prod ]]
  then
      KEYNAME="~/.ssh/prod-aws.pem"
  elif [[ $ENVIRO == stg ]]
  then
      KEYNAME="~/.ssh/stg-aws.pem"
  elif [[ $ENVIRO == uat ]]
  then
      KEYNAME="~/.ssh/uat-aws.pem"
  else
      echo "assignPemFile: I was here but why?"
      exit 1
  fi
  ACCESSKEY=$(echo ${KEYNAME} | cut -d'/' -f3 | cut -d'.' -f1)
}


provision()
{
case "$TASK" in
	spin)
	 $AWS ec2 run-instances --image-id ${BASE_IMAGE} --count ${COUNT} --instance-type ${INSTANCE_TYPE} --key-name ${ACCESSKEY} --security-group-ids ${SGID} --subnet-id ${SUBNETID} --placement AvailabilityZone=${AZ} > $OUTFILE && aws ec2 create-tags --resources `cat $OUTFILE | jq -r ".Instances[0].InstanceId"` --tags "Key=Name,Value=$HOST_NAME"
	  ;;
	 knife)                                       
	  perl /users/ashnep/data_import/wait_until.pl "timeout 2 nc -z -n -v `cat $OUTFILE | jq -r ".Instances[0].PrivateIpAddress"` 22 | grep succeeded | wc -l" "1"
	  knife bootstrap `cat $OUTFILE | jq -r ".Instances[0].PrivateIpAddress"` -N $HOST_NAME -r "role[$ROLE_TYPE]" --environment $ENVIRO -x ec2-user --sudo --use-sudo-password  -i $KEYNAME
	  ;;
	 telnet)
	  timeout 1 telnet `cat $OUTFILE | jq -r ".Instances[0].PrivateIpAddress"` 22
	  ;;
	 *)
	  echo 'usages either spin/knife or telnet'
	  ;;
esac
}
# ---------------------------------- INIT VARIABLES  ------------------------------
init_variables



if [ $# -lt 8 ] ; then
        usage
 exit
fi

# -------------------------------- PARSE PARAMETER --------------------------------

ARGS=$(getopt -u --longoptions="nodename:,subnetzone:,noderole:,vpc-security-grp:,env_value:,baseimage:,instance-type:,count:,azzone:,help,version,task:" -o "" -- ${@})

if [ ${?} -ne 0 ]
then
        exit 1
fi


set -- ${ARGS}

while [ ${1} != -- ]
do
        case ${1} in
                '--help')
                        usage
                        ;;

                '--version')
                        version
                        ;;

                '--nodename')
                        HOST_NAME=$2
                        shift
                        ;;

                '--subnetzone')
                        HOST_ZONE=$2
                        shift
                        ;;
                '--instance-type')
                        INSTANCE_TYPE=$2
                        shift
                        ;;
                '--task')
                        TASK=$2
                        shift
                        ;;
                '--vpc-security-grp')
                        #SGID=$2
			echo "Ignoring --vpc-security-grp: Security group ID should always be DevOps"
                        shift
                        ;;
                '--env_value')
                        ENVIRO=$2
                        shift
                        ;;
                '--noderole')
                        ROLE_TYPE=$2
                        shift
                        ;;
                '--baseimage')
                        BASE_IMAGE=$2
                        shift
                        ;;
		'--count')
                        COUNT=$2
                        shift
                        ;;
                '--azzone')
                        #AZZONE=$2
			echo "Ignoring --azzone: We dont control AZ Zone its decided based on subnetzone, hostname and environment"
                        shift
                        ;;
        esac

        shift
done

# -------------------------------- SANITY CHECK --------------------------------
sanityCheck
# -------------------------------- ASSIGN PEM FILE --------------------------------
assignPemFile
# -------------------------------- ASSIGN SUBNET ID --------------------------------
assignSubnetId
# -------------------------------- PROVISION TASK --------------------------------
provision


rm -f "${LOCKFILE}"

fi
