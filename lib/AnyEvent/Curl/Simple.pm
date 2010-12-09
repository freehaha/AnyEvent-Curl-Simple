package AnyEvent::Curl::Simple;

use 5.010001;
use AnyEvent;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use URI::Escape;
use Carp;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use AnyEvent::Curl::Simple ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';


# Preloaded methods go here.

sub header {
	my $self = shift;
	$self->{__header} = shift;
}

sub new {
	my $class = shift;
	my $self = {
		__reqid => 1,
		__curlm => WWW::Curl::Multi->new,
		__requests => {},
		__active => 0,
		__header => 0,
		cookie => undef,
		@_,
	};

	bless $self, $class;
}

sub genid {
	$_[0]->{__reqid} = 1 if $_[0]->{__reqid} > 65535;
	$_[0]->{__reqid}++;
}

sub new_request {
	my $self = shift;
	my ($url, $cb, $data) = @_;
	my $id = $self->genid;
	my $curl = WWW::Curl::Easy->new;
	my ($fh, $body);
	$body = '';
	open($fh, ">", \$body);

	$curl->setopt(CURLOPT_HEADER, $self->{__header});
	$curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
	$curl->setopt(CURLOPT_URL, $url);
	$curl->setopt(CURLOPT_WRITEDATA, $fh);
	$curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
	$curl->setopt(CURLOPT_USERAGENT, "Firefox/3.6");
	$curl->setopt(CURLOPT_PRIVATE, $id);
	#$curl->setopt(CURLOPT_VERBOSE, 1);
	$curl->setopt(CURLOPT_TIMEOUT, 180);

	if($self->{cookie}) {
		$curl->setopt(CURLOPT_COOKIEFILE, $self->{cookie});
		$curl->setopt(CURLOPT_COOKIEJAR, $self->{cookie});
	}

	$self->{__requests}->{$id} = {
		handle => $curl,
		id => $id,
		body => \$body,
		fh => $fh,
		cb => $cb,
		data => $data,
	};
	$self->{__curlm}->add_handle($curl);
	$self->{__active}++;
	return wantarray?($id, $curl):$id;
}

sub get {
	my $self = shift;
	my ($url, $args, $cb, $data) = @_;

	if(ref $args ne 'HASH') {
		carp "need a hashref for argument";
		return;
	}
	$args = join('&', map { uri_escape_utf8($_)."=".uri_escape_utf8($args->{$_}) } keys %$args);
	if($args) {
		$url .= ($url =~ /\?/)?'':"?";
		$url .= $args;
	}

	my ($id, $curl) = $self->new_request($url, $cb, $data);
	$curl->setopt(CURLOPT_HTTPGET, 1);
	$self->check_fh;
}

sub post {
	my $self = shift;
	my ($url, $args, $cb, $data) = @_;
	my ($id, $curl) = $self->new_request($url, $cb, $data);

	if(ref $args eq 'HASH') {
		$args = join('&', map { uri_escape_utf8($_)."=".uri_escape_utf8($args->{$_}) } keys %$args);
	}

	#let's use 1.0 POST, so we can post to servers who did not implement 1.1 POST right
	$curl->setopt(CURLOPT_HTTP_VERSION, 1);
	$curl->setopt(CURLOPT_HTTPGET, 0);
	$curl->setopt(CURLOPT_POST, 1);
	$curl->setopt(CURLOPT_POSTFIELDS, $args);

	$self->check_fh;
}

sub call_cb {
	my $self = shift;
	my $id = shift;
	my $request = $self->{__requests}->{$id};
	my $retcode = $request->{handle}->getinfo(CURLINFO_HTTP_CODE),
	# the cookie will be written to file when the handle is GCed
	# so we'll have to let it go before the callback might use it
	undef $request->{handle};
	$request->{cb}->(
		$retcode,
		${$request->{body}},
		$request->{data},
	);
}

sub check_fh {
	my $self = shift;
	my $curlm = $self->{__curlm};
	$curlm->perform;
    my ($rio, $wio, $eio) = $curlm->fdset;

    if(@{$rio}) {
		foreach my $fd (@$rio) {
			$self->{__watcher}->{$fd} ||= AE::io $fd, 0, sub {
				delete $self->{__watcher}->{$fd};
				$self->on_read;
			};
		}
    } elsif(@{$wio}) {
        $self->{__fh_timer} ||= AE::timer 0.5, 0, sub {
			delete $self->{__fh_timer};
			$self->check_fh;
		}
	} elsif($self->{__active}) { #there're some left unread
        $self->{__rd_timer} ||= AE::timer 0.2, 0, sub {
			delete $self->{__rd_timer};
			$self->on_read;
		}
	}
}

sub finish {
	my $self = shift;
	my $id = shift;
	$self->{__active}--;
	$self->call_cb($id) if ($id);
	close $self->{__requests}->{$id}->{fh};
	delete $self->{__requests}->{$id};
	delete $self->{cb}->{$id};
}

sub on_read {
    my $self = shift;
    my $curlm = $self->{__curlm};
    my $active = $curlm->perform;
    if($active < $self->{__active}) {
		while (my ($id, $rval) = $curlm->info_read) {
			if($rval != 0) {
				carp $self->{__requests}->{$id}->{handle}->strerror($rval)." ($rval)\n";
			}
			$self->finish($id) if $id;
		}
    }
	$self->check_fh;
    $active;
}

1;
__END__

=head1 NAME

AnyEvent::Curl::Simple - simpler implementation of AnyEvent::Curl

=head1 SYNOPSIS

  use AnyEvent::Curl::Simple;
  my $curl = AnyEvent::Curl::Simple->new(
		cookie => 'cookie.txt',
	);
  $curl->get('http://www.cpan.org', {
  	},
	sub {
		my ($ret_code, $body) = @_;
		print $body;
	}

=head1 DESCRIPTION

AnyEvent::Curl::Simple is a minimal implementation that I needed for a 
event-based app. If you're looking for a more complete one have a look at
mala's AnyEvent::Curl: http://github.com/mala/AnyEvent-Curl .

=head2 EXPORT

None by default.



=head2 Methods

=over 4

=item new

my $curl = AnyEvent::Curl::Simple->new(
	cookie => 'path to file that stores cookies',
);

if cookie is not given, requests made afterwards will
not save cookies AT ALL.

=item get

$curl->get($url, $args_hashref, $callback);

=item post

$curl->post($url, $args_hashref, $callback);

=back

=head1 SEE ALSO

mala's AnyEvent::Curl: http://github.com/mala/AnyEvent-Curl .

=head1 AUTHOR

Freehaha, E<lt>freehaha AT gmail DOT comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Freehaha

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
