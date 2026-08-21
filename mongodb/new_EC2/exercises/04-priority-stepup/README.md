# Question 4 — node1 should be PRIMARY again

The replica set `interview` is up across `node1`, `node2`, and `node3`,
but node2 keeps winning elections. Application code expects node1 to be
PRIMARY in steady state.

Reconfigure the replica set so that **node1 becomes PRIMARY**. It has to
stay the preferred member, so node1 wins the next election too, not just
this one.
