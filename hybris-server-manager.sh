#!/usr/bin/env bash

function isRunning() {

    pgrep -f -- "-DHYBRIS_BIN_DIR=$HYBRIS/bin" &>/dev/null

    return $?

}

function stopHybris() {

    # Check, if server is running

    isRunning

    if [ $? -ne 0 ]
    then

        # Server is already stopped.

        if [ ${DUPLICATEFAILURE} -eq 0 ]
        then

            echo "##teamcity[message text='Hybris does not seem to be running. Canceling.' status='ERROR']"
            exit 1

        fi

    else

        # Server is running. Stop it.

        cd "$HYBRIS/bin/platform"

        bash hybrisserver.sh stop &>/dev/null

        WAITING=0

        isRunning

        while [ $? -eq 0 ]
        do

            # Wait for server to stop

            sleep 1
            WAITING=$((WAITING+1))

            if [ ${WAITING} -gt ${TIMEOUT} ]
            then

                echo "##teamcity[message text='Waiting for Hybris to stop took longer then $TIMEOUT seconds. Canceling.' status='ERROR']"
                exit 2

            fi

            isRunning

        done

    fi

}

function startHybris() {

    # Check, if server is running

    isRunning

    if [ $? -eq 0 ]
    then

        # Server is already running

        if [ ${DUPLICATEFAILURE} -eq 0 ]
        then

            echo "##teamcity[message text='Hybris seems to be running already. Canceling.' status='ERROR']"
            exit 1

        fi

    else

        # Server is not running. Start it

        cd "$HYBRIS/bin/platform"

        if [ ${DEBUGMODE} -eq 0 ]
        then
            bash hybrisserver.sh debug &>/dev/null &
        else
            bash hybrisserver.sh start &>/dev/null
        fi

        TOMCAT_HOME=${HYBRIS}/bin/platform/tomcat-6/conf/Catalina

        if [ ! -d $TOMCAT_HOME ]
        then

            # Hybris > 5.3

            TOMCAT_HOME=${HYBRIS}/bin/platform/tomcat/conf/Catalina

        fi

        if [ ! -d $TOMCAT_HOME ]
        then

            echo "##teamcity[message text='Can not find Tomcat context configuration directory. Disabling JMX-based check.' status='WARNING']"

            JMXURL=""

        fi

        # Wait until server is running.

        if [ "X${JMXURL}X" == "XX" ]
        then

            # No JMX Url specified. Just wait, until we see the process in the process list

            WAITING=0

            while true
            do

                isRunning

                if [ $? -eq 0 ]
                then
                    # Server has started

                    exit 0
                fi

                # Server has not started. Wait.

                sleep 1
                WAITING=$((WAITING+1))

                if [ ${WAITING} -gt ${TIMEOUT} ]
                then

                    echo "##teamcity[message text='Waiting for Hybris to start took longer then $TIMEOUT seconds. Canceling.' status='ERROR']"
                    exit 2

                fi

            done

        else

            WAITING=0

            # Gather the needed resources from tomcat's catalina directory

            RESOURCES=`cd ${TOMCAT_HOME} && find * -type f | sed -re "s/ROOT//gi" | tr / : | tr \# \/ | sed -re "s/\.xml//gi" | paste -s -d "," | sed -re "s/,/ -r /gi"`

            while true; do

                java -jar ${CHECKTOMCAT} -j "service:jmx:rmi:///jndi/rmi://${JMXURL}/jmxrmi" -t ${TIMEOUT} -r ${RESOURCES}

                CHECK_TOMCAT_RC=$?

                if [ ${CHECK_TOMCAT_RC} -eq 2 ]
                then

                    echo "##teamcity[message text='Waiting for Hybris to start took longer then $TIMEOUT seconds. Canceling.' status='ERROR']"
                    exit 2

                elif [ ${CHECK_TOMCAT_RC} -eq 3 ]
                then

                    # JMX is currently not responding. Wait for it.

                    sleep 1
                    WAITING=$((WAITING+1))

                    if [ ${WAITING} -gt ${TIMEOUT} ]
                    then

                        echo "##teamcity[message text='Waiting for Hybris to start took longer then $TIMEOUT seconds. Canceling.' status='ERROR']"
                        exit 2

                    fi

                elif [ ${CHECK_TOMCAT_RC} -ne 0 ]
                then

                    echo "##teamcity[message text='Error running check-tomcat.' status='ERROR']"
                    exit 3

                else
                    exit 0
                fi

            done

        fi

    fi

}

