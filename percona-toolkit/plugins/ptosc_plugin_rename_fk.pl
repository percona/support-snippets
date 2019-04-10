package pt_online_schema_change_plugin;

use strict;

my $table_name;
my $table_fks = {};

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
      $table_fks->{"$key"} = {ddl => $val->{'ddl'}};
   }
}

sub after_drop_old_table {
   # This is used for DEBUG purposes, can be removed
   print ">>>>>> PLUGIN to rename the FK's to the original name executed after drop the old table\n";

   my ($self, %args) = @_;
   my $dbh     = $self->{cxn}->dbh;
   my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $table_name");
   my $fks = get_fks($self, $row->[1]);

   # Here we start creating the SQL to rename the FK's
   my $sql_fk = "ALTER TABLE $table_name \n";

   # Variable to control if we need add an extra ","
   my $count = 0;

   # Loop the FK's to create the SQL
   while (my ($key_name, $val) = each (%$fks)) {
      if ($count++ > 0) {
         $sql_fk .= ", \n";
      }

      $sql_fk = $sql_fk . "  DROP FOREIGN KEY `$key_name`, \n";
      $sql_fk = $sql_fk . "  ADD " . $table_fks->{substr($key_name, 1)}{ddl};
   }

   # This will print the SQL to the console used for DEBUG purposes
   print ">>>>>> PLUGIN SQL: \n$sql_fk\n";

   # This line will effectively execute the SQL to rename (DROP and ADD) the FK's
   $dbh->do($sql_fk);
}

1;