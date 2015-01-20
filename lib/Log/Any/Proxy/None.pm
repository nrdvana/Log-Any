use 5.008001;
use strict;
use warnings;

package Log::Any::Proxy::None;

our $VERSION = '1.04';

use base qw/Log::Any::Proxy/;

# ABSTRACT: Let producers opt-out of using a proxy

=head1 SYNOPSIS

  use Log::Any '$log', proxy_class => 'None';

=head1 DESCRIPTION

The Log::Any::Proxy gives you useful ways to tailor the logging outout
your module generates.  However if you don't need those features and would
rather communicate directly with the adapter to your backend (or if you
need the ability to do so, for certain special features) this proxy class
restores the old behavior of $log being the adapter itself.

Note that the application can still choose to override your choice of the
'None' proxy in order to facilitate custom processing between producer
and consumer.

=cut

sub new {
    my ( $class, %args ) = @_;
    return $args{adapter};
}

1;
