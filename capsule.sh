#!/bin/bash

set -e
source ./capsule.conf

# init

LOCKFILE="/tmp/autobuilder.lock"
LOCK_FILE_IS_FOUND=42
ORIGIN=$(pwd)
BUILDDIR=$(mktemp -d "/tmp/${CAPSULE_PROJECT}-autobuild.XXXXXX")

# subs

function on_exit() {
	exit_code=$?
    if [[ $exit_code -gt 0 ]]; then

		if [[ $exit_code == $LOCK_FILE_IS_FOUND ]]; then
			echo "Lock file detected, skipping."
		else
	        echo "FAILURE during processing of $project @'$branch'" >&2
	        mv $logfile $logfile.failed
			rm -f $LOCKFILE
			rm -rf $BUILDDIR
		fi
    else
		echo "All builds done with success"
		rm -f $LOCKFILE
		rm -rf $BUILDDIR
    fi
}

trap on_exit EXIT

# main

if [[ -f $LOCKFILE ]]; then
	exit $LOCK_FILE_IS_FOUND
fi

touch $LOCKFILE
mkdir -p $CAPSULE_LOGDIR

source $HOME/perl5/perlbrew/etc/bashrc

cd $BUILDDIR
for branch in "master" "devel"
do
    for perl in $HOME/perl5/perlbrew/perls/perl-*
    do 
        theperl="$(basename $perl)"
        echo "Building $CAPSULE_PROJECT @ $branch for $theperl ..."

        perlbrew switch $theperl 
		hash -r

        mkdir -p "$CAPSULE_LOGDIR/$branch"
        logfile="$CAPSULE_LOGDIR/$branch/$CAPSULE_PROJECT.$theperl.pending.txt"
        
        buildtime=$(date +"%Y-%m-%d %H:%M:%S")
        echo "Autobuild of $project with $theperl" >> $logfile
        echo "build time: $buildtime" >> $logfile
        echo "=================================================================================" >> $logfile
        perl -v >> $logfile
        echo "" >> $logfile

        rm -rf $CAPSULE_PROJECT

        git clone $CAPSULE_GIT_REPO --branch $branch >> $logfile 2>&1
        cd $CAPSULE_PROJECT

		# we want the last commit _before_ the merge we just did, so 
        lastrev=$(git log | head -n 1 | awk '{print $2}')

        echo "" >> $logfile
        echo "==> Using $CAPSULE_GIT_REPO @ $branch [ $lastrev ]" >> $logfile
        echo "" >> $logfile

        pendinglog="$logfile"
        logfile="$CAPSULE_LOGDIR/$branch/$CAPSULE_PROJECT.$theperl.$lastrev.txt"

        # if logfile already exist, it means the run has already been done
        if [[ -f "$logfile" ]] ; then
            echo "  -> already done for $lastrev"
            rm -f $pendinglog
			cd ..
            continue
        fi

        # Test never done with $lastrev, doing it
        mv "$pendinglog" "$logfile"

        # make sure all deps are OK for $theperl
        cpanm $CAPSULE_CPAN_DEPS >> $logfile 2>&1

        # build $project
        perl Makefile.PL >> $logfile 2>&1
        make >> $logfile 2>&1
        HARNESS_VERBOSE=1 make test >> $logfile  2>&1

		# link the last run for $theperl
		rm -f "$CAPSULE_LOGDIR/$branch.last.$theperl.txt"
		ln -s $logfile "$CAPSULE_LOGDIR/$branch.last.$theperl.txt"

		# cover score
		cover_file="$CAPSULE_LOGDIR/$branch/$lastrev.cover.txt"
		if [[ ! -e $cover_file ]]; then
			cover -test \
				-coverage statement \
				-coverage branch \
				-coverage subroutine > $cover_file 2>&1 

			rm -f "$CAPSULE_LOGDIR/$branch/last.cover.txt"
			ln -s $cover_file "$CAPSULE_LOGDIR/$branch/last.cover.txt"
		fi

        cd ..
    done
done

cd $origin
rm -rf $BUILDDIR

