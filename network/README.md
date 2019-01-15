# Configure flapping network

This script adds random latency and drop packets to an interface. It's indicated to simulate bad network.
It will use `eth0` as default interface, but you can pass an interface as argv[1].
## Test Run

```
./add_latency.sh eth1
Using eth1 as network interface
Thu Dec 27 18:54:04 UTC 2018 will sleep for 6 seconds while adding 3172ms of latency and 50% of packet loss
Thu Dec 27 18:54:10 UTC 2018 Done
Thu Dec 27 18:54:10 UTC 2018 Sleeping for 5 seconds to allow node to rejoin

Thu Dec 27 18:54:45 UTC 2018 will sleep for 5 seconds while adding 3199ms of latency and 50% of packet loss
Thu Dec 27 18:54:50 UTC 2018 Done
Thu Dec 27 18:54:50 UTC 2018 Sleeping for 5 seconds to allow node to rejoin

Thu Dec 27 18:54:55 UTC 2018 will sleep for 5 seconds while adding 3403ms of latency and 60% of packet loss
Thu Dec 27 18:55:00 UTC 2018 Done
Thu Dec 27 18:55:00 UTC 2018 Sleeping for 5 seconds to allow node to rejoin

Thu Dec 27 18:55:40 UTC 2018 will sleep for 7 seconds while adding 3436ms of latency and 43% of packet loss
Thu Dec 27 18:55:47 UTC 2018 Done
Thu Dec 27 18:55:47 UTC 2018 Sleeping for 5 seconds to allow node to rejoin

Thu Dec 27 18:55:52 UTC 2018 will sleep for 6 seconds while adding 3274ms of latency and 53% of packet loss
Thu Dec 27 18:55:58 UTC 2018 Done
Thu Dec 27 18:55:58 UTC 2018 Sleeping for 5 seconds to allow node to rejoin
```
