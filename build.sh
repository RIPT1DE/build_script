#!/bin/bash
# Copyright (C) 2017 Vincent Zvikaramba
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

############
#          #
#  COLORS  #
#          #
############
START_TIME=$( date +%s )

BLUE='\033[1;35m'
BOLD="\033[1m"
GREEN="\033[01;32m"
NC='\033[0m' # No Color
RED="\033[01;31m"
RESTORE=$NC

# file transfer/build retry count
BUILD_RETRY_COUNT=0
UPLOAD_RETRY_COUNT=3

# create a temprary working dir
BUILD_TEMP=$(mktemp -d)

ARTIFACT_OUT_DIR=${BUILD_TEMP}/builds

SAVED_BUILD_JOBS_DIR=/tmp/android_build_jobs

#changelog
CHANGELOG_DAYS=5

CURL="curl --silent -connect-timeout=10"

# file extraction function names
COPY_FUNCTIONS=();
POST_COPY_FUNCTIONS=();

REPO_REF_MAP=();

SCRIPT_REPO_URL="https://git.msm8916.com/Galaxy-MSM8916/build_script.git/plain"

SILENT=0

LOCAL_REPO_PICKS=
LINEAGE_REPO_PICKS=

LOCAL_REPO_TOPICS=
LINEAGE_REPO_TOPICS=

function logr {
    echo -e ${RED} "$@" ${NC}
}

function logb {
    echo -e ${BLUE} "$@" ${NC}
}

function logg {
    echo -e ${GREEN} "$@" ${NC}
}

function log {
    echo -e "$@"
}

function validate_arg {
    valid=$(echo $1 | sed s'/^[\-][a-z0-9A-Z\-]*/valid/'g)
    [ "x$1" == "x$0" ] && return 0;
    [ "x$1" == "x" ] && return 0;
    [ "$valid" == "valid" ] && return 0 || return 1;
}

function print_help {
                log "Usage: `basename $0` [OPTION]";
                log "  -d, --distribution\tdistribution name" ;
                log "  --description\tDescription for use in notifications" ;
                log "  --job-url\tURL to the job on jenkins" ;
                log "  -t, --target\twhere target is one of bootimage|recoveryimage|otapackage" ;
                log "  -e, --type\twhere type is one of user|userdebug|eng" ;
                log "  --device\tdevice name" ;
                log "  -H, --host\trsync/ssh host details. In the form [user@]hostname";
                log "  -p, --path\tbuild top path" ;
                log "  -P, --print-via-proxy\tConnect to telegram via host specified above." ;
                log "  -o, --output\toutput path (path to jenkins archive dir)";
                log "\nOptional commands:";
                log "  -b\tbuild number";
                log "\n  --branch-map --ref-map\tSpecify branches to check out for particular repositories";
                log "              \tin the form repo directory:branch, for example,";
                log "              \t--branch-map vendor/samsung:cm-14.1-experimental ";
                log "              \tThis option can be specified multiple times.\n ";
                log "--pick-lineage --pick-lineage-topic \t Pick specified lineage gerrit changes.";
                log "--pick  --pick-topic \t Pick specified local (msm8916) gerrit changes.";
                log "              \tChanges can be comma separated, or the flag";
                log "              \tcan be called repeatedly with each change. ";
                log "  -s, --silent\tdon't publish to Telegram";
                log "  -c, --odin\tbuild compressed (ODIN) images";
                log "  --days\tNumber of days of changelogs to generate";
                log "  -r, --clean\tclean build directory on completion";
                log "  --make-args\tArguments to pass to make at build time.";
                log "  -N, --no-pack-bootimage\tDon't pack the bootimage into a zip.\n";
                log "  -R, --retry\tRetry build this many times upon failure before giving up.";
                log "              \tDefault is 0 ";
                log "  -U, --upload-retry\tRetry file upload this many times upon failure before giving up.";
                log "              \tDefault is 3 ";
                log "  -a, --sync_all\tSync entire build tree";
                log "  -v, --sync\tSync device/kernel/vendor trees";
                log "  -u, --su\tAdd SU to build";
                log "  --update-script\tUpdate build script immediately";
                log "  -j\tnumber of parallel make jobs to run";

        exit
}

