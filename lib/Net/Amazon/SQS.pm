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

sub add_permission {
    my ($self, $param) = @_;

    my $account_id_valid = 0;
    my $action_name_valid = 0;
    for my $key (keys %{$param}) {
        $account_id_valid = 1 if $key =~ /AWSAccountId\.\d/;
        $action_name_valid = 1 if $key =~ /ActionName\.\d/;
    }
    Carp::croak "AWSAccountId.[num] is required." unless $account_id_valid;
    Carp::croak "ActionName.[num] is required." unless $action_name_valid;
    Carp::croak "Label is required." unless $param->{Label};
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'AddPermission',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub change_message_visibility {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    Carp::croak "ReceiptHandle is required." unless $param->{ReceiptHandle};
    Carp::croak "VisibilityTimeout is required." unless $param->{VisibilityTimeout};
    my $req_param = {
        'Action' => 'ChangeMessageVisibility',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub change_message_visibility_batch {
    my ($self, $param) = @_;

    my $batch_request_entry = 0;
    for my $key (keys %{$param}) {
        $batch_request_entry = 1 if $key =~ /ChangeMessageVisibilityBatchRequestEntry\.\d/;
    }
    Carp::croak "ChangeMessageVisibilityBatchRequestEntry.[num] is required." unless $batch_request_entry;
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'ChangeMessageVisibilityBatch',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
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

sub delete_message {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    Carp::croak "ReceiptHandle is required." unless $param->{ReceiptHandle};
    my $req_param = {
        'Action' => 'DeleteMessage',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub delete_message_batch {
    my ($self, $param) = @_;

    my $batch_request_entry = 0;
    for my $key (keys %{$param}) {
        $batch_request_entry = 1 if $key =~ /DeleteaMessageBatchRequestEntry\.\d/;
    }
    Carp::croak "DeleteMessageBatchRequestEntry.[num] is required." unless $batch_request_entry;
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'DeleteMessageBatch',
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

sub get_queue_attributes {
    my ($self, $param) = @_;

    my $attributes = 0;
    for my $key (keys %{$param}) {
        $attributes = 1 if $key =~ /AttributeName\.\d/;
    }
    Carp::croak "AttributeName.[num] is required." unless $attributes;
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'GetQueueAttributes',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub get_queue_url {
    my ($self, $param) = @_;

    Carp::croak "QueueName is required." unless $param->{QueueName};
    my $req_param = {
        'Action' => 'GetQueueUrl',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub list_dead_letter_source_queues {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'ListDeadLetterSourceQueues',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub purge_queue {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'PurgeQueue',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub receive_message {
    my ($self, $param) = @_;

    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'ReceiveMessage',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub remove_permission {
    my ($self, $param) = @_;

    Carp::croak "Label is required." unless $param->{Label};
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'RemovePermission',
        'Version' => $self->version,
        %{$param}
    };
    $self->_request($req_param);
}

sub send_message {
    my ($self, $param) = @_;

    Carp::croak "MessageBody is required." unless $param->{MessageBody};
    Carp::croak "QueueUrl is required." unless $param->{QueueUrl};
    my $req_param = {
        'Action' => 'SendMessage',
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

