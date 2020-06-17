#!/bin/bash
# Needs to be run from the mysql datadir
# A file with schema names must be located in /tmp/schema_list.out
# dbsake must be in $PATH
# curl -s http://get.dbsake.net > ~/bin/dbsake && chmod +x ~/bin/dbsake

mysql_client="mysql -uuser -ppassword "

for schema in $(cat /tmp/schema_list.out); do
  echo "### Schema: $schema"
  cd $schema;

  for table in `ls -1 *frm`; do
    echo "## Processing $table";
    column_count=$(dbsake frmdump $table | grep "^  \`" | wc -l);
    echo " Column count from .frm file is: $column_count";
    table_no_frm=${table/.frm/}
    column_count_i_s=$($mysql_client -BNe "SELECT count(COLUMN_NAME) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='${schema}' AND TABLE_NAME='${table_no_frm}'");
    echo " Column count from I_S is:       $column_count_i_s"
    if [ $column_count -ne $column_count_i_s ]; then
      echo " !!! Column count differs for ${schema}.${table}";
    fi;

  done;

  echo;
  cd ..;
done;

