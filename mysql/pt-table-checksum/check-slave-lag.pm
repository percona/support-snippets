# #############################################################################
# pt_table_checksum_plugin
# #############################################################################
{

    package pt_table_checksum_plugin;
    use strict;
    use warnings FATAL => 'all';
    use English qw(-no_match_vars);
    use constant PTDEBUG        => $ENV{PTDEBUG}        || 0;
    use constant PT_SKIP_LAG_CHECK_COUNT => $ENV{PT_SKIP_LAG_CHECK_COUNT} || 100;

    sub new {
        my ($class, %args) = @_;
        my $self = {%args};
        return bless $self, $class;
    }

    sub _d {
        my ($package, undef, $line) = caller 0;
        @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
            map { defined $_ ? $_ : 'undef' } @_;
        print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
    }

    sub get_slave_lag {
        my ($self, %args) = @_;
        my $get_lag = sub {
            my ($cxn) = @_;
            my $dbh = $cxn->dbh();
            if (!$dbh || !$dbh->ping()) {
                eval { $dbh = $cxn->connect() };    # connect or die trying
                if ($EVAL_ERROR) {
                    chomp $EVAL_ERROR;
                    die "Lost connection to replica "
                        . $cxn->name()
                        . " while attempting to get its lag ($EVAL_ERROR)\n";
                }
            }

            $self->{chunk_count}++;
            PTDEBUG && _d('pt-table-checksum get_lag plugin: chunk_count', $self->{chunk_count});

            if (($self->{chunk_count} % PT_SKIP_LAG_CHECK_COUNT) == 0) {
                if (!$dbh || !$dbh->ping()) {
                    eval { $dbh = $cxn->connect() };    # connect or die trying
                    if ($EVAL_ERROR) {
                        chomp $EVAL_ERROR;
                        die "Lost connection to replica "
                            . $cxn->name()
                            . " while attempting to get its lag ($EVAL_ERROR)\n";
                    }
                }
                PTDEBUG && _d('pt-table-checksum get_lag plugin: will check lag');
                eval {
                    my $slavestatus = $dbh->selectrow_hashref("SHOW SLAVE STATUS");
                    return $slavestatus->{seconds_behind_master};
                };
                if ($EVAL_ERROR) {
                    chomp $EVAL_ERROR;
                    die "Cannot get slave status: $EVAL_ERROR";
                }
            } else {
                PTDEBUG && _d('pt-table-checksum get_lag plugin: skipping lag check');
                return 0;
            }
        };
        return $get_lag;
    }
}
1;
