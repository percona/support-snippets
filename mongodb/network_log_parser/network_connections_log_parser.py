#!/usr/bin/python

import os, sys, string, json
import argparse

def main(mongodb_log_file):

  if not os.path.exists(mongodb_log_file):
    sys.exit("Could not find MongoDB log file %s" % mongodb_log_file)

  file = open(mongodb_log_file)
  lines = file.readlines()
  file.close()

  connections_stats = {}
  connections = {}

  for line in lines:
    try:
      line_s = line.split()
      timestamp = string.join(line_s[0][:len(line_s[0])-9].split('T'))
      if line_s[2]=='NETWORK':
        if line_s[3].startswith('[thread') and line_s[4]=='connection' and line_s[5]=='accepted':
          source_ip, source_port = line_s[7].split(':')
          conns_open = int(line_s[9].strip('('))
          if not connections_stats.has_key(timestamp):
            connections_stats[timestamp] = {'open': conns_open, 'opened': 1, 'closed': 0}
          else:
            connections_stats[timestamp]['open'] = conns_open
            connections_stats[timestamp]['opened'] += 1
          conn_number = int(line_s[8].strip('#'))
          if not connections.has_key(conn_number):
            connections[conn_number] = {'source_ip': source_ip, 'source_port': source_port, 'open_at': timestamp}
          else:
            connections[conn_number]['source_ip'] = source_ip
            connections[conn_number]['source_port'] = source_port
            connections[conn_number]['open_at'] = timestamp
                          
      elif line_s[2]=='ACCESS' and line_s[4]=='Successfully' and line_s[5]=='authenticated':
        conn_number = int(line_s[3].strip('[conn').strip(']'))
        auth_as = "%s %s" % (line_s[7], line_s[8])
        auth_on = line_s[10]
        if not connections.has_key(conn_number):
          connections[conn_number] = {'auth_as': auth_as, 'auth_on': auth_on, 'auth_at': timestamp}
        else:
          connections[conn_number]['auth_as'] = auth_as
          connections[conn_number]['auth_on'] = auth_on
          connections[conn_number]['auth_at'] = timestamp
              
      elif line_s[2]=='-' and line_s[4]=='end' and line_s[5]=='connection':
        conn_number = int(line_s[3].strip('[conn').strip(']'))
        if not connections.has_key(conn_number):
          connections[conn_number] = {'closed_at': timestamp}
        else:
          connections[conn_number]['closed_at'] = timestamp
        conns_open = int(line_s[7].strip('('))
        if not connections_stats.has_key(timestamp):
          connections_stats[timestamp] = {'open': conns_open, 'opened': 0, 'closed': 1}
        else:
          connections_stats[timestamp]['open'] = conns_open
          connections_stats[timestamp]['closed'] += 1
        
    except Exception, error:
      print str(error)

  print "\nCompleted processing of log file %s:" % mongodb_log_file
  print "- Number of recorded connections: %i" % len(connections)
  print "- Number of precessed seconds: %i\n" % len(connections_stats)

  connections_file_name = "%s.json" % mongodb_log_file
  connections_file = open(connections_file_name, 'w')
  json.dump(connections, connections_file)
  connections_file.close()   
  print "- Generated JSON file: %s\n" % connections_file_name

  connections_stats_file_name = "%s.csv" % mongodb_log_file
  connections_stats_file = open(connections_stats_file_name, 'w')
  connections_stats_file.write("timestamp;open connections;opened;closed\n")
  for i in sorted(connections_stats):
    timestamp = i
    open_conns = connections_stats[i]['open']
    opened_conns = connections_stats[i]['opened']
    closed_conns = connections_stats[i]['closed']
    connections_stats_file.write("%s;%i;%i;%i\n" % (timestamp, open_conns, opened_conns, closed_conns))
  connections_stats_file.close()
  print "- Generated CSV file: %s\n" % connections_stats_file_name
  
  sys.exit(0)
    
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('log', help='path to the MongoDB log file')
    args_namespace = parser.parse_args()
    args = vars(args_namespace)['log']
    main(args)
