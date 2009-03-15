#! /usr/bin/perl
use strict;
use warnings;
use Lingua::StopWords;
use Lingua::Stem::Snowball;
use DBI;

my $INDEX_FILE = "/usr/ports/INDEX-5";
my $DB         = "/home/tobez/var/db/port-tags.db";

if (@ARGV && $ARGV[0] eq 'test') {
	$INDEX_FILE = "/usr/ports/INDEX-5";
	$DB         = "/home/tobez/_/port-tags.db";
}

build_tags(
	index               => $INDEX_FILE,
	ignore_pure_numbers => 1,
	minimum_length      => 3,
	minimum_count       => 9,
	db                  => $DB,
);

sub process_index
{
	my %p = @_;

	open my $file, "< $p{index}" or die "cannot open $p{index}: $!\n";
	my $stopwords = Lingua::StopWords::getStopWords('en');
	my $stemmer = Lingua::Stem::Snowball->new(lang => 'en');

	while (<$file>) {
		my ($origin, $comment, $category) = (split /\|/)[1,3,6];
		$origin =~ s|^/usr/ports/||;
		$origin2comment{$origin} = $comment;
		my @words;
		push @words,
			$comment  =~ /\b(\w+)\b/g,
			$category =~ /\b(\w+)\b/g;
		@words = keys %{ {map { lc($_) => 1 } @words} };
		@words = grep { !$stopwords->{$_} } @words;
		my %s;
		for my $word (@words) {
			next if $p{ignore_pure_numbers} && $word =~ /^\d+$/;
			my $stem = $stemmer->stem($word);
			next unless defined $stem;
			$stem = $stem_cor->{$stem} if $stem_cor->{$stem};
			$stem2word{$stem}{$word}++;
			next if $s{$stem}++;
			push @{$stem2port{$stem}}, $origin;
			$stemcount{$stem}++;
		}
	}
}

sub build_tags
{
	my %p = @_;

	process_index(%p);

	my $extra_sw = extra_stop_words();
	my $stem_cor = stem_correspond();
	my %stem2word;
	my %stemcount;
	my %stem2port;
	my %wordcount;
	my %word2port;
	my %origin2comment;
	while (my ($s,$w) = each %stem2word) {
		my $word = (sort { length($a) <=> length($b) } keys %$w)[0];
		next if $extra_sw->{$word};
		$word = $stem_cor->{$word} if $stem_cor->{$word};
		$wordcount{$word} += $stemcount{$s};
		push @{$word2port{$word}}, @{$stem2port{$s}};
	}

	my $db = "$p{db}.new";
	unlink $db;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$db","","",
		{ RaiseError => 1, PrintError => 0, AutoCommit => 1});
	$dbh->do(<<EOF);
create table ports (pid integer primary key, origin text, comment text)
EOF
	$dbh->do(<<EOF);
create table tags (tid integer primary key, tag text, count integer)
EOF
	$dbh->do(<<EOF);
create table pt (tag_id integer, port_id integer)
EOF
	$dbh->do(<<EOF);
create index tags_tag on tags (tag)
EOF
	$dbh->do(<<EOF);
create index pt_tag_id on pt (tag_id)
EOF
	$dbh->do(<<EOF);
create index pt_port_id on pt (port_id)
EOF
	$dbh->do(<<EOF);
create index ports_origin on ports (origin)
EOF

#print "populate ports table\n";
	# populate ports table
	my %origin2pid;
	$dbh->begin_work;
	while (my ($o, $c) = each %origin2comment) {
		$dbh->do("insert into ports (origin, comment) values (?, ?)",
			{}, $o, $c);
		$origin2pid{$o} = $dbh->func("last_insert_rowid");
	}
	$dbh->commit;

	$dbh->begin_work;
	for my $w (sort keys %wordcount) {
		if ($p{minimum_length} > length $w) {
			next unless $stem_cor->{$w};
		}
		next if $wordcount{$w} <= $p{minimum_count};
#print "$w\n";
		$dbh->do("insert into tags (tag, count) values (?, ?)",
			{}, $w, $wordcount{$w});
		my $tid = $dbh->func("last_insert_rowid");
		my $origins = $word2port{$w};
		for my $o (@$origins) {
			$dbh->do("insert into pt (tag_id, port_id) values (?, ?)",
				{}, $tid, $origin2pid{$o});
		}
	}
	$dbh->commit;
	$dbh->disconnect;
	rename $db, $p{db};
}

sub extra_stop_words
{
	# canna ?
	my @sw = qw(across aka allow another
				anti applicative arbitrary around
				attach authentic available aware
				better built can capable
				clean combine common composite
				comprehensive contains create custom
				deal decorated default define
				definitive derived determine dimensional
				driven drop dynamic easier
				easily easy effect efficient
				enable enhance equivalent etc
				example except execute explore
				explorin extend extensive external
				extremely facility fast feature
				fix flavor flexible fly
				forward free freebsd friendly
				fsf full fully function
				general get given gnu
				gpl guest hackin half
				handle handler help high
				highlight highly home host
				identify iii implement improve
				include independent inspired install
				instant integrate intended interact
				interprets intrusive just keep
				kind kit known large
				layer learn level life
				light lightweight like limit
				line lite little long
				look low made maintain
				maintenance major male manipulate
				many minimal model modern
				modifed modify modular module
				multiple native need new
				next nice non numeral
				old one optimal option
				oriented output per perform
				popular port precise present
				pretty produce product project
				provide public pure purpose
				quality query quick read
				real receive record refer
				regular related release reliable
				represent representation require revised
				rewrite robust run safe
				sample save send separate
				serve set several share
				show side similar simple
				simplify single small smart
				software solution source special
				specific stable standalone standard
				store summary support technical
				test three tool tradition
				two type update usage
				use user valid variable
				various verify version via
				view way well wide
				within without wonderful word
				work wrap write written yet);
	my %sw = map { $_ => 1 } @sw;
	return \%sw;
}

sub stem_correspond
{
	my %sc = (
		guy => "gui",
		cryptograph => "crypto",
		detector => "detect",
		develop => "devel",
		differ => "diff",
		dockable => "dock",
		dockapp => "dock",
		editor => "edit",
		emacs20 => "emacs",
		emacs21 => "emacs",
		emacsen => "emacs",
		embedded => "embed",
		enlightened => "enlightenment",
		extractor => "extract",
		filename => "file",
		front => "frontend",
		gkrellm2 => "gkrellm",
		gnome2 => "gnome",
		graphic => "graph",
		gtk2 => "gtk",
		iconset => "icon",
		information => "info",
		japan => "japanese",
		kde3 => "kde",
		language => "lang",
		launcher => "launch",
		lib => "library",
		logfile => "log",
		maker => "make",
		messenger => "message",
		mgmt => "management",
		manage => "management",
		mixer => "mix",
		network => "net",
		parser => "parse",
		perl5 => "perl",
		pop3 => "pop",
		programm => "program",
		xfce4 => "xfce",
		xemacs => "emacs",
		xemacs21 => "emacs",
		scientific => "science",
		tcl83 => "tcl",
		tcl84 => "tcl",
		tk80 => "tk",
		tk82 => "tk",
		tk83 => "tk",
		tk84 => "tk",
		tk   => "tk",
		wnn6 => "wnn",
		wnn7 => "wnn",
		emule => "emulator",
	);
	return \%sc;
}

__END__

The hypothesis is that comment field can sort of naturally yield tags
information.  If this experiment proves useful, we can convert to using
real tags.
