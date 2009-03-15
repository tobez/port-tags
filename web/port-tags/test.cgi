#! /usr/bin/perl
use strict;
use warnings;
use DBI;
use Template;
use CGI qw(:cgi);

my $pi = path_info();  $pi =~ s|/||g;
my @allcur = split /\+/, $pi;
my @cur = grep { /^\w/ } @allcur;
my @nocur = map { /(\w+)/, $1||$_ } grep { /^\W/ } @allcur;
my $lim = 10;
my $offset = param("o") || 0;
my $mode = param("m") || "web";
if ($mode eq "pl") {
	# portlist
	$lim = param("n") || 200;
}

my %PROCESS = (
	web => \&process_web,
	pl  => \&process_portlist,
);

my %cur = map { $_ => 1 } @cur;
my $db = "/home/tobez/var/db/port-tags.db";
my $dbh = DBI->connect("dbi:SQLite:dbname=$db","","",
	{ RaiseError => 1, PrintError => 0, AutoCommit => 1});

use Template::Stash;

$Template::Stash::LIST_OPS->{except} = sub {
	my ($list,$except) = @_;
	return [ grep { $_ ne $except } @$list ];
};

if ($PROCESS{$mode}) {
	$PROCESS{$mode}->();
} else {
	print header("text/plain");
	print "E(unknown mode)\n";
}

sub process_portlist
{
	print header("text/plain");
	my ($ports, $n_ports) = get_ports();
	if (@$ports < $n_ports) {
		print "E(too many)[$n_ports]\n";
	} else {
		for my $p (@$ports) {
			print "$p->{origin}\n";
		}
	}
}

sub process_web
{
	print header();

	# get all tags
	my $tags = [];
	my $r = $dbh->selectall_arrayref("select tag,count from tags");
	my %tags;
	for (@$r) {
		push @$tags, { tag => $_->[0], count => $_->[1] };
		$tags{$_->[0]} = $_->[1];
	}

	# get related tags
	my $related = [];
	my %related;
	if (@cur) {
		my $sql = "select distinct tag from pt,tags where ";
		$sql = $sql . join " and ",
			map { "port_id in (select pid from tags,pt,ports where " .
				  "tag=? and tid=tag_id and port_id=pid)" } @cur;
		$sql = "$sql and tid=tag_id order by tag";
		my $r = $dbh->selectall_arrayref($sql, {}, @cur);
		for (@$r) {
			next if $cur{$_->[0]};
			push @$related, { tag => $_->[0], count => $tags{$_->[0]} };
			$related{$_->[0]}++;
		}
	}

	my ($ports, $n_ports) = get_ports(with_tags => 1);

	my $test = $0 =~ /test.cgi/;
	my $vars = {
		base       => ($test ? '/port-tags/test.cgi' : '/port-tags/index.cgi'),
		test       => $test,
		title      => 'Port tags',
		hcur       => {map {$_=>1} @cur},
		related    => $related,
		hrelated   => \%related,
		tags       => $tags,
		ports      => $ports,
		n_ports    => $n_ports,
		limit      => $lim,
		offset     => $offset,
	};


	my $t = Template->new({PRE_CHOMP=>1, POST_CHOMP=>1});
	my $o;
	$t->process("port-tags.tmpl", $vars, \$o) or print STDERR $t->error, "\n";
	print "$o\n";
}

sub get_ports
{
	my (%p) = @_;
	my $ports = [];
	my $n_ports;
	my $r;
	if (@cur) {
		my $rest_sql = "select distinct port_id from pt,tags where ";
		$rest_sql .= join " and ",
			(map { "port_id in (select pid from tags,pt,ports where " .
				"tag=? and tid=tag_id and port_id = pid)" } @cur),
			(map { "port_id not in (select pid from tags,pt,ports where " .
				"tag=? and tid=tag_id and port_id = pid)" } @nocur);
		$rest_sql .= " and tid=tag_id";

		my $some_sql = "select distinct origin,comment,port_id from pt,ports " .
			"where port_id in ($rest_sql) and port_id = pid";

		# XXX could be done better
		$r = $dbh->selectall_arrayref("$rest_sql", {}, @cur, @nocur);
		$n_ports = @$r;

		$r = $dbh->selectall_arrayref("$some_sql order by origin limit $lim offset $offset", {}, @cur, @nocur);
	} else {
		($n_ports) = $dbh->selectrow_array("select count(origin) from ports");
		$r = $dbh->selectall_arrayref("select origin,comment,pid from ports" .
			" order by origin limit $lim offset $offset");
	}
	my @pid;
	my %pid;
	for (@$r) {
		$_->[0] =~ m|^(.*?)/(.*)$|;
		push @pid, $_->[2];
		push @$ports, {
			origin   => $_->[0],
			comment  => $_->[1],
			name     => $2,
			category => $1,
		};
		$pid{$_->[2]} = $ports->[-1];
	}
	if ($p{with_tags}) {
		$r = $dbh->selectall_arrayref(
			"select port_id,tag from pt,tags where ".
			"port_id in (" . join(",", @pid) . ") ".
			"and tag_id = tid");
		for (@$r) {
			push @{$pid{$_->[0]}->{tags}}, $_->[1];
		}
	}
	return ($ports, $n_ports);
}

$dbh->disconnect;
