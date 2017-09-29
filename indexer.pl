#!/usr/local/bin/perl
use strict;
use warnings;

use Getopt::Std;
use DBI;
use DBD::SQLite;
use DBD::SQLite::Constants qw/:file_open/;
use Data::Dumper;


# takes in an open file pointer and reads text in until the end of the file;
# it returns the word count for each word in an associative hash
sub parse_file
{
	my ($f_obj) = @_;
	my $full_dictionary = {}; # counts of all the words from this file

	while (<$f_obj>) {
		my @tokens = split(/[^a-zA-Z0-9]+/, $_);
		foreach my $token (@tokens) {
			my $entry = uc $token;
			# filter out empty tokens
			if ($token eq '') { next; }

			if (!defined($full_dictionary->{$entry})) {
				$full_dictionary->{$entry} = 1;
			} else {
				$full_dictionary->{$entry}++;
			}
		}
	}
	return $full_dictionary;
}


# initialize a local sqlite db file and return the file name
#
sub init_db
{
	my $dbfile = time().'.db';
	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', ''); 

	if (!defined($dbh)) { 
		die "unable to create temporary db file";
	}

	# note: the c_index seems handy, but it slows down insert/update
	# considerably - it's also only used for one query at the end; no
	# point in repeatedly calculating it

	# setup the db file for the indexer
	my $sqlite_init = {
		'1create' => '
			CREATE TABLE words (
    				w_idx integer PRIMARY KEY AUTOINCREMENT,
    				word text NOT NULL UNIQUE,
    				count integer DEFAULT 0
			)',
		'2w_index' => 'CREATE UNIQUE INDEX word_idx ON words(word)',
#		'3c_index' => 'CREATE INDEX count_idx ON words(count)',
		'4create' => '
			CREATE TABLE files (
				f_idx integer PRIMARY KEY AUTOINCREMENT,
				file text NOT NULL UNIQUE,
				index_time DATETIME DEFAULT (DATETIME(\'now\')) 
			)',
		'5f_index' => 'CREATE INDEX file_idx ON files(file)',
		'6t_index' => 'CREATE INDEX time_idx ON files(index_time)',
	};
	foreach my $sth (sort keys %$sqlite_init) {
		my $rc = $dbh->do($sqlite_init->{$sth});
	}
	$dbh->disconnect();

	return ($dbfile);
}


# For each child process, we need to get a locked db handle - so this
# function attempts to open up the db until we get it unlocked
#TODO: set a timeout
sub get_dbh_readwrite
{
	my ($dbfile) = @_;

	my $timeout = 60;
	my $dbh = undef;

	while (!defined($dbh) && ($timeout > 0)) {
		$dbh = DBI->connect(
			"dbi:SQLite:dbname=$dbfile", undef, undef, {
				sqlite_open_flags => SQLITE_OPEN_READWRITE,
				RaiseError => 1,
			});
		if (!defined($dbh)) { 
			print "failed to open\n";
			$timeout--;
			sleep (1);
		}
	}
	return $dbh;
}


# add dictionary to db file
# - updates the db with the specified dictionary; the database handle must be
# active and the db unlocked
sub update_dictionary
{
	my ($dbh, $dictionary) = @_;

	my $u_sth = $dbh->prepare(
		'UPDATE words SET count=count+? WHERE word=?');
	my $i_sth = $dbh->prepare(
		'INSERT INTO words(word, count) VALUES (?,?)');

	if (!defined($u_sth) || !defined($i_sth)) {
		die "$dbh->errstr\n";
	}

	# enforce transactions to keep the processes from interfering with
	# each other's counts
	$dbh->do('BEGIN TRANSACTION');
	foreach my $word (keys %$dictionary) {
		# run the update query first - if nothing happens...
		my $u_rc = $u_sth->execute($dictionary->{$word}, $word);
		# ...then run the insert query
		if ($u_rc == 0) {
			my $i_rc = $i_sth->execute($word, $dictionary->{$word});
		}
	}
	$dbh->do('END TRANSACTION');
	$u_sth->finish();
	$i_sth->finish();
	return;
}

# update the file table
sub update_file_entry
{
	my ($dbh, $file) = @_;

	$dbh->do('BEGIN TRANSACTION');
	my $f_rc = $dbh->do("INSERT INTO files(file) VALUES('$file')");
	if ($f_rc == 0) {
		print STDERR "Failed to update '$file' entry ($f_rc)\n";
	}
	$dbh->do('END TRANSACTION');
	return;
}


# parent of indexers
sub index_manager
{
	my ($config) = @_;
	my $dbfile = $config->{'dbfile'};
	my @files = @{$config->{'files'}};
	my @children = @{$config->{'children'}};
	my $timeout = $config->{'timeout'};

	# Parent DB setup - read only as we wait for children to finish
	# reporting in
	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$dbfile", undef, undef, {
			sqlite_open_flags => SQLITE_OPEN_READONLY
		});
	if (!defined($dbh)) { die "Could not read from temporary db\n"; }
	my $status_sth = $dbh->prepare(
		'SELECT count(file) AS fcount FROM files');
	my $count_sth = $dbh->prepare(
		'SELECT count,word FROM words ORDER BY count DESC LIMIT 10');
	if (!defined($status_sth) || !defined($count_sth)) {
		die $dbh->errstr;
	}
	
	my $file_count = $#files + 1;
	my $start_time = time();
	my $latest_count;
	# Basic wait loop - count the number of kids reporting in, and wait
	# for the count to reach the expecting tally, or timeout to occur
	PARENT_WAIT: while (($timeout + $start_time) > time()) {
	
		my $fc_rc = $status_sth->execute();
		my $h_count = $status_sth->fetchrow_hashref();
		if (!defined($h_count)) { next; }
	
		$latest_count = $h_count->{'fcount'};
		if ($latest_count == $file_count) {
			last PARENT_WAIT;
		}
	}
	$status_sth->finish();

	# TODO: move this out of this function
	# if timeout occured, do process cleanup	
	if ($latest_count != $file_count) {
		print STDERR "Warning: timeout indexing all files\n";

		my $fdone_sth = $dbh->prepare('SELECT file FROM files');
		my $fd_rc = $fdone_sth->execute();
		my $files = $fdone_sth->fetchall_hashref('file');

		# remove all the successfully indexed files from the child
		# process array
		foreach my $file (keys %$files) {
			foreach my $c_process (@children) {
				if ($c_process->{'file'} eq $file) {
					$c_process->{'pid'} = -1;
				}
			}
		}
		# kill any remaining child processes
		foreach my $c_process (@children) {
			if ($c_process->{'pid'} == -1) { next; }
			my $k_rc = `kill $c_process->{'pid'}`;
			print STDERR "Killed indexing of ".
				"$c_process->{'file'} ($c_process->{'pid'})\n";
		}
		$fdone_sth->finish();
	} else {
		print STDERR "Full indexing complete\n";
	}

	# Process cleanup is done; let's get the final tallies
	if (!($count_sth->execute())) {
		# This should be limited to db errors or pathological cases
		# where the number of distinct words indexed is less than 10
		print STDERR "Warning: error returning word counts\n";
	}
	# grab the top 10 entries
	my $top_words = $count_sth->fetchall_arrayref();
	$count_sth->finish();
	
	foreach my $wordcount (@$top_words) {
		my ($count, $word) = @$wordcount;
		printf("%32s : %8d\n", $word, $count);
	}

	# close the db connection, and remove the temporary file
	$dbh->disconnect();
	`rm -f $dbfile*`;
	return;
}


