package Net::Amazon::SQS;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp;
use Encode qw(decode);
use Furl;
use HTTP::Request::Common;
use Moo;
use POSIX qw(setlocale LC_TIME strftime);
use Time::Piece;
use URI;
use URI::QueryParam;
use WebService::Amazon::Signature::v4;
use XML::Simple;

has signature => (
    is => 'lazy',
);

has scope => (
    is => 'lazy',
);

has ua => (
    is => 'lazy',
);

has uri => (
    is => 'lazy',
);

has access_key => (
    is => 'ro',
);

has secret_key => (
    is => 'ro',
);

has region => (
    is => 'ro',
);

has ca_path => (
    is => 'rw',
    default => sub {
        '/etc/ssl/certs',
    },
);

has connection_timeout => (
    is => 'rw',
    default => sub {
        1,
    },
);

has version => (
    is => 'rw',
    default => sub {
        '2012-11-05'
    },
);

has xml_decoder => (
    is => 'rw',
    default => sub {
        XML::Simple->new;
    },
);

sub _build_signature {
    my ($self) = @_;
    my $locale = setlocale(LC_TIME);
    setlocale(LC_TIME, "C");
    my $v4 = WebService::Amazon::Signature::v4->new(
        scope => $self->scope,
        access_key => $self->access_key,
        secret_key => $self->secret_key,
    );
    setlocale(LC_TIME, $locale);
    $v4;
}

sub _build_scope {
    my ($self) = @_;
    join '/', strftime('%Y%m%d', gmtime), $self->region, qw(sqs aws4_request);
}

sub _build_ua {
    my ($self) = @_;

    my $ua = Furl->new(
        agent => 'Net::Amazon::SQS v0.01',
        timeout => $self->connection_timeout,
        ssl_opts => {
            SSL_ca_path => $self->ca_path,
        },
    );
}

sub _build_uri {
    my ($self) = @_;
    URI->new('http://sqs.' . $self->region . '.amazonaws.com/');
}

sub make_request {
    my ($self, $content) = @_;

    my $req = POST($self->uri, $content);
    my $locale = setlocale(LC_TIME);
    setlocale(LC_TIME, "C");
    $req->header(host => $self->uri->host);
    my $http_date = strftime('%a, %d %b %Y %H:%M:%S %Z', localtime);
    my $amz_date = strftime('%Y%m%dT%H%M%SZ', gmtime);
    $req->header(Date => $http_date);
    $req->header('x-amz-date' => $amz_date);
    $req->header('content-type' => 'application/x-www-form-urlencoded');
    $self->signature->from_http_request($req);
    $req->header(Authorization => $self->signature->calculate_signature);
    setlocale(LC_TIME, $locale);
    return $req;
}

sub _request {
    my ($self, $req_param) = @_;
    my $req = $self->make_request($req_param);
    my $res = $self->ua->request($req);
    use Data::Dumper;
    warn Dumper $res;
    my $decoded = $self->xml_decoder->XMLin($res->content);
    if ($res->is_success) {
        return $decoded;
    } else {
        Carp::croak $decoded;
    }
}

sub list_queues {
    my ($self, $param) = @_;

    my $req_param = {
        'Action' => 'ListQueues',
        'Version' => $self->version,
    };
    $req_param->{QueueNamePrefix} = $param->{QueueNamePrefix} if $param->{QueueNamePrefix};
    $self->_request($req_param);
}

sub create_queue {
    my ($self, $param) = @_;

    Carp::croak "QueueName is required." unless $param->{QueueName};
    my $req_param = {
        'Action' => 'CreateQueue',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub delete_queue {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'DeleteQueue',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}


1;
__END__

=encoding utf-8

=head1 NAME

Net::Amazon::SQS - It's new $module

=head1 SYNOPSIS

    use Net::Amazon::SQS;

=head1 DESCRIPTION

Net::Amazon::SQS is ...

=head1 LICENSE

Copyright (C) Kazuhiro Shibuya.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kazuhiro Shibuya E<lt>stevenlabs@gmail.comE<gt>

=cut

