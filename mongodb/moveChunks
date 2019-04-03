// Lets us defaults will search the last 24 hours, but lets make it output the failures
>x = moveChunkFailures( undefined , undefined , undefined, true);
  
>x[0]
// Success Result would be : 22
>x[1]
// Failed Result would be : 2
>x[2]
/* Result would be array of the failures pairs by source and destionation shards.
They will be groups by the generic "aborted" message or by specfic message like timeouts
{
    _id: "aborted",
    from: "shard1",
    to: "shard2",
    count: 2
}
*/
  
/* TODO -  We should change the  _id  formula to be src_dest_msg , to prevent collisions when you have aborts from differnt pairs but _id is not unqiue */


function moveChunkFailures( startTS, stopTS, configdb,verbose) {
    //default to yesterday
 
    if ( startTS === undefined ) { startTS = new Date( new Date() - (24*60*60*1000));}
 
    // set stop is set
 
    if ( stopTS === undefined) { stopTS = new Date(); }
    // default to config
    if ( configdb === undefined) { db = db.getSiblingDB('config') }
    elif ( typeof configdb == "string"){ db = db.getSiblingDB(configdb) }  
     
 
    succesQuery = {
        time: { $gt: startTS, $lte : stopTS },
        what: "moveChunk.from",
 
        'details.note': 'success'
 
    }
    failureQuery = {
        time: { $gt: yesterday },
        what : "moveChunk.from",
        $or: [
            { 'details.errmsg': { $exists: true }},
            { 'details.note': { $ne: 'success' }}
        ]
    }
    successCount =  db.count(successQuery);
 
    failureCount =  db.coutn(failureQuery);
 
    if (verbose != true){
 
        return [successCount, failureCount]
 
    }
    // Failed migrations.
    result = result.concat(configDB.changelog.aggregate([
        {
            $match: failureQuery
        },
        {
            $group: {
                _id: {
                    msg: "$details.errmsg",
                    from : "$details.from",
                    to: "$details.to"
                },
                count: { $sum: 1 }
            }
        },
        {
            $project: {
                _id: { $ifNull: [ '$_id.msg', 'aborted' ]},
                from: "$_id.from",
                to: "$_id.to",
                count: "$count"
            }
        }
    ]).toArray());
    return [successCount, failureCount, result];
}
