#!/bin/bash

usage() {
    echo "Usage: $0 [OPTIONS] <clientname> <input_file>"
    echo
    echo "Options:"
    echo "  --auth-file AUTH_FILE     Specify the authentication file to use"
    echo "  --help                    Display this help message and exit"
    echo
    echo "Authentication file format:"
    echo "  username = <USER>"
    echo "  password = <PASSWORD>"
    echo "  domain   = <DOMAIN>"
    exit 1
}

test_server() {
    local p=$1
    if [ -z "$AUTH_FILE" ]; then
        echo -e "$INFO_TERM Now testing server at $p without credentials"
        echo -e "$INFO_LOG Now testing server at $p without credentials" >&4
        COMMAND="smbclient -N -L $p 2>/dev/null"
    else
        echo -e "$INFO_TERM Now testing server at $p with credentials from $AUTH_FILE"
        echo -e "$INFO_LOG Now testing server at $p with credentials from $AUTH_FILE" >&4
        COMMAND="smbclient -L $p -A $AUTH_FILE 2>/dev/null"
    fi
    RESULT=$(eval $COMMAND)

    ERROR_FOUND=0
    for STATUS in "${!STATUS_MSGS[@]}"; do
        if [[ $RESULT == *"$STATUS"* ]]; then
            echo -e "$FAIL_TERM ${STATUS_MSGS[$STATUS]} at $p. Continuing."
            echo -e "$FAIL_LOG ${STATUS_MSGS[$STATUS]} at $p. Continuing." >&4
            ERROR_FOUND=1
            break
        fi
    done

    if [[ $ERROR_FOUND -eq 0 ]]; then
        echo -e "$SUCCESS_TERM Access to server at $p granted!"
        echo -e "$SUCCESS_LOG Access to server at $p granted!" >&4
        SHARES=$(echo "$RESULT" | awk '/Sharename/,/Server               Comment/' | egrep -v "Sharename       |---|Server               |^$" | grep -v "Anonymous login" | grep -v "NT_STATUS_RESOURCE_NAME_NOT_FOUND" | grep -v "NetBIOS over TCP" | awk '{print $1}')
        if [ -z "$SHARES" ]; then
            echo -e "$INFO_TERM No shares available on $p."
            echo -e "$INFO_LOG No shares available on $p." >&4
            return
        fi
        while read -r line; do
            if [ -z "$AUTH_FILE" ]; then
                echo -e "$INFO_TERM Testing \\\\\\\\$p\\\\$line without credentials"
                echo -e "$INFO_LOG Testing \\\\\\\\$p\\\\$line without credentials" >&4
                COMMAND="smbclient -N \\\\\\\\$p\\\\$line -c ls 2>/dev/null"
            else
                echo -e "$INFO_TERM Testing \\\\\\\\$p\\\\$line with credentials from $AUTH_FILE"
                echo -e "$INFO_LOG Testing \\\\\\\\$p\\\\$line with credentials from $AUTH_FILE" >&4
                COMMAND="smbclient -A $AUTH_FILE \\\\\\\\$p\\\\$line -c ls 2>/dev/null"
            fi
            SHARE_RESULT=$(eval $COMMAND)
            echo "$COMMAND" >&4
            echo "$SHARE_RESULT" >&4

            ERROR_FOUND=0
            for STATUS in "${!STATUS_MSGS[@]}"; do
                if [[ $SHARE_RESULT == *"$STATUS"* ]]; then
                    echo -e "$FAIL_TERM ${STATUS_MSGS[$STATUS]} for \\\\\\\\$p\\\\$line. Continuing."
                    echo -e "$FAIL_LOG ${STATUS_MSGS[$STATUS]} for \\\\\\\\$p\\\\$line. Continuing." >&4
                    ERROR_FOUND=1
                    break
                fi
            done

            if [[ $ERROR_FOUND -eq 0 && -n $line ]]; then
                echo -e "$SUCCESS_TERM Access granted to \\\\\\\\$p\\\\$line!"
                echo -e "$SUCCESS_LOG Access granted to \\\\\\\\$p\\\\$line!" >&4
                echo "$p $line \\\\$p\\$line" >&3
            fi
        done <<< "$SHARES"
    fi
}

AUTH_FILE=

while [ "$1" != "" ]; do
    case $1 in
        --auth-file )       shift
                            AUTH_FILE=$1
                            ;;
        --help )            usage
                            ;;
        * )                 break
                            ;;
    esac
    shift
done

if [ -z "$2" ]; then
    usage
fi

start=$(date +%s)
clientname=$1
FILE=$2
OUT_FILE=$clientname-smb_check_no_auth-parallel.txt

exec 3>> $OUT_FILE
exec 4>> $clientname-smbclient_responses-parallel.txt

declare -A STATUS_MSGS
STATUS_MSGS=(
    ["NT_STATUS_ACCESS_DENIED"]="Access denied"
    ["NT_STATUS_LOGON_FAILURE"]="Log on failed"
    ["NT_STATUS_IO_TIMEOUT"]="Connection timed out"
    ["NT_STATUS_CONNECTION_REFUSED"]="Connection refused"
    ["NT_STATUS_ACCOUNT_DISABLED"]="Account was disabled"
    ["NT_STATUS_UNSUCCESSFUL"]="Connection was unsuccessful"
    ["NT_STATUS_CONNECTION_DISCONNECTED"]="Connection was disconnected"
    ["ERRDOS"]="Protocol negotiation failed"
)

INFO_TERM="[ \033[1;33m=\033[0m ] "
SUCCESS_TERM="[ \033[1;32m+\033[0m ] "
FAIL_TERM="[ \033[1;31m!\033[0m ] "

INFO_LOG="[ = ] "
SUCCESS_LOG="[ + ] "
FAIL_LOG="[ ! ] "

while read p; do
    test_server $p &
done < $FILE

wait

end=$(date +%s)
runtime=$((end-start))
echo "Program has finished execution in $runtime seconds."

# Display a summary of open shares
if [[ -s $OUT_FILE ]]; then
    echo -e "$SUCCESS_TERM Open shares found:"
    awk 'NF>2{print "Server: " $1 ", Share: " $2 ", Path: " $3}' $OUT_FILE
else
    echo -e "$INFO_TERM No open shares found."
fi

exec 3>&-
exec 4>&-