prev_arg=
while [ "$1" != "" ]; do
    cur_arg=$1

    # find arguments of the form --arg=val and split to --arg val
    if [ -n "`echo $cur_arg | grep -o =`" ]; then
        cur_arg=`echo $1 | cut -d'=' -f 1`
        next_arg=`echo $1 | cut -d'=' -f 2`
    else
        cur_arg=$1
        next_arg=$2
    fi

    case $cur_arg in

        -a | --sync-all )
            SYNC_ALL=1
            ;;
        -b )
            JOB_BUILD_NUMBER=$next_arg
            ;;
        --branch-map | --ref-map )
            logb "\t\tRef map $next_arg specified"
            REPO_REF_MAP=("${REPO_REF_MAP[@]}" "$next_arg")
            ;;
        --clean )
            CLEAN_TARGET_OUT=1
            ;;
        -d )
            DISTRIBUTION=$next_arg
            ;;
        --days )
            CHANGELOG_DAYS=$next_arg
            ;;
        --device )
            DEVICE_NAME=$next_arg
            ;;
        --description )
            JOB_DESCRIPTION=$next_arg
            ;;
        --distro )
            DISTRIBUTION=$next_arg
            ;;
        --job-url )
            JOB_URL=$next_arg
            ;;
        -e | --type )
            BUILD_VARIANT=$next_arg
            ;;
        -j | --jobs )
            JOB_NUMBER=$next_arg
            ;;
        -h | --help )
            print_help
            ;;
        -H | --host )
            SYNC_HOST=$next_arg
            ;;
        --make-args )
            logb "\t\tmake argument $next_arg specified"
            MAKE_ARGS="$MAKE_ARGS $next_arg "
            ;;
        --manifest )
            MANIFEST_NAME=$next_arg
            ;;
        -N | --no-pack-bootimage)
            NO_PACK_BOOTIMAGE=1
            ;;
        --node)
            TARGET_NODE=$next_arg
            ;;
        --node-unavail-count)
            NODE_UNAVAILABLE_COUNT=$next_arg
            ;;
        -o | --output )
            OUTPUT_DIR=$next_arg
            ;;
        --odin)
            MAKE_ODIN_PACKAGE=1
            ;;
        -p | --path )
            BUILD_TOP=`realpath $next_arg`
            ;;
        -P)
            PRINT_VIA_PROXY=y
            ;;
        --pick )
            logb "\t\tChange(s) $next_arg specified"
            LOCAL_REPO_PICKS="${LOCAL_REPO_PICKS} `echo $next_arg|sed s'/,/ /'g`"
            ;;
        --pick-lineage )
            logb "\t\tLineage change(s) $next_arg specified"
            LINEAGE_REPO_PICKS="${LINEAGE_REPO_PICKS} `echo $next_arg|sed s'/,/ /'g`"
            ;;
        --pick-lineage-topic )
            logb "\t\tLineage topic(s) $next_arg specified"
            LINEAGE_REPO_TOPICS="${LINEAGE_REPO_TOPICS} `echo $next_arg|sed s'/,/ /'g`"
            ;;
        --pick-topic )
            logb "\t\tTopic(s) $next_arg specified"
            LOCAL_REPO_TOPICS="${LOCAL_REPO_TOPICS} `echo $next_arg|sed s'/,/ /'g`"
            ;;
        --print-via-proxy ) PRINT_VIA_PROXY=y
            ;;
        -R | --retry )
            BUILD_RETRY_COUNT=$next_arg
            ;;
        -r)
            CLEAN_TARGET_OUT=1
            ;;
        --restored-state ) RESTORED_BUILD_STATE=1
            ;;
        -s | --silent )
            SILENT=1
            ;;
        --sync)
            SYNC_VENDOR=1
            ;;
        -t | --target )
            BUILD_TARGET=$next_arg
            ;;
        -U | --upload-retry )
            UPLOAD_RETRY_COUNT=$next_arg
            ;;
        -u | --su )
            WITH_SU=true
            ;;
        --update-script )  UPDATE_SCRIPT=1
            ;;
        -v)
            SYNC_VENDOR=1
            ;;
        *)
            validate_arg $cur_arg;
            if [ $? -eq 0 ]; then
                logr "Unrecognised option $cur_arg passed"
                print_help
            else
                validate_arg $prev_arg
                if [ $? -eq 1 ]; then
                    logr "Argument $cur_arg passed without flag option"
                    print_help
                fi
            fi
            ;;
    esac
    prev_arg=$1
    shift
