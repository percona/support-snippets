package pt_online_schema_change_plugin;

use Data::Dumper;
use strict;

my $table_name;
my $executed = 0;
my $OLD_table_fks = {};


sub get_fks {
   my ( $self, $ddl, $opts ) = @_;
   my $q   = $self->{Quoter};
   my $fks = {};

   foreach my $fk (
      $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg )
   {
      my ( $name ) = $fk =~ m/CONSTRAINT `(.*?)`/;
      my ( $cols ) = $fk =~ m/FOREIGN KEY \(([^\)]+)\)/;
      my ( $parent, $parent_cols ) = $fk =~ m/REFERENCES (\S+) \(([^\)]+)\)/;

      my ($db, $tbl) = $q->split_unquote($parent, $opts->{database});
      my %parent_tbl = (tbl => $tbl);
      $parent_tbl{db} = $db if $db;

      if ( $parent !~ m/\./ && $opts->{database} ) {
         $parent = $q->quote($opts->{database}) . ".$parent";
      }

      $fks->{$name} = {
         name           => $name,
         colnames       => $cols,
         cols           => [ map { s/[ `]+//g; $_; } split(',', $cols) ],
         parent_tbl     => \%parent_tbl,
         parent_tblname => $parent,
         parent_cols    => [ map { s/[ `]+//g; $_; } split(',', $parent_cols) ],
         parent_colnames=> $parent_cols,
         ddl            => $fk,
      };
}

return $fks;
}

sub new {
   my ($class, %args) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub init {
   my ($self, %args) = @_;
   my $table = $args{orig_tbl};
   $table_name = $table->{name};
}

sub before_create_new_table {
   my ($self, %args) = @_;
   my $dbh     = $self->{cxn}->dbh;
   my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $table_name");
   my $fks = get_fks($self, $row->[1]);

   while (my ($key, $val) = each (%$fks)) {
      # print Dumper(\$val);
      $OLD_table_fks->{"$key"} = {
         name => $val->{'name'},
         colnames => $val->{'colnames'}
      };
   }
}

sub after_drop_old_table {
   my ($self, %args) = @_;
   my $dbh     = $self->{cxn}->dbh;
   my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $table_name");
   my $fks = get_fks($self, $row->[1]);

   # print Dumper(\$fks);
   # Check if any FK in the new table
   if ((keys %$fks) > 0) {
      # This is used for DEBUG purposes, can be removed
      print ">>>>>> PLUGIN to rename the FK's to the original name executed after drop the old table [after_drop_old_table]\n";
      $executed = 1;
      change_fk($dbh, $fks);
   }
}

sub before_drop_triggers {
   if ($executed == 0) {
      my ($self, %args) = @_;
      my $dbh     = $self->{cxn}->dbh;
      my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $table_name");
      my $fks = get_fks($self, $row->[1]);

      # Check if any FK in the new table
      if ((keys %$fks) > 0) {
         # This is used for DEBUG purposes, can be removed
         print ">>>>>> PLUGIN to rename the FK's to the original name executed after drop the old table [before_drop_triggers]\n";
         $executed = 1;
         change_fk($dbh, $fks);
      }
   }
}

sub change_fk {
   my ($dbh, $fks) = @_;
      # Here we start creating the SQL to rename the FK's
      my $sql_fk = "ALTER TABLE $table_name \n";

      # Variable to control if we need add an extra ","
      my $count = 0;

      # Loop the FK's to create the SQL
      while (my ($key_name, $val) = each (%$fks)) {
         if (exists $OLD_table_fks->{substr($key_name, 1)}) {  
            if ($count++ > 0) {
               $sql_fk .= ", \n";
            }

            $sql_fk = $sql_fk . "  DROP FOREIGN KEY `$key_name`, \n";
            $sql_fk = $sql_fk . "  ADD CONSTRAINT " . substr($key_name, 1) . 
               " FOREIGN KEY ( " . $val->{colnames} . ") " .
               " REFERENCES " . $val->{parent_tblname} . " (" . $val->{parent_colnames} . ") ";
            # print Dumper(\$OLD_table_fks)
         }
      }

      # This will print the SQL to the console used for DEBUG purposes
      print ">>>>>> PLUGIN SQL: \n$sql_fk\n";

      # This line will effectively execute the SQL to rename (DROP and ADD) the FK's
      $dbh->do($sql_fk);
   
}

sub test {
   
}

1;