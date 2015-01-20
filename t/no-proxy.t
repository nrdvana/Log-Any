use strict;
use warnings;
use Test::More;
use Log::Any::Adapter 'Test';

plan tests => 2;

defined eval q{
  package WithoutProxy;
  use Log::Any '$log', proxy_class => 'None';
  
  sub log { $log }
  1;
} or die $@;

# Pckage WithoutProxy should have direct access to adapter Test
is( ref( WithoutProxy->log ), 'Log::Any::Adapter::Test' );

# Now, override the global proxy.  Packages loaded after will be affected.
require Log::Any::Test;

defined eval q{
  package ProxyAnyway;
  use Log::Any '$log', proxy_class => 'None';
  
  sub log { $log }
  1;
} or die $@;

is( ref( ProxyAnyway->log ), 'Log::Any::Proxy::Test' );

