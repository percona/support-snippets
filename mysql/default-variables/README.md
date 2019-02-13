#MySQL Default Variables

This folder contains the default variables for each MySQL release.
You can use it to compare customer variables that differ from default.
Pt-stalk provides a variable file, below is a command to compare:

```
curl https://raw.githubusercontent.com/percona/support-snippets/master/mysql/default-variables/5.7.24-default.out -o 5.7.24-default.out
find . -name '*variables' -print -quit | xargs -- cat | grep -B 9999 'select \* from performance_schema.variables_by_thread order by thread_id, variable_name;' > mine-variables.out
diff --side-by-side --suppress-common-lines 5.7.24-default.out mine-variables.out
```
