db.currentOp().inprog.forEach(
  function(op) {
    // Define the seconds here
    if(op.secs_running > 5) printjson(op);
  }
)
