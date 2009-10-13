use Coro;
use Coro::Channel;
use Coro::AnyEvent;
use AnyEvent::Twitter::Stream;
use Plack::Request;
use Plack::Builder;
use IO::Handle::Util qw(io_from_getline);
use Encode;

my $username = $ENV{TWITTER_USERNAME};
my $password = $ENV{TWITTER_PASSWORD};
my $boundary = '|||';
my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    if ( $req->path eq '/push' ) {
        my $queue    = Coro::Channel->new;
        my $streamer = AnyEvent::Twitter::Stream->new(
            username => $username,
            password => $password,
            method   => 'filter',
            track => 'twitter',
            on_tweet => sub {
                $queue->put(@_);
            },
        );
        my $body = io_from_getline sub {
            my $tweet = $queue->get;
            if( $tweet->{text} ){
                return "--$boundary\nContent-Type: text/html\n" .
                    Encode::encode_utf8( $tweet->{text} );
            }else{
                return '';
            }
        };
        return [ 200, ['Content-Type' => qq{multipart/mixed; boundary="$boundary"} ], $body ];
    }
    if ( $req->path eq '/' ) {
        my $res = $req->new_response(200);
        $res->content_type('text/html');
        $res->body( html() );
        $res->finalize;
    }
};

builder {
    enable "Plack::Middleware::Static",
        path => qr{\.(?:png|jpg|gif|css|txt|js)$},
            root => './static/';
    $app;
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
