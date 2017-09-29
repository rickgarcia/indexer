#!/usr/local/bin/perl
use strict;
use warnings;

use DBI;
use DBD::SQLite;
use Data::Dumper;

print Dumper(@ARGV);

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

			if (!defined($full_dictionary->{$entry})) {
				$full_dictionary->{$entry} = 1;
			} else {
				$full_dictionary->{$entry}++;
			}
		}
	}
	return $full_dictionary;
}



# merges the word counts of two dictionaries; currently creates a new
# dictionary, rather than updating one in place. 
sub merge_dictionary_counts 
{
	my ($dict_a, $dict_b) = @_;

	my $new_dictionary = {};

	foreach my $word (keys %$dict_a) {
		$new_dictionary->{$word} = $dict_a->{$word} +
			defined($dict_b->{$word}) ? $dict_b->{$word} : 0;

		delete($dict_b->{$word});
	}
	foreach my $word (keys %$dict_b) {
		$new_dictionary->{$word} = $dict_b->{$word};
	}
	return $new_dictionary;
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
				index_time DATETIME DEFAULT CURRENT_TIMESTAMP
			)',
		'5f_index' => 'CREATE INDEX file_idx ON files(file)',
		'6t_index' => 'CREATE INDEX time_idx ON files(index_time)',
	};
	foreach my $sth (sort keys %$sqlite_init) {
		my $rc = $dbh->do($sqlite_init->{$sth});
		print "$sth: $rc\n";
	}

	return ($dbh, $dbfile);
}


# add dictionary to db file
# - updates the db with the specified dictionary; the database handle must be
# active and the db unlocked
sub update_dictionary
{
	my ($dbh, $dictionary) = @_;

#	my $u_sth = $dbh->prepare(
#		'UPDATE words SET count=count+? WHERE word=?');
#	my $i_sth = $dbh->prepare(
#		'INSERT INTO words(word, count) VALUES (?,?)');
#
#	if (!defined($u_sth) || !defined($i_sth)) {
#		die "$dbh->errstr\n";
#	}
#	print "done preparing statement\n";
#
#	foreach my $word (keys %$dictionary) {
#		my $u_rc = $u_sth->execute($dictionary->{$word}, $word);
#
#		print "$word ($dictionary->{$word}): $u_rc\n";
#		if ($u_rc == 0) {
#			print "No row updated - inserting\n";
#			my $i_rc = $i_sth->execute($word, $dictionary->{$word});
#		}
#	}
#	$u_sth->finish();
#	$i_sth->finish();
	return;
}



print STDERR "initializing db\n";
my ($dbh, $dbfile) = init_db();
if (!defined($dbh) || !defined($dbfile)) {
	die "error creating temporary index db";
}

my @files = @ARGV;

foreach my $file (@files) {
	my $fh = undef;
	if (!open($fh, '<', $file)) {
		print STDERR "error opening $file\n";
		next;
	}
	my $dict = parse_file($fh);
	print "$file parsed...\n";

	update_dictionary($dbh, $dict);
	#print Dumper($dict);
exit;
}

