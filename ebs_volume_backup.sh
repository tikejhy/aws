#!/bin/bash

### Volumelist format:
### Volumeid:host_identifier:retaintion_period
volume_list='

vol-01010101:web1.ashishnepal.com:3
vol-02020202:web2.ashishnepal.com:3
vol-03030303:web3.ashishnepal.com:3

'

snapshot_volumes() {
	for volume in $volume_list; do

		volume_id=$(echo "$volume" | cut -d':' -f1)
		host_name=$(echo "$volume" | cut -d':' -f2)
		retention_days=$(echo "$volume" | cut -d':' -f3)
		retention_date_in_seconds=$(date +%s --date "$retention_days days ago")
		snapshot_description=$(date +%Y-%m-%d)

		snapshot_id=$(aws ec2 create-snapshot --output=text --description $host_name-$snapshot_description --volume-id $volume_id --query SnapshotId)
		aws ec2 create-tags --resource $snapshot_id --tags Key=CreatedBy,Value=AutomatedBackup

	done
}


cleanup_snapshots() {
         for volume in $volume_list; do

                volume_id=$(echo "$volume" | cut -d':' -f1)
                host_name=$(echo "$volume" | cut -d':' -f2)
		retention_days=$(echo "$volume" | cut -d':' -f3)
                retention_date_in_seconds=$(date +%s --date "$retention_days days ago")

                snapshot_list=$(aws ec2 describe-snapshots --output=text --filters "Name=volume-id,Values=$volume_id" "Name=tag:CreatedBy,Values=AutomatedBackup" --query Snapshots[].SnapshotId)
                for snapshot in $snapshot_list; do

                        snapshot_date=$(aws ec2 describe-snapshots --output=text --snapshot-ids $snapshot --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
                        snapshot_date_in_seconds=$(date "--date=$snapshot_date" +%s)
                        snapshot_description=$(aws ec2 describe-snapshots --snapshot-id $snapshot --query Snapshots[].Description)

                        if (( $snapshot_date_in_seconds <= $retention_date_in_seconds )); then
                                aws ec2 delete-snapshot --snapshot-id $snapshot
				echo "aws ec2 delete-snapshot --snapshot-id $snapshot"
                        else
                                echo "Nothing to delete $snapshot"
                        fi
                done
        done
}

cleanup_snapshots
snapshot_volumes