function usage() {

    if [ "XX$1XX" != "XXXX" ]
    then

      echo $1
      echo ""

    fi

    echo "Hybris Server Management script"
    echo "Starts, Stops or Restarts a hybris server and waits until the"
    echo "server is started, if the jvm is accessible via jmx."

    echo "Usage:"
    echo "  ./hybris-server-manager.sh [<options>] HYBRIS-PATH COMMAND"

    echo ""
    echo "Options:"
    echo "  -j <url>  JMX service URL. Is required, if you want to wait, until"
    echo "            the server is completely started"
    echo "  -c <path> Path to the check_tomcat jar file to check, wether the"
    echo "            server is started"
    echo "  -t <sec>  Timeout in seconds for start/stop commands (default: 60s)"
    echo "  -x        If e.g. COMMAND is start and the server is already"
    echo "            started, exit with an error"
    echo "  -d        Start the server in debug mode"
    echo "  -h        Print this help"

    echo ""
    echo "Available Commands:"
    echo ""
    echo "start - start the server"
    echo "stop - stop the server"
    echo "restart - restart the server"
    echo "status - check current state of server (started, stopped)"
    echo ""

    if [ "XX$1XX" != "XXXX" ]
    then
      exit 1
    fi

    exit 0

}

# Parse command line parameters

JMXURL=""
DEBUGMODE=1
DUPLICATEFAILURE=1
CHECKTOMCAT=""
TIMEOUT=60

while getopts "j:c:t:xdh" opt
do
    case ${opt} in
        j) JMXURL=$OPTARG;
           ;;
        c) CHECKTOMCAT=$OPTARG;
           ;;
        t) TIMEOUT=$OPTARG;
           ;;
        d) DEBUGMODE=0;
           ;;
        x) DUPLICATEFAILURE=0;
           ;;
        h) usage
             ;;
        \?) usage "Invalid option $opt"
    esac
done

shift $((OPTIND-1))

if [ "XX${JMXURL}XX" != "XXXX" -a "XX${CHECKTOMCAT}XX" == "XXXX" ]
then
    usage "You have to specify both JMX URL and path to the check_tomcat jar file!"
fi

if [ "XX${JMXURL}XX" == "XXXX" -a "XX${CHECKTOMCAT}XX" != "XXXX" ]
then
    usage "You have to specify both JMX URL and path to the check_tomcat jar file!"
fi

HYBRIS=$1
COMMAND=$2

if [ "XX${HYBRIS}XX" == "XXXX" ]
then
    usage "Hybris path not specified."
fi

if [ "XX${COMMAND}XX" == "XXXX" ]
then
    usage "Command not specified."
fi

if [ "${CHECKTOMCAT:0:1}" != "/" ]
then
    # Checktomcat was given as a non-absolute path. Add the script path
    CHECKTOMCAT="`pwd`/$CHECKTOMCAT"
fi

if [ "$COMMAND" == "stop" ]
then
    stopHybris
elif [ "$COMMAND" == "start" ]
then
    startHybris
elif [ "$COMMAND" == "restart" ]
then
    stopHybris && startHybris
elif [ "$COMMAND" == "status" ]
then
    isRunning

    if [ $? -eq 0 ]
    then
        echo "started"
    else
        echo "stopped"
    fi

    exit 0
else
    echo "##teamcity[message text='Invalid command $COMMAND. Canceling.' status='ERROR']"
fi
