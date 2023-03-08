// This script will list redundant indexes basewd on its prefix. 
// 2023: It will also provide the command to drop the index
//

var ldb = db.adminCommand( { listDatabases: 1 } ); 

for ( i = 0; i < ldb.databases.length; i++ ) { 

  if ( ldb.databases[i].name != 'admin' && ldb.databases[i].name != 'config' && ldb.databases[i].name != 'local') {
    print('DATABASE ',ldb.databases[i].name); 
    print("+++++++++++++++++++++++++++++++++++++++++");

    var db = db.getSiblingDB(ldb.databases[i].name); 
    var cpd = db.getCollectionNames(); 

    for ( j = 0; j < cpd.length; j++ ) { 

      if ( cpd[j] !=  'system.profile' ) { 

        var indexes = JSON.parse(JSON.stringify(db.runCommand( { listIndexes: cpd[j] } ).cursor.firstBatch)); 
        var indexes_name = JSON.parse(JSON.stringify(db.runCommand( { listIndexes: cpd[j] } ).cursor.firstBatch));
        print("Collection: "+cpd[j]); 
        for ( k = 0; k < indexes.length; k++ ) { 
          indexes_name[k] = (JSON.stringify(indexes[k].name)).replace(/,/g ,"_");
          indexes[k] = (((JSON.stringify(indexes[k].key)).replace("{","")).replace("}","")).replace(/,/g ,"_"); 
        } 

        var founddup = false; 

        for ( k1 = 0; k1 < indexes.length; k1++ ) { 
          for ( k2 = 0; k2 < indexes.length; k2++ ) { 
            if ( k1 != k2 ) { 
              if (indexes[k1].startsWith(indexes[k2],0)) { 
                print("{ "+indexes[k2]+" } is the left prefix of { "+indexes[k1]+" } and should be dropped");
                print("Drop command: db.getSiblingDB('" + db + "')." + cpd[j] + ".dropIndex(" + indexes_name[k2] + ")");
                founddup = true; 
              } 
            }
          } 
        } 

        if (!founddup) { 
          print("no duplicate indexes found"); 
        } 
        
        print("\n"); 
      } 
    } 
    print("\n");
  }
}
