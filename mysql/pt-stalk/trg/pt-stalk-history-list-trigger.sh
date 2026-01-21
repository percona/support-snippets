#!/bin/bash
trg_plugin() {
  mysql "${EXT_ARGV}" -BNe "SELECT count FROM information_schema.INNODB_METRICS WHERE name = 'trx_rseg_history_len'";
}
