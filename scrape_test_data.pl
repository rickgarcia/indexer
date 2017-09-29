#!/usr/local/bin/perl
# Quick script to pull book texts from Project Gutenberg; scraped from top
# 100 book as listed at:
# https://www.gutenberg.org/browse/scores/top
#
# usage: perl scrape_test_data.pl
# - will create the directory test_data if it doesn't already exist
#

use strict;
use warnings;

my $root_url = 'https://www.gutenberg.org';
my $books = {
	'1342' => 'Pride and Prejudice by Jane Austen',
	'11' => 'Alices Adventures in Wonderland by Lewis Carroll',
	'84' => 'Frankenstein; Or, The Modern Prometheus by Mary Wollstonecraft Shelley',
	'1952' => 'The Yellow Wallpaper by Charlotte Perkins Gilman',
	'1661' => 'The Adventures of Sherlock Holmes by Arthur Conan Doyle',
	'345' => 'Dracula by Bram Stoker',
	'98' => 'A Tale of Two Cities by Charles Dickens',
	'16328' => 'Beowulf: An Anglo-Saxon Epic Poem',
	'2542' => 'Et dukkehjem. English by Henrik Ibsen',
	'5200' => 'Metamorphosis by Franz Kafka',
	'1232' => 'Il Principe. English by Niccolò Machiavelli',
	'2591' => 'Grimms Fairy Tales by Jacob Grimm and Wilhelm Grimm',
	'851' => 'Narrative of the Captivity and Restoration of Mrs. Mary Rowlandson by Mary White Rowlandson',
	'76' => 'Adventures of Huckleberry Finn by Mark Twain',
	'3207' => 'Leviathan by Thomas Hobbes',
	'74' => 'The Adventures of Tom Sawyer by Mark Twain',
	'6130' => 'The Iliad by Homer',
	'844' => 'The Importance of Being Earnest: A Trivial Comedy for Serious People by Oscar Wilde',
	'2600' => 'War and Peace by graf Leo Tolstoy',
	'2701' => 'Moby Dick; Or, The Whale by Herman Melville',
	'16' => 'Peter Pan by J. M.  Barrie',
	'20203' => 'Autobiography of Benjamin Franklin by Benjamin Franklin',
	'4300' => 'Ulysses by James Joyce',
	'30254' => 'The Romance of Lust: A Classic Victorian erotic novel by Anonymous',
	'55553' => 'The Last Frontier by E. Alexander  Powell',
	'55628' => 'Dealings with the Inquisition by Giacinto Achilli',
	'55635' => 'Goose-Quill Papers by Louise Imogen Guiney',
	'27827' => 'The Kama Sutra of Vatsyayana by Vatsyayana',
	'100' => 'The Complete Works of William Shakespeare by William Shakespeare',
	'1400' => 'Great Expectations by Charles Dickens',
	'55630' => 'History of Chemistry, Volume I',
	'174' => 'The Picture of Dorian Gray by Oscar Wilde',
	'55636' => 'Orloff and his Wife by Maxime Gorky and Isabel Florence Hapgood',
	'147' => 'Common Sense by Thomas Paine',
	'23' => 'Narrative of the Life of Frederick Douglass, an American Slave by Frederick Douglass',
	'1260' => 'Jane Eyre: An Autobiography by Charlotte Brontë',
	'41' => 'The Legend of Sleepy Hollow by Washington Irving',
	'2500' => 'Siddhartha by Hermann Hesse',
	'16643' => 'Essays by Ralph Waldo Emerson by Ralph Waldo Emerson',
	'160' => 'The Awakening, and Selected Short Stories by Kate Chopin',
	'35' => 'The Time Machine by H. G.  Wells',
	'1404' => 'The Federalist Papers by Alexander Hamilton and John Jay and James Madison',
	'42' => 'The Strange Case of Dr. Jekyll and Mr. Hyde by Robert Louis Stevenson',
	'1497' => 'The Republic by Plato',
	'55634' => 'Tutti Frutti, Erster Band',
	'2814' => 'Dubliners by James Joyce',
	'1080' => 'A Modest Proposal by Jonathan Swift',
	'55637' => 'Les aventures de Télémaque by Louis Aragon',
	'55626' => 'Science in Short Chapters by W. Mattieu Williams',
	'2554' => 'Prestuplenie i nakazanie. English by Fyodor Dostoyevsky',
	'55629' => 'Historical record of the Sixth by Richard Cannon',
	'15399' => 'The Interesting Narrative of the Life of Olaudah Equiano, Or Gustavus Vassa, The African by Equiano',
	'768' => 'Wuthering Heights by Emily Bronte', 
	'55627' => 'Emmeline by Elsie Singmaster',
	'158' => 'Emma by Jane Austen',
	'55631' => 'History of Chemistry, Volume II',
	'244' => 'A Study in Scarlet by Arthur Conan Doyle',
	'1184' => 'The Count of Monte Cristo, Illustrated by Alexandre Dumas',
	'219' => 'Heart of Darkness by Joseph Conrad',
	'33' => 'The Scarlet Letter by Nathaniel Hawthorne',
	'135' => 'Les Misérables by Victor Hugo',
	'3600' => 'Essays of Michel de Montaigne Complete by Michel de Montaigne',
	'55633' => 'Eine Reise nach Freiland by Theodor Hertzka',
	'55624' => 'The Young Train Dispatcher by Burton Egbert Stevenson',
	'7370' => 'Second Treatise of Government by John Locke',
	'46' => 'A Christmas Carol in Prose; Being a Ghost Story of Christmas by Charles Dickens',
	'120' => 'Treasure Island by Robert Louis Stevenson',
	'30360' => 'My Secret Life, Volumes I. to III. by Anonymous',
	'829' => 'Gullivers Travels into Several Remote Nations of the World by Jonathan Swift',
	'205' => 'Walden, and On The Duty Of Civil Disobedience by Henry David Thoreau',
	'28054' => 'The Brothers Karamazov by Fyodor Dostoyevsky',
	'1112' => 'The Tragedy of Romeo and Juliet by William Shakespeare',
	'55' => 'The Wonderful Wizard of Oz by L. Frank  Baum',
	'408' => 'The Souls of Black Folk by W. E. B.  Du Bois',
	'209' => 'The Turn of the Screw by Henry James',
	'236' => 'The Jungle Book by Rudyard Kipling',
	'161' => 'Sense and Sensibility by Jane Austen',
	'2852' => 'The Hound of the Baskervilles by Arthur Conan Doyle',
	'36' => 'The War of the Worlds by H. G.  Wells',
	'1934' => 'Songs of Innocence, and Songs of Experience by William Blake',
	'521' => 'The Life and Adventures of Robinson Crusoe by Daniel Defoe',
	'2148' => 'The Works of Edgar Allan Poe Volume 2 by Edgar Allan Poe',
	'21279' => '2 B R 0 2 B by Kurt Vonnegut',
	'34901' => 'On Liberty by John Stuart Mill',
	'779' => 'The Tragical History of Doctor Faustus by Christopher Marlowe',
	'863' => 'The Mysterious Affair at Styles by Agatha Christie',
	'2147' => 'The Works of Edgar Allan Poe Volume 1 by Edgar Allan Poe',
	'61' => 'Manifest der Kommunistischen Partei. English by Friedrich Engels and Karl Marx',
	'33283' => 'Calculus Made Easy by Silvanus P.  Thompson',
	'1322' => 'Leaves of Grass by Walt Whitman',
	'996' => 'Don Quixote by Miguel de Cervantes Saavedra',
	'10' => 'The King James Version of the Bible',
	'55642' => 'The Sacred Herb by Fergus Hume',
	'1399' => 'Anna Karenina by graf Leo Tolstoy',
	'45' => 'Anne of Green Gables by L. M.  Montgomery',
	'3825' => 'Pygmalion by Bernard Shaw',
	'600' => 'Notes from the Underground by Fyodor Dostoyevsky',
	'1727' => 'The Odyssey by Homer',
	'14264' => 'The Practice and Science of Drawing by Harold Speed',
	'512' => 'Mosses from an Old Manse, and Other Stories by Nathaniel Hawthorne'
};

if (!(-e 'test_data' && -d 'test_data')) {
	mkdir 'test_data';
}

foreach my $book_id (keys %$books) {

	# sanitize the file name to get rid of any accented or control chars
	my $filename = $books->{$book_id};
	$filename =~ s/[^a-zA-Z\s]//g;
	$filename = "test_data/'$filename'";

	# The gutenberg book locations appear to follow one of two name 
	# formats, along with a few redirects. So, try both, along with 
	# instructing curl to follow redirection
	my $book_url = $root_url.'/files/'.$book_id.'/'.$book_id.'-0.txt';
	`curl -f -s -L -o $filename $book_url`;

	if ($?) {
		$book_url = $root_url.'/ebooks/'.$book_id.'.txt.utf-8';
		`curl -f -s -L -o $filename $book_url`;
	}
	if ($?) {
		print "error requesting $books->{$book_id}\n";
	}
}


