#!/bin/bash

ACTION=$1

function usage() {
	echo "Usage: $0 <prep|run|cleanup> [remoteserver] [repts]" >&2
	exit 1
}


TARGET_IP=${2-localhost}	# dns/ip for machine to test
TEST_USER=${3}
CMD_PATH=${4}

REPTS=${5-10}
REQ=${6-''}

NR_REQUESTS=1000
TABLE_SIZE=1000000
RESULTS=mysql.txt

mysql_root_pw="kvm"

function prepare() {
    mysql -u root -p${mysql_root_pw} < create_db.sql
    sysbench /usr/share/sysbench/oltp_read_write.lua \
        --db-driver=mysql \
        --mysql-host=$TARGET_IP \
        --mysql-user=sysbench \
        --mysql-password=${mysql_root_pw} \
        --mysql-db=sysbench \
        --table-size=$TABLE_SIZE \
        prepare
}

function cleanup() {
    sysbench /usr/share/sysbench/oltp_read_write.lua \
        --db-driver=mysql \
        --mysql-host=$TARGET_IP \
        --mysql-user=sysbench \
        --mysql-password=${mysql_root_pw} \
        --mysql-db=sysbench \
        cleanup
    mysql -u root -p${mysql_root_pw} < drop_db.sql
}

function run() {
    sysbench /usr/share/sysbench/oltp_read_write.lua $REQ \
        --db-driver=mysql \
        --mysql-host=$TARGET_IP \
        --mysql-user=sysbench \
        --mysql-password=${mysql_root_pw} \
        --mysql-db=sysbench \
        --table-size=$TABLE_SIZE \
        --num-threads=$num_threads \
        run | tee \
        >(grep 'total time:' | awk '{ print $3 }' | sed 's/s//' >> $RESULTS)
}


if [[ "$TARGET_IP" != "localhost" && ("$ACTION" == "prep" || "$ACTION" == "cleanup") ]]; then
	echo "prep and cleanup actions can only be run on the db server" >&2
	exit 1
fi

if [[ "$ACTION" == "prep" ]]; then
	service mysql start
	cleanup
	prepare
elif [[ "$ACTION" == "run" ]]; then
	source exits.sh mysql
	start_measurement

	for num_threads in 100; do
		echo -e "$num_threads threads:\n---" >> $RESULTS
		for i in `seq 1 $REPTS`; do
			ssh $TEST_USER@$TARGET_IP "pushd ${CMD_PATH};sudo ./mysql.sh prep"
			run
			ssh $TEST_USER@$TARGET_IP "pushd ${CMD_PATH};sudo ./mysql.sh cleanup"
		done;
		echo "" >> $RESULTS
	done;

	end_measurement
	save_stat

elif [[ "$ACTION" == "cleanup" ]]; then
	#We will do a lazy-cleanup.
	service mysql stop
else
	usage
fi
