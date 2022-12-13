#!/bin/bash

containerImage="stack-over-search-img"
containerName="stack-over-search"

restartContainer=0
runAnsible=0
containerIsAlreadyRunning=0
startContainerOnly=0

generateNewSshKey=0

runAnsibleSilent=0
ansibleVerboseOption=""

currDir="`pwd`"
scriptLocationDir="`echo -n "$currDir/$0"`"
scriptLocationDir="`dirname $scriptLocationDir`"

sshPrivateKeyFile="$scriptLocationDir/sshkey-stackoversearch"
sshPrivateKeyExists=0

requiedPackages=("docker")
requiedPackages+=("ansible")

ansiblePlaybookFile="run_roles.yml"
ansibleCollectionsListFile="ansible_collections.txt"

ShowMessageErrorExit(){
    echo "Exiting with error. Try -h for help"
    exit 1
}

while getopts ":hk:rasvcgn:i:" opt;
do
	case "$opt" in
		h)
			echo -e "Options:"
            echo -e "-h\tshow help"
            echo -e "-k\tredefine ssh private key file. Usage: '-k sshKeyFile'"
            echo -e "-r\trestart container: kill it and start again (only if container is currently running)"
            echo -e "-a\tuse ansible on running container"
            echo -e "-s\trun ansible silently: no output, terminal session can be closed after ansible start, ansible will continue to run"
            echo -e "-v\trun ansible in verbose mode. can be used multiple times, for example: '-vvvv'"
            echo -e "-c\tstart container and exit script"
            echo -e "-g\tgenerate new ssh key"
            echo -e "-i\tredefine image name. Usage: '-i imageName'"
            echo -e "-n\tredefine container name. Usage: '-n containerName'"
            echo -e "\nExamples:"
            echo -e "- First run, silent"
            echo -e "\t$0 -gs"
            echo
            echo -e "- Redefine ssh key, generate it, show more ansible logs"
            echo -e "\t$0 -k ~/.ssh/id_rsa -vv -g"
			exit 0
		;;
        k)
            sshPrivateKeyFile="$OPTARG"
        ;;
        r)
            restartContainer=1
        ;;
        a)
            runAnsible=1
        ;;
        s)
            runAnsibleSilent=1
        ;;
        v)
            ansibleVerboseOption+="v"
        ;;
        c)
            startContainerOnly=1
        ;;
        g)
            generateNewSshKey=1
        ;;
        i)
            containerImage="$OPTARG"
        ;;
        n)
            containerName="$OPTARG"
        ;;
		:)
			echo "Argument '$OPTARG' requies parameter."; ShowMessageErrorExit
		;;
		\?)
			echo "Unexpected argument: '$OPTARG'"; ShowMessageErrorExit
		;;
	esac
done


if [ "$runAnsibleSilent" = "1" -a "$ansibleVerboseOption" != "" ]; then
    echo "Options '-s' and '-v' cannot be used at same time, choose one."
    ShowMessageErrorExit
fi


if [ -f "$sshPrivateKeyFile" -o -f "$sshPrivateKeyFile".pub ]; then sshPrivateKeyExists=1; fi

if [ "$generateNewSshKey" = "1" -a "$sshPrivateKeyExists" = "1" ]; then
    echo "You mentioned that you want to generate new ssh key file, but it already exists."
    echo "Do not use '-g' option or delete existing ssh key before continue."
    ShowMessageErrorExit
fi

if [ "$sshPrivateKeyExists" = "0" -a "$generateNewSshKey" = "0" ]; then
    echo "Ssh private key not found: '$sshPrivateKeyFile'"
    ShowMessageErrorExit
fi

if [ "$generateNewSshKey" = "1" ]; then
    echo "Generating ssh private key: '$sshPrivateKeyFile'"
    ssh-keygen -b 2048 -t rsa -f "$sshPrivateKeyFile" -q -N ""
fi


echo "Checking that requied packages are installed on local host"
for pack in ${requiedPackages[@]}; do
    packageVersion=`$pack --version 2>/dev/null`
    if [ -z "$packageVersion" ]; then
        echo "'$pack' is not installed, exiting"
        exit 1
    fi
done

echo "All packages are installed, continue"


runningContainerNames="`docker ps --format '{{.Names}}'`"
if [[ "$runningContainerNames" =~ "$containerName" ]]; then
    containerIsAlreadyRunning=1
else
    containerIsAlreadyRunning=0
fi

if [ "$containerIsAlreadyRunning" = "1" ]; then
    if [ "$restartContainer" = "1" ]; then
        echo "Killing running container"
        docker kill "$containerName"
    elif [ "$runAnsible" = "0" ]; then
        echo "Container is already running. Maybe you want to use '-a' or '-r' option?"
        ShowMessageErrorExit
    fi
fi

imageIsCompiled=`docker images "$containerImage" | grep -v REPOSITORY | wc -l`
if [ "$imageIsCompiled" = "0" ]; then
    echo "Building image: '$containerImage'"
    docker build -t "$containerImage" "$scriptLocationDir"
fi

containerExists="`docker ps --all | grep "$containerName" | wc -l`"
if [ "$containerIsAlreadyRunning" = "0" ]; then
    if [ "$containerExists" = "0" ]; then
        echo "Starting new container"
        docker run -dit -p 2222:22 -p 8080:80 --name "$containerName" "$containerImage"
    else
        echo "Starting existing container"
        docker start "$containerName"
    fi
fi

if [ "$sshPrivateKeyExists" = "0" -o "$containerExists" = "0" -o "$imageIsCompiled" = "0" ]; then
    echo "Copying public ssh key to container"
    docker exec "$containerName" /bin/mkdir -p /root/.ssh
    if ! [ -f "$sshPrivateKeyFile".pub ]; then
        echo "Public ssh key file not found: '$sshPrivateKeyFile'"
        ShowMessageErrorExit
    fi
    docker cp "$sshPrivateKeyFile.pub" "$containerName":/root/.ssh/authorized_keys
    docker exec "$containerName" /bin/chown root:root /root/.ssh/authorized_keys
fi

if [ "$startContainerOnly" = "1" ]; then
    "You chose to start container only, exiting"
    exit 0
fi


cd "$scriptLocationDir/ansible"

echo "Installing ansible collections from list file: $ansibleCollectionsListFile"
while IFS= read -r collection || [[ -n "$collection" ]]; do
    firstField="`echo $collection | awk '{print $1}'`"
    if [[ "${firstField}" = \#* ]]; then continue; fi
    echo "Installing collection: $collection"
    ansible-galaxy collection install $collection
done < $ansibleCollectionsListFile

if ! [ -f "$sshPrivateKeyFile" ]; then
    echo "Private ssh key file not found: '$sshPrivateKeyFile'"
    ShowMessageErrorExit
fi

echo "Configuring server with ansible"
if [ "$runAnsibleSilent" = "1" ]; then
    echo "Silent ansible run"
    nohup ansible-playbook "$ansiblePlaybookFile" -e "ansible_private_key_file=$sshPrivateKeyFile" >/dev/null &
elif [ "$ansibleVerboseOption" != "" ]; then
    echo "Verbose ansible run"
    ansible-playbook "$ansiblePlaybookFile" -e "ansible_private_key_file=$sshPrivateKeyFile" -"$ansibleVerboseOption"
else
    ansible-playbook "$ansiblePlaybookFile" -e "ansible_private_key_file=$sshPrivateKeyFile"
fi

if [ "$runAnsibleSilent" = "0" -a "$?" = "0" ]; then echo "Server configured succesfully"; fi