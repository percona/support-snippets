

This bash script will iterate through all mysqladmin output files from a pt-stalk sample and will run pt-mext on them.
It will remove multiline Rsa_public_key status output, since it breaks pt-mext.

The script can receive one parameter. If it's used, then it will assume it's the path to the directory with the samples. 
If not, it will use the output of running `pwd`, which should give the current working directory. 
NOTE that the tool will not do any checks on what is received as first parameter.

The script will work on both Linux and MacOS (in-file substitution is resolved differently in both).

# Running it

To run with an explicit path, execute as `./pt_mext_all path_to_samples`.

To be able to use the `pwd` functionality (ie: argument-less invocation), you should have the script in a directory
from your path. Then, just `cd` to the wanted directory and run `pt_mext_all`.
