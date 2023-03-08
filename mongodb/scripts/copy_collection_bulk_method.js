// Replace source and targe accordingly to the collection name

var bulkInsert = db.target.initializeUnorderedBulkOp()
var bulkRemove = db.source.initializeUnorderedBulkOp()
var x = 10000
var counter = 0
db.source.find({}).forEach(
    function(doc){
      bulkInsert.insert(doc);
      bulkRemove.find({_id:doc._id}).removeOne();
      counter ++
      if( counter % x == 0){
        bulkInsert.execute()
        bulkRemove.execute()
        bulkInsert = db.target.initializeUnorderedBulkOp()
        bulkRemove = db.source.initializeUnorderedBulkOp()
      }
    }
  )
bulkInsert.execute()
bulkRemove.execute()
