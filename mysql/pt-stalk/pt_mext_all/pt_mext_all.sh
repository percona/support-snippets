#!/usr/bin/env bash

# This bash script will iterate through all mysqladmin output files from a
# pt-stalk sample and will run pt-mext on them.
# It will remove multiline Rsa_public_key status output, since it breaks
# pt-mext.
#
# The script can receive one parameter. If it's used, then it will assume it's
# the path to the directory with the samples. If not, it will use the output of
# running `pwd`, which should give the current working directory. NOTE that the
# tool will not do any checks on what is received as first parameter.
#
# The script will work on both Linux and MacOS (in-file substitution is
# resolved differently in both).
#
# To run, simply execute as `./pt_mextify_all path_to_samples`


# Constants:

# If we have a first parameter, assume it's the path to samples directory
# If not, use current working directory
readonly TARGET_DIR="${1:-`pwd`}"


# Functions:

pt_mextify_all_linux(){
  for mext_file in $(ls $TARGET_DIR/*-mysqladmin); do {
    echo $mext_file.mext
    cat $mext_file | sed -e '/\-\-\-\-\-BEGIN\ PUBLIC\ KEY/,+9d' | pt-mext -r -- cat - > $mext_file.mext
  } done;
}

pt_mextify_all_macos(){
  for mext_file in $(ls $TARGET_DIR/*-mysqladmin); do {
    echo $mext_file.mext
    perl -0777 -i.original -pe 's/\n\| Rsa_public_key.*?-----END PUBLIC KEY-----\n \|//igs' $mext_file
    pt-mext -r -- cat $mext_file > $mext_file.mext
  } done;
}


main() {
  # Check if we are running in Linux or MacOS and run appropriate function
  if [ `uname -s` == "Linux" ]; then
    #echo "DEBUG: Linux detected"
    pt_mextify_all_linux
  elif [ `uname -s` == "Darwin" ]; then
    #echo "DEBUG: MacOS detected"
    pt_mextify_all_macos
  else
    echo "ERROR: unsupported OS" `uname -s`
    exit 1
  fi

  exit 0
}

# Call to main
main
