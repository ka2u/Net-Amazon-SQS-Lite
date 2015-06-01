use strict;
use Net::Amazon::SQS;
use Test::More 0.98;
use Time::Piece;
use Time::Seconds;

my $sqs = Net::Amazon::SQS->new(
    access_key => "XXXXX",
    secret_key => "YYYYY",
    region => "ap-northeast-1",
);

my $t = localtime + ONE_DAY;
$sqs->list_queues;

done_testing;
