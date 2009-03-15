#! /usr/bin/perl
use warnings;
use strict;
use DBI;

my $DB   = "/home/tobez/var/db/port-tags.db";
my $TAGS = "/home/tobez/bsd2.be/port-tags/TAGS";

my $dbh = DBI->connect("dbi:SQLite:dbname=$DB","","",
	{ RaiseError => 1, PrintError => 0, AutoCommit => 1});
my $r = $dbh->selectall_arrayref(
	"select tag,origin from tags,pt,ports where ".
	"tid=tag_id and pid=port_id order by tag,origin");
open TAGS, ">$TAGS.new" or die $!;
for (@$r) {
	$_->[1] =~ m|^(.*?)/(.*)$|;
	print TAGS "$_->[0]|$1|$2\n";
}
close TAGS;
rename "$TAGS.new", $TAGS;
unlink "$TAGS.bz2";
system("/usr/bin/bzip2 -9 $TAGS");
$dbh->disconnect;
