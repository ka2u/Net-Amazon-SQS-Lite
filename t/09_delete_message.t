use strict;
use Net::Amazon::SQS;
use Test::More 0.98;
use Time::Piece;
use Time::Seconds;
use URI;

my $sqs = Net::Amazon::SQS->new(
    access_key => "XXXXX",
    secret_key => "YYYYY",
    region => "ap-northeast-1",
    uri => URI->new("http://localhost:9324"),
);

SKIP: {
    my $res;
    eval {
        $res = $sqs->list_queues;
    };
    skip $@, 1 if $@;

    $sqs->create_queue({QueueName => "test_queue"});
    $sqs->send_message({
        QueueUrl => "http://localhost:9324/queue/test_queue",
        MessageBody => "Hello!"
    });
    $res = $sqs->receive_message({
        QueueUrl => "http://localhost:9324/queue/test_queue",
    });
    $res = $sqs->delete_message({
        QueueUrl => "http://localhost:9324/queue/test_queue",
        ReceiptHandle => $res->{ReceiveMessageResult}->{Message}->{ReceiptHandle},
        VisibilityTimeout => 60
    });
    is $res->{ResponseMetadata}->{RequestId}, "00000000-0000-0000-0000-000000000000";
    $res = $sqs->delete_queue({QueueUrl => "http://localhost:9324/queue/test_queue"});
};

done_testing;
