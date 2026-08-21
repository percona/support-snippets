# Question 3 — Build a replica set

The application team needs a 3-member replica set named `interview`
across `node1`, `node2`, and `node3`: one PRIMARY and two SECONDARY.

- `node1` and `node2` already have mongod, but running as standalone.
  Configure the replica set there, first.
- `node3` is a **freshly provisioned host — MongoDB is not installed on
  it yet.** Install Percona Server for MongoDB (the Percona yum repo is
  already configured on the box), then bring node3 into the set
  alongside the others.

Set it up so all three are healthy members of the replica set
`interview`.
