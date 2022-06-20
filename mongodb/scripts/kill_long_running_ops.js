// kills long running ops in MongoDB (taking seconds as an arg to define "long")
// attempts to be a bit safer than killing all by excluding replication related operations
// and only targeting queries as opposed to commands etc.

killLongRunningOps = function(maxSecsRunning) {
    currOp = db.currentOp();
    for (oper in currOp.inprog) {
        op = currOp.inprog[oper-0];
        if (op.secs_running > maxSecsRunning && op.op == "query" && !op.ns.startsWith("local")) {
            print("Killing opId: " + op.opid
                    + " running for over secs: "
                    + op.secs_running);
            db.killOp(op.opid);
        }
    }
};

// To kill you need to invoke the function
//example: killLongRunningOps(5)