done

if [ "x$UPDATE_SCRIPT" == "x" ]; then
    if [ "x${BUILD_TOP}" == "x" ]; then
        logr "No android source directory specified!"
        exit 1
    fi
    if [ "x$SYNC_ALL" == "x" ] && [ "x$SYNC_VENDOR" == "x" ]; then
        if [ "x${DEVICE_NAME}" == "x" ]; then
            logr "No device name specified!"
            exit 1
        fi

        if [ "x${BUILD_VARIANT}" == "x" ]; then
            logr "No build variant specified!"
            exit 1
        fi

        if [ "x${BUILD_TARGET}" == "x" ]; then
            logr "No build target specified!"
            exit 1
        fi
    fi
fi

# fetch the critical build scripts
logb "Getting build script list..."
script_dir=${BUILD_TEMP}/scripts
file_list=$(${CURL} ${SCRIPT_REPO_URL}/list.txt 2>/dev/null)

if [ $? -ne 0 ]; then
    logr "Failed! Checking for local version.."
    file_list=$(cat $(dirname $0)/list.txt)
    if [ $? -ne 0 ]; then
        logr "Fatal! No local version found."
        exit 1
    fi
else
    ${CURL} ${SCRIPT_REPO_URL}/list.txt 1>$(dirname $0)/list.txt 2>/dev/null
fi

mkdir -p ${script_dir}

# source the files
for source_file in ${file_list}; do

    if [ -n "$UPDATE_SCRIPT" ] || ! [ -e $(dirname $0)/${source_file} ]; then
        logb "Fetching $source_file ..."
        ${CURL} ${SCRIPT_REPO_URL}/${source_file} 1>${script_dir}/${source_file} 2>/dev/null
        logg "Updating local version of $source_file ..."
        mv -f ${script_dir}/${source_file} $(dirname $0)/${source_file}
    fi


    if ! [ -e $(dirname $0)/${source_file} ]; then
        logr "Failed to fetch file $source_file"
        exit 1
    fi

    logb "Sourcing $source_file ..."
    . $(dirname $0)/${source_file}

    echo
done

if [ "x$UPDATE_SCRIPT" == "x" ]; then
    # setup env vars
    bootstrap "$@"
    # check if any other builds are running
    acquire_build_lock
    # restore a terminated build
    restore_saved_build_state
    # get the platform info
    get_platform_info
    # clean build top
    clean_out
    # sync manifests
    sync_manifests
    # sync the repos
    sync_vendor_trees "$@"
    sync_all_trees "$@"

    if [ "x${BUILD_TARGET}" != "x" ] && [ "x${BUILD_VARIANT}" != "x" ] && [ "x${DEVICE_NAME}" != "x" ]; then
        # apply custom repo-branch maps
        apply_repo_map
        # setup the build environment
        setup_env "$@"
        # apply repopicks
        apply_repopicks
        # print the build start text
        print_start_build
        #save build state
        save_build_state "$@"
        # make the targets
        make_targets
        # copy the files
        copy_files
        # generate the changes
        generate_changes
        # reverse repo maps
        reverse_repo_map
        # clean build state
        clean_state
        # sync the build script
        sync_script "$@"
        # remove lock
        remove_build_lock
        # upload build artifacts
        upload_artifacts
        # end the build
        print_end_build
    fi
fi
# remove temp dir
remove_temp_dir
if [ "x${BUILD_TARGET}" == "x" ] || [ "x${BUILD_VARIANT}" == "x" ] || [ "x${DEVICE_NAME}" == "x" ]; then
    # check if any other builds are running
    acquire_build_lock
    # sync the build script
    sync_script "$@"
fi
# remove lock
remove_build_lock

END_TIME=$( date +%s )

# PRINT RESULT TO USER
echoTextGreen "SCRIPT COMPLETED!"
echo -e ${RED}"TIME: $(format_time ${END_TIME} ${START_TIME})"${RESTORE}; newLine
