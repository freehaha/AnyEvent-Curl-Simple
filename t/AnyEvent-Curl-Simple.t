# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl AnyEvent-Curl-Simple.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 3;
BEGIN {
	use_ok('AnyEvent::Curl::Simple')
};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

# These are simple tests to make sure the api did return correct code

use AnyEvent;
# Test 2:
my $cv = AE::cv;

my $curl = AnyEvent::Curl::Simple->new;
$cv->begin;
$curl->get('http://www.cpan.org', {}, sub {
		my ($code, $body) = @_;
		ok ($code == 200, 'get');
		$cv->end;
	});

#Test 3:
$cv->begin;
$curl->post('http://www.cpan.org', {}, sub {
		my ($code, $body) = @_;
		ok ($code == 200, 'post');
		$cv->end;
	});

$cv->recv;