sub index_single_file
{
	my ($dbfile, $parsefile) = @_;

	my $fh = undef;
	if (!open($fh, '<', $parsefile)) {
		print STDERR "error opening $parsefile\n";
		next;
	}
	my $dict = parse_file($fh);
	close($fh);

	print STDERR "'$parsefile' parsing complete\n";

	my $dbh = get_dbh_readwrite($dbfile); 
	update_dictionary($dbh, $dict);
	update_file_entry($dbh, $parsefile);
	$dbh->disconnect();
	print STDERR "'$parsefile' index complete\n";
	return;
}

sub usage
{
	print "
usage: indexer.pl [-htwp] files
	-h : help
	-t : timeout in seconds
	-w : number of workers [not implemented]
	-b : blob mode - index from standard input\n\n";
	exit 0;
}

### Main section

my @children = ();
my @files = ();
my $config = {
	'timeout' => 60,
	'files' => \@files,
	'children' => \@children
};

# process all cmdline options

my %options;
getopts("ht:w:b", \%options) || usage();


if (defined($options{'h'})) {
	usage();
}

if (defined($options{'t'})) {
	$config->{'timeout'} = $options{'t'};
	if ($config->{'timeout'} =~ /\D/) {
		print STDERR "invalid timeout specified\n";
		exit -1;
	}
}

# by default, we index all files on the command line
if (!defined($options{'b'})) {
	@files = @ARGV;
}


# option setup is finished; initialize the index db and start indexing
my ($dbfile) = init_db();
if (!defined($dbfile)) {
	die "error creating temporary index db";
}
$config->{'dbfile'} = $dbfile;

# raw parser - read from stdin and parse
if ($#files < 0) {
	my $fh = \*STDIN;
	my $dict = parse_file($fh);
	my $dbh = get_dbh_readwrite($dbfile); 
	update_dictionary($dbh, $dict);
	update_file_entry($dbh, 'stdin');
	push(@files, 'stdin'); # to keep index_manager happy
	$dbh->disconnect();
} else {
	# TODO: this section needs to be completely reworked if # of workers
	# is to be limited - process acccounting is currently handled in the 
	# index_manager function - needs to be moved out

	# launch processes for all files
	foreach my $file (@files) {
	
		my $child_pid = fork();
		if ($child_pid) {
			# save the child pid/file info for process accounting
			push(@children, 
				{'pid' => $child_pid, 'file' => $file });
		} else {
			index_single_file($dbfile, $file);
			exit;
		}
	}
}

index_manager($config);
exit;

