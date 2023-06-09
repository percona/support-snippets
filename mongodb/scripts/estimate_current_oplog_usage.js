// Switch to admin database to get a list of databases
db = db.getSiblingDB("local");
// gathering oplog max size and oplog used
var result = db.getReplicationInfo();
currentOpLogWindow = result.timeDiff;
storageSize = result.usedMB;
maxSize = result.logSizeMB;print(storageSize + "  -  " + maxSize)

if (storageSize/maxSize < 0.98) 
{
  // Estimate oplog window
  totalOpLogTimeWindow = (maxSize*currentOpLogWindow)/storageSize
  print (totalOpLogTimeWindow/60/60 + " hours");
}
