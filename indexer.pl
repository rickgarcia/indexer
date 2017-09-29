#!/usr/local/bin/perl
use strict;
use warnings;

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

	# setup the db file for the indexer
	my $sqlite_init = {
		'1create' => '
			CREATE TABLE words (
    				w_idx integer PRIMARY KEY AUTOINCREMENT,
    				word text NOT NULL UNIQUE,
    				count integer DEFAULT 0
			)',
		'2w_index' => 'CREATE UNIQUE INDEX word_idx ON words(word)',
		'3c_index' => 'CREATE INDEX count_idx ON words(count)',
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
sub get_dbh_locked
{
	my ($dbfile) = @_;

	my $timeout = 60;
	my $dbh = undef;

	while (!defined($dbh)) {
		$dbh = DBI->connect(
			"dbi:SQLite:dbname=$dbfile", undef, undef, {
				sqlite_open_flags => SQLITE_OPEN_READWRITE
			});
		if (!defined($dbh)) { 
			print "failed to open\n";
			sleep (1); 
		}
		if ($timeout-- <= 0) {
			last;
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

	foreach my $word (keys %$dictionary) {
		my $u_rc = $u_sth->execute($dictionary->{$word}, $word);

		#print "$word ($dictionary->{$word}): $u_rc\n";
		if ($u_rc == 0) {
			my $i_rc = $i_sth->execute($word, $dictionary->{$word});
		}
	}
	$u_sth->finish();
	$i_sth->finish();
	return;
}

# update the file table
sub update_file_entry
{
	my ($dbh, $file) = @_;

	my $f_rc = $dbh->do("INSERT INTO files(file) VALUES('$file')");
	if ($f_rc == 0) {
		print STDERR "Failed to update '$file' entry ($f_rc)\n";
	}
	return;
}



print STDERR "initializing db\n";
my ($dbfile) = init_db();
if (!defined($dbfile)) {
	die "error creating temporary index db";
}


#run through the files and fork for each one
my @files = @ARGV;

foreach my $file (@files) {

	my $child_pid = fork();
	if ($child_pid) {

	} else {

		my $fh = undef;
		if (!open($fh, '<', $file)) {
			print STDERR "error opening $file\n";
			next;
		}
		my $dict = parse_file($fh);
		print STDERR "'$file' parsing complete\n";

		my $dbh = get_dbh_locked($dbfile); 
		update_dictionary($dbh, $dict);
		update_file_entry($dbh, $file);
		$dbh->disconnect();
		print STDERR "'$file' index complete\n";
		exit;
	}
}


# now wait for all the kids to finish and print the output


my $dbh = DBI->connect(
	"dbi:SQLite:dbname=$dbfile", undef, undef, {
		sqlite_open_flags => SQLITE_OPEN_READONLY
	});
if (!defined($dbh)) { die "Could not read from temporary db\n"; }
my $status_sth = $dbh->prepare('SELECT count(file) AS fcount FROM files');
my $count_sth = $dbh->prepare(
	'SELECT count,word FROM words ORDER BY count DESC LIMIT 10');

if (!defined($status_sth) || !defined($count_sth)) {
	die $dbh->errstr;
}

my $file_count = $#files + 1;
print "Counting $file_count files\n";
my $timeout = 60;
my $start_time = time();
my $latest_count;
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

if ($latest_count != $file_count) {
	print "Warning: timeout indexing all files\n";
} else {
	print "All files indexed\n";
}

if (!($count_sth->execute())) {
	# This should be limited to either db errors or pathological cases
	# where the number of distinct words indexed is less than 10
	print STDERR "Warning: error returning word counts\n";
}

my $top_words = $count_sth->fetchall_arrayref();

foreach my $wordcount (@$top_words) {
	my ($count, $word) = @$wordcount;
	printf("%32s : %8d\n", $word, $count);
}


`rm -f $dbfile`;
