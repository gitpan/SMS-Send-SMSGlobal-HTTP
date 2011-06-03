#!perl

#
# send_sms.t was copied and adapted from SMS::Send::Clickatell
# t/01-construct-request.t with thanks to Brian McCauley.
#

use strict;
use warnings;

use Test::More tests => 34;
use Test::MockObject;
use Test::Exception;
use Test::NoWarnings;

use HTTP::Response;

use SMS::Send;

my $send;

lives_ok( sub {
    $send = SMS::Send->new( 'SMSGlobal::HTTP',
			    _user => "someone",
			    _password => "secret",
			    __ua => Test::MockObject->new,
##			        __verbose => 1,
	)}, "SMS::Send->new('SMSGlobal::HTTP', ...) - lives");

isa_ok($send,'SMS::Send');

# Let's not send any real SMS!
my $mock_ua = Test::MockObject->new;

my (@requests,@mock_responses);

$mock_ua->mock( 
    request => sub {
	shift;
	push @requests => shift;
	shift @mock_responses or die;
    } );

# Ugly but we need to mung the User Agent inside the driver inside the
# object
my $driver = $send->{OBJECT};

isa_ok($driver,'SMS::Send::SMSGlobal::HTTP');
    $driver->{__ua} = $mock_ua;

my %message = (
    text => 'Hi there',
    # From Ofcom's Telephone Numbers for drama purposes (TV, Radio etc)
    to   => '+447700900999',
    _from => '+614444444444',
    );   

my %expected_content = (
    'action' => 'sendsms',
    'password' => 'secret',
    'to' => '447700900999',
    'from' => '614444444444',
    'text' => 'Hi+there',
    'user' => 'someone',
    'maxsplit' => '3'
    );

sub check_request {
    my ($obj, $case, $expect_ok, @stati) = @_;

    @mock_responses = map {
	my ($code,$content) = @$_;
	my $resp = HTTP::Response->new($code);
	$resp->content($content);
	$resp;
    } @stati;

    @requests = ();

    is(!!$obj->send_sms(%message), !!$expect_ok, "send_sms() status $case");

    my $request = $requests[-1]
	or die "no request - unable to continue";

    my %content = $request->content =~ /\G(.*?)=(.*?)(?:&|$)/g;

    is_deeply(\%content,\%expected_content, "request content $case")
	if %expected_content;

    ok(!@mock_responses,"number of requests $case");

    return $request;
}

my $SENT = 1;

## basic request ##

check_request($send, "ok message, immediate delivery", $SENT, [200 => 'OK: 0; Sent queued message ID: 941596d028699601']);

my $request;

do {
    ## add in http-2way fields

    $message{_api} = 1;
    $message{_userfield} = 'testing-1-2-3';
    $expected_content{api} = 1;
    $expected_content{userfield} = 'testing-1-2-3';

    $request = check_request($send, "ok message with defaults, http", $SENT, [200 => 'OK: 0; Sent queued message ID: 941596d028699601']);
    is($request->method, 'POST', 'Default method is post');
    like($request->url, qr/^http:/, 'Default transport is http');

    delete $message{_api};
    delete $message{_userfield};
    delete $expected_content{api};
    delete $expected_content{userfield};
};

do {
    ## https

    $message{__transport} = 'https';
    $request = check_request($send, "ok message, transport https", $SENT, [200 => 'OK: 0; Sent queued message ID: 941596d028699602']);
    like($request->url, qr/^https:/, 'transport set to https');
    delete $message{__transport};
};

## delayed messages

do {
    ## date strings

    $message{'_scheduledatetime'} = '2999-12-31 11:59:59';
    $expected_content{scheduledatetime} = '2999-12-31+11%3A59%3A59';

    check_request($send, "ok message, scheduledatetime (string)", $SENT, [200 => 'SMSGLOBAL DELAY MSGID:49936728']);
    my $mock_dt = Test::MockObject->new;

    ## date objects

    $mock_dt->mock( 
	ymd => sub {
	    my $self = shift;
	    my $sep = shift;
	    join( $sep, qw(2061 10 21) );
	}
	);
    $mock_dt->mock(
	hms => sub {
	    my $self = shift;
	    my $sep = shift;
	    join( $sep, qw(09 05 17) );
	},
	);

    $message{'_scheduledatetime'} = $mock_dt;
    $expected_content{scheduledatetime} = '2061-10-21+09%3A05%3A17';

    check_request($send, "ok message, scheduledatetime (object)", $SENT, [200 => 'SMSGLOBAL DELAY MSGID:49936728']);

    delete $message{'_scheduledatetime'};
    delete $expected_content{scheduledatetime};
};

do {
    # from callerids are tidied up to be alphanumeric & truncated to
    # 11 characters

    $message{_from} = '+H1_(fr0m-d8ve!)';
    $expected_content{from} = 'H1_fr0md8ve';

    $request = check_request($send, "ok message with alphanumeric caller id", $SENT, [200 => 'OK: 0; Sent queued message ID: 941596d028699603']);
};

delete $message{_from};
delete $expected_content{from};

check_request($send, "invalid request", !$SENT, [200 => 'ERROR: Missing parameter: from']);

check_request($send, "404 error", !$SENT, [404 => 'OK']);

do {
    ## list of recipients
    #
    # SMS::Send 0.05 doesn't support lists; test the driver directly
    #
    $message{to} = ['+61(4)770090099','0419 123 456'];
    $expected_content{to} = '614770090099%2C0419123456';

    $request = check_request($driver, "ok message with alphanumeric caller id", $SENT, [200 => 'OK: 0; Sent queued message ID: 941596d028699604']);
};
