
## FTDC Parser

- This tool parses diagnostic.data from MongoDB.

**Dependency**
- Python:
matplotlib
argparse
ast
json

- Repo:
https://github.com/10gen/ftdc-utils


## How to use:

**1.** Install ftdc utils using:
`go install github.com/10gen/ftdc-utils/cmd/ftdc@latest`  
- The `go install` command installs binaries to `$GOBIN`, which defaults to `$GOPATH/bin`.
- `$GOPATH` (which defaults to $HOME/go on Unix and %USERPROFILE%\go on Windows)

You can then move the ftdc binary to your user $PATH:  
`/usr/bin`

**2.** From a running mongodb (3.2+) use ftdc tool to export as a JSON;
```
    cd /mongodb/data/
    ftdc decode metrics.2024-06-20T14-43-53Z-00000 -o ftdc.json
```
- Sample output:
```
chunk in file 'metrics.2024-06-20T14-43-53Z-00000' with 2405 metrics and 299 deltas on Thu Jun 20 17:57:25 -03 2024
found 22631 samples
```
**3.** Use the **ftdc_parser.py** to evaluate the metrics:  
`python3 ftdc_parser.py -i ftdc.json`  
- Sample output:
```
Loading file...
Total of timestamps : 33
0 Start Time: 2024-06-20 21:35:57 # of deltas: 10
1 Start Time: 2024-06-20 21:36:19 # of deltas: 4
2 Start Time: 2024-06-20 21:36:24 # of deltas: 0
3 Start Time: 2024-06-20 21:36:25 # of deltas: 299
4 Start Time: 2024-06-20 21:41:25 # of deltas: 299
5 Start Time: 2024-06-20 21:46:25 # of deltas: 299
6 Start Time: 2024-06-20 21:51:25 # of deltas: 299
7 Start Time: 2024-06-20 21:56:25 # of deltas: 299
8 Start Time: 2024-06-20 22:01:25 # of deltas: 299
9 Start Time: 2024-06-20 22:06:25 # of deltas: 299
10 Start Time: 2024-06-20 22:11:25 # of deltas: 299
11 Start Time: 2024-06-20 22:16:25 # of deltas: 299
12 Start Time: 2024-06-20 22:21:25 # of deltas: 299
13 Start Time: 2024-06-20 22:26:25 # of deltas: 299
14 Start Time: 2024-06-20 22:31:25 # of deltas: 299
15 Start Time: 2024-06-20 22:36:25 # of deltas: 299
16 Start Time: 2024-06-20 22:41:25 # of deltas: 299
17 Start Time: 2024-06-20 22:46:25 # of deltas: 299
18 Start Time: 2024-06-20 22:51:25 # of deltas: 299
19 Start Time: 2024-06-20 22:56:25 # of deltas: 299
20 Start Time: 2024-06-20 23:01:25 # of deltas: 299
21 Start Time: 2024-06-20 23:06:25 # of deltas: 299
22 Start Time: 2024-06-20 23:11:25 # of deltas: 299
23 Start Time: 2024-06-20 23:16:25 # of deltas: 299
24 Start Time: 2024-06-20 23:21:25 # of deltas: 299
25 Start Time: 2024-06-20 23:26:25 # of deltas: 299
26 Start Time: 2024-06-20 23:31:25 # of deltas: 299
27 Start Time: 2024-06-20 23:36:25 # of deltas: 299
28 Start Time: 2024-06-20 23:41:25 # of deltas: 299
29 Start Time: 2024-06-20 23:46:25 # of deltas: 299
30 Start Time: 2024-06-20 23:51:25 # of deltas: 299
31 Start Time: 2024-06-20 23:56:25 # of deltas: 293
32 Start Time: 2024-06-21 00:01:19 # of deltas: 20
```

0..32 It is the timestamp index; For bigger files, each slice will have 5 minutes.

**4.** Printing the metrics from **ftdc.json**:  

`python3 ftdc_parser.py -i ftdc.json --generate True -d 0`
> [!NOTE]
> The above command will print out all metrics from the metrics file to the terminal.

- where `--generate` means show the metrics, `-d` means the time slice, 0 in that case. 

**4.1.** If you want to filter by a specific metric value use `-f` 'text' as follows:

`python3 ftdc_parser.py -i ftdc.json --generate True -d 0 -f 'serverStatus.wiredTiger.concurrentTransactions'`  
- Sample output:
```
Loading file...
Total of timestamps : 80
serverStatus.wiredTiger.concurrentTransactions.write.out;0;0;0;0;0;0;0;0;
serverStatus.wiredTiger.concurrentTransactions.write.available;128;0;0;0;0;0;0;0;
serverStatus.wiredTiger.concurrentTransactions.write.totalTickets;128;0;0;0;0;0;0;0;
serverStatus.wiredTiger.concurrentTransactions.read.out;0;0;0;0;0;0;0;0;
serverStatus.wiredTiger.concurrentTransactions.read.available;128;0;0;0;0;0;0;0;
serverStatus.wiredTiger.concurrentTransactions.read.totalTickets;128;0;0;0;0;0;0;0;

```
The deltas from each `serverStatus.wiredTiger.concurrentTransactions.*` metrics from timestamp 0


## Generating graphs
graph.py receives as stdin the output of the ftdc_parser.py

**1.** Use the same parameters as earlier but add the `-t` True flag to show the timestamps:
`python3 ftdc_parser.py -i ftdc.json --generate True -d 0 -f 'serverStatus.wiredTiger.concurrentTransactions' -t True | python3 graph.py` 
- Sample output:
```
Generating ['serverStatus.wiredTiger.concurrentTransactions.write.out']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
Generating ['serverStatus.wiredTiger.concurrentTransactions.write.available']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
Generating ['serverStatus.wiredTiger.concurrentTransactions.write.totalTickets']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
Generating ['serverStatus.wiredTiger.concurrentTransactions.read.out']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
Generating ['serverStatus.wiredTiger.concurrentTransactions.read.available']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
Generating ['serverStatus.wiredTiger.concurrentTransactions.read.totalTickets']
['43:54', '43:55', '43:56', '43:57', '43:58', '43:59', '44:00']
[0, 0, 0, 0, 0, 0, 0]
```

- That process will generate a graph for each line:
```
serverStatus_wiredTiger_concurrentTransactions_write_out.png
serverStatus_wiredTiger_concurrentTransactions_write_available.png
serverStatus_wiredTiger_concurrentTransactions_write_totalTickets.png
serverStatus_wiredTiger_concurrentTransactions_read_out.png
serverStatus_wiredTiger_concurrentTransactions_read_available.png
serverStatus_wiredTiger_concurrentTransactions_read_totalTickets.png
```

