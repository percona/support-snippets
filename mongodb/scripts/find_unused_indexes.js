// This script will print in the output indexes that never been used based on the access.
// Added the drop command

var ldb = db.adminCommand( { listDatabases: 1 } ); 

for ( i = 0; i < ldb.databases.length; i++ ) { 

  if ( ldb.databases[i].name != 'admin' && ldb.databases[i].name != 'config' && ldb.databases[i].name != 'local') {
    print('DATABASE ',ldb.databases[i].name); 
    print("+++++++++++++++++++++++++++++++++++++++++");

    var db = db.getSiblingDB(ldb.databases[i].name); 
    var cpd = db.getCollectionNames(); 

    for ( j = 0; j < cpd.length; j++ ) { 

      if ( cpd[j] !=  'system.profile' ) { 

        var indexstats = JSON.parse(JSON.stringify(db.runCommand( { aggregate : cpd[j], pipeline : [ { $indexStats: { } }, { $match: { "accesses.ops": 0 } } ], cursor: { batchSize: 100 }  } ).cursor.firstBatch));

        for ( k = 0; k < indexstats.length; k++ ) { 
          if ( k == 0) {
            print("COLL :"+cpd[j]); 
          }
          
          indexname = ((JSON.stringify(indexstats[k].key)));
          indexusage = ((JSON.stringify(indexstats[k].accesses.ops)));
          indexes_name = (JSON.stringify(indexstats[k].name)).replace(/,/g ,"_");
          

          if (indexname != '{"_id":1}') {
            print(indexname," ==> ",indexusage);
            print("Drop command: db.getSiblingDB('" + db + "')." + cpd[j] + ".dropIndex(" + indexes_name + ")");

          }
        }
     
        print("\n");
        
      } 
    } 
    print("\n");
  }
}
