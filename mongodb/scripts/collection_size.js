// This function will calculate all the collection size
//
// First output is the total uncompressed size in memory of all records in a collection. 
// The size does not include the size of any indexes associated with the collection.
// 
// The second output will provide the  total amount of storage allocated to this collection.

function getReadableFileSizeString(fileSizeInBytes) {
    var i = -1;
    var byteUnits = [' kB', ' MB', ' GB', ' TB', 'PB', 'EB', 'ZB', 'YB'];
    do {
        fileSizeInBytes = fileSizeInBytes / 1024;
        i++;
    } while (fileSizeInBytes > 1024);
    return Math.max(fileSizeInBytes, 0.1).toFixed(1) + byteUnits[i];
};

db.adminCommand("listDatabases").databases.forEach(function(d){
  if (d.name != 'config'){
    mdb=db.getSiblingDB(d.name);
    var collectionNames = mdb.getCollectionNames(), stats = [];
    collectionNames.forEach(function (n) { 
      stats.push(mdb[n].stats()); 
    });
    stats = stats.sort(function(a, b) { return b['size'] - a['size']; });
    for (var c in stats) { print(stats[c]['ns'] + ": " + getReadableFileSizeString(stats[c]['size']) + " (" + getReadableFileSizeString(stats[c]['storageSize']) + ")"); }
  }
});
