#include <fstream>
#include <getopt.h>
#include <iostream>
#include <stdlib.h> /* atoi */
#include <string.h>

using namespace std;

string my_id = "";
string my_file = "";

void PrintHelp() {
  std::cout << "This program extract Queries from binlogs\n"
               "In case of row based binlog, it requires you to pass a --file "
               "already processed by:\n"
               "mysqlbinlog -v -v -v binlog.000001\n"
               "\n"
               "--file <fname>:                  binlog to search\n"
               "--match <string>:                                \n"
               "--help:              Show help\n";
  exit(1);
}

void ProcessArgs(int argc, char **argv) {

  if(argc != 3)
  {
    cout << argc << endl;
    cout << "You need to pass --file and --match\n";
    PrintHelp();
  }
  const char *const short_opts = "f:m:h";
  const option long_opts[] = {{"file", required_argument, nullptr, 'f'},
                              {"match", required_argument, nullptr, 'm'},
                              {"help", no_argument, nullptr, 'h'},
                              {nullptr, no_argument, nullptr, 0}};

  while (true) {
    const auto opt = getopt_long(argc, argv, short_opts, long_opts, nullptr);

    if (-1 == opt)
      break;

    switch (opt) {
    case 'f':
      my_file = std::string(optarg);
      break;

    case 'm':
      my_id = std::string(optarg);
      break;
    case 'h': // -h or --help
    case '?': // Unrecognized option
    default:
      PrintHelp();
      break;
    }
  }
}

int main(int argc, char *argv[]) {
  ProcessArgs(argc, argv);
  bool found_id = false;
  string ts = "";
  string dml = "";
  ifstream in(my_file.c_str());
  if (!in) {
    cout << "Cannot open input file.\n";
    return 1;
  }
  char str[255];
  while (in) {
    in.getline(str, 255); // delim defaults to '\n'
    if (in) {
      string line(str);
      if (line.substr(0, 7) == "#190404") {
        if (found_id) {
          cout << ts;
          cout << dml << endl;
          found_id = false;
        }

        ts = line;
        dml = "";
      } else if (line.substr(0, 3) == "###") {
        dml += "\n" + line;
        size_t found = line.find(my_id);
        if (found != string::npos)
          found_id = true;
      }
    }
  }
  in.close();
  return 0;
}