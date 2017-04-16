#!/bin/bash

function check_oc_enabled {
ARG="--oc"
for i in `seq 0 ${#}`; do
	if [ "${!i}" == "$ARG" ]; then
		logb "\t\tOverclocking is enabled"
		OVERCLOCKED=y
	fi
done
}

PATCHES=("${PATCHES[@]}" "check_oc_enabled")
