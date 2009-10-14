use strict;
use warnings;

package FastTwitterStream;
use Coro;
use Coro::Channel;
use Coro::AnyEvent;
use AnyEvent::Twitter::Stream;
use HTTP::Engine::Response;
use IO::Handle::Util qw(io_from_getline);
use Encode;

my $username = $ENV{TWITTER_USERNAME};
my $password = $ENV{TWITTER_PASSWORD};
my $boundary = '|||';

my $streamer;
my %queue;
my $count = 0;
sub request_handler {
    my $req = shift;

    if ( $req->path eq '/push' ) {
        my $now = ++$count;
        $queue{$count} = Coro::Channel->new;
        $streamer ||= AnyEvent::Twitter::Stream->new(
            username => $username,
            password => $password,
            method   => 'filter',
            track => 'twitter',
            on_tweet => sub {
                $_->put(@_) for values %queue;
            },
        );
        my $body = io_from_getline sub {
            my $tweet = $queue{$now}->get;
            if( $tweet->{text} ){
                return "--$boundary\nContent-Type: text/html\n" .
                    Encode::encode_utf8( $tweet->{text} );
            }else{
                return '';
            }
        };

        return HTTP::Engine::Response->new(
            headers => {
                'Content-Type' => qq{multipart/mixed; boundary="$boundary"},
            },
            body => $body,
        );
    }
    if ( $req->path eq '/' ) {
        return HTTP::Engine::Response->new( body => html() );
    }
};

sub html {
    my $html = <<'HTML';
<html><head>
<title>Server Push</title>
<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.3.1/jquery.min.js"></script>
<script type="text/javascript" src="/js/DUI.js"></script>
<script type="text/javascript" src="/js/Stream.js"></script>
<script type="text/javascript">
$(function() {
var s = new DUI.Stream();
s.listen('text/html', function(payload) {
$('#content').prepend('<p>' + payload + '</p>');
});
s.load('/push');
});
</script>
</head>
<body>
<h1>Server Push</h1>
<div id="content"></div>
</body>
</html>
HTML
    return $html;
}

package main;
use HTTP::Engine;
use Plack::Builder;

my $engine; $engine = HTTP::Engine->new(
    interface => {
        module => 'PSGI',
        request_handler => \&FastTwitterStream::request_handler,
    },
);

builder {
    enable "Plack::Middleware::Static",
        path => qr{\.(?:png|jpg|gif|css|txt|js)$},
            root => './static/';
    sub { $engine->run(@_) };
};


