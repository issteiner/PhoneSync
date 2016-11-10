#!/bin/bash

# Script to help copying directories from/to phone

ACTUAL_DATE=$(date +%Y%m%d)
ACTUAL_TIME=$(date +%H%M%S)
START_TIME_SEC=$(date +'%s')

SCRIPT_PATH=$(readlink -f $0)             # In case we execute it as a symlink
SCRIPT_NAME=$(basename ${SCRIPT_PATH%%.sh})

LOGDIR="$(dirname $SCRIPT_PATH)/Logs"
OUTLOG="${LOGDIR}/${SCRIPT_NAME}_${ACTUAL_DATE}_${ACTUAL_TIME}.log"
ERRORLOG="${OUTLOG%%log}err"

PC_HOME_DIR="/home/ethsri"
PC_DOC_DIR="${PC_HOME_DIR}/Documents"
PC_PHONE_DIR="${PC_HOME_DIR}/PhoneTransfer"
PC_PHONE_ACTUAL_DIR="${PC_PHONE_DIR}/FromPhone_${ACTUAL_DATE}"

GVS_PATH="/run/user/$UID/gvfs"
PHONE_MTP_DIR=$(ls "${GVS_PATH}")
PHONE_BASE_DIR="${GVS_PATH}/${PHONE_MTP_DIR}/Phone"
PHONE_DOC_DIR="${PHONE_BASE_DIR}/Documents"
PHONE_TRANSFER_DIR="${PHONE_DOC_DIR}/0_Transfer"

DIRS_TO_PHONE="Private/0_Privat/Projektek/0_Folyo/HazFelujitas_2015- Private/6_AlkalmazottTudomany Private/0_Privat/Aktualis/CsinalniValo Private/0_Privat/Ingatlanok Common/Scripts"
# DIRS_TO_PHONE="Temp/TestFiles"
DIRS_FROM_PHONE="DCIM Download Documents/Actual Documents/1_BackTransfer"

gvfs_mtp_mount_dev=$(gvfs-mount -l | awk '/^Mount.*mtp\ -/ {print $4}')
pid_gvfsd_mtp=$(pidof gvfsd-mtp)

nr_of_transactions=0

function increase_nr_of_transactions {
    let nr_of_transactions=nr_of_transactions+1
    cents=$(echo "$nr_of_transactions % 20" | bc)
    if [ $cents -eq 0 ]
    then
        resident_memory=$(/usr/bin/top -b -p $pid_gvfsd_mtp -n 1 | awk "/$USER/"' {print $6}')
        print_and_log "${nr_of_transactions}    ${resident_memory}"
        if [ $resident_memory -gt 10000 ]
        then
            echo -e "WARNING! Resident memory is over 10000.\nRemounting device..."
            gvfs-mount -u ${gvfs_mtp_mount_dev}
            sleep 5
            gvfs-mount ${gvfs_mtp_mount_dev}
            pid_gvfsd_mtp=$(pidof gvfsd-mtp)
            print_and_log "PID OF GVFSD-MTP: $pid_gvfsd_mtp"
        fi
    fi
}

function print_and_log {
    echo -n "$(date +%Y.%m.%d-%H:%M:%S) - " >>${OUTLOG}
    echo -e "$1" | tee -a ${OUTLOG}
}

function only_log {
    echo -n "$(date +%Y.%m.%d-%H:%M:%S) - " >>${OUTLOG}
    echo -e "$1" >>${OUTLOG}
}

function exit_if_error {
    if [ $1 -ne 0 ]
    then
        resident_memory=$(/usr/bin/top -b -p $pid_gvfsd_mtp -n 1 | awk "/$USER/"' {print $6}')
        print_and_log "${nr_of_transactions}    ${resident_memory}"
        print_and_log "ERROR occurred. Exiting..."
        exit 1
    fi
}

function copy_fromto_phone {
    local source_base_dir=$1
    local source_dir=$2
    local target_dir=$3

    OIFS="$IFS"
    IFS=$'\n'
    for dir in $(find ${source_base_dir}/${source_dir} -type d)
    do
        dir_tail=${dir##${source_base_dir}/}
        only_log "gvfs-mkdir -p ${target_dir}/${dir_tail}"
        gvfs-mkdir -p ${target_dir}/${dir_tail} 2>>${ERRORLOG}
        exit_if_error $?
#        increase_nr_of_transactions
    done

    for file_to_copy in $(find ${source_base_dir}/${source_dir} -type f)
    do
        file_to_copy_dir=$(dirname ${file_to_copy})
        file_to_copy_dir_tail=${file_to_copy_dir##${source_base_dir}/}
        only_log "gvfs-copy ${file_to_copy} ${target_dir}/${file_to_copy_dir_tail}/"
        gvfs-copy ${file_to_copy} ${target_dir}/${file_to_copy_dir_tail}/ 2>>${ERRORLOG}
        exit_if_error $?
        increase_nr_of_transactions
    done
    IFS="$OIFS"
}

########
# MAIN #
########

if [ ! -d $LOGDIR ]
then
    mkdir -p "${LOGDIR}"
fi

if ! ls ${PHONE_BASE_DIR} >/dev/null 2>&1
then
    echo "ERROR! Phone is not mounted. Please mount it and try again. Exiting..."
    exit 1
fi

if [ ! -d "${PC_PHONE_DIR}" ]
then
    print_and_log "Creating ${PC_PHONE_DIR}..."
    only_log "mkdir -p ${PC_PHONE_DIR}"
    mkdir -p "${PC_PHONE_DIR}" 2>>${ERRORLOG}
    exit_if_error $?
fi

print_and_log "PID OF GVFSD-MTP: $pid_gvfsd_mtp"
print_and_log "Nr. of transactions      Resident memory"
    
print_and_log "Copying files from phone to the own HDD..."

for dir in ${DIRS_FROM_PHONE}
do
    only_log "copy_fromto_phone ${PHONE_BASE_DIR} ${dir} ${PC_PHONE_ACTUAL_DIR}"
    copy_fromto_phone ${PHONE_BASE_DIR} ${dir} ${PC_PHONE_ACTUAL_DIR}
done

print_and_log "Copying files from the own HDD to the phone..."
for dir in ${DIRS_TO_PHONE}
do
    only_log "copy_fromto_phone ${PC_DOC_DIR} ${dir} ${PHONE_TRANSFER_DIR}"
    copy_fromto_phone ${PC_DOC_DIR} ${dir} ${PHONE_TRANSFER_DIR}
done

print_and_log "Searching for duplicate files and removing found duplicate files in the copied files/direcories on the HDD..."
only_log "cd /home/ethsri/Documents/Common/Scripts/DupliSeek"
only_log "./dupliSeek.py -v -p -r ${PC_DOC_DIR} ${PC_PHONE_ACTUAL_DIR}"

cd /home/ethsri/Documents/Common/Scripts/DupliSeek
./dupliSeek.py -v -p -r ${PC_DOC_DIR} ${PC_PHONE_ACTUAL_DIR} >>${OUTLOG} 2>>${ERRORLOG}

print_and_log "Deleting zero size files and empty directories in the copied files/direcories on the HDD..."
only_log "find ${PC_PHONE_ACTUAL_DIR} -type f -size 0 -delete"
only_log "find ${PC_PHONE_ACTUAL_DIR} -type d -empty -delete"

find ${PC_PHONE_ACTUAL_DIR} -type f -size 0 -delete 2>>${ERRORLOG}
find ${PC_PHONE_ACTUAL_DIR} -type d -empty -delete 2>>${ERRORLOG}

