use Test;
BEGIN { plan tests => 4 }
END { ok(0) unless $loaded }
use CGI::XMLApplication;
$loaded = 1;
ok(1);

my $p = CGI::XMLApplication->new('');
ok($p);
$p->setDebugLevel(10);
ok( $CGI::XMLApplication::DEBUG, 10 );
ok( $p->getDebugLevel(), 10 );
