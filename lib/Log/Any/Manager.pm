use 5.008001;
use strict;
use warnings;

package Log::Any::Manager;

our $VERSION = '1.04';

use Carp qw(croak);
use Scalar::Util 'weaken';

sub new {
    my $class = shift;
    my $self  = {
        entries         => [],
        category_cache  => {},
        default_adapter => {},
    };
    bless $self, $class;

    return $self;
}

sub get_adapter {
    my ( $self, $category ) = @_;

    # Create a new adapter for this category if it is not already in cache
    #
    my $category_cache = $self->{category_cache};
    if ( !defined( $category_cache->{$category} ) ) {
        my $entry = $self->_choose_entry_for_category($category);
        my $adapter = $self->_new_adapter_for_entry( $entry, $category );
        $category_cache->{$category} = { entry => $entry, adapter => $adapter };
    }
    return $category_cache->{$category}->{adapter};
}

{
    no warnings 'once';
    *get_logger = \&get_adapter;    # backwards compatibility
}

sub _choose_entry_for_category {
    my ( $self, $category ) = @_;

    foreach my $entry ( @{ $self->{entries} } ) {
        if ( $category =~ $entry->{pattern} ) {
            return $entry;
        }
    }
    # nothing requested so fallback to default
    my $default = $self->{default_adapter}{$category}
        || [ $self->_get_adapter_class("Null"), [] ];
    my ($adapter_class, $adapter_params) = @$default;
    _require_dynamic($adapter_class);
    return {
        adapter_class  => $adapter_class,
        adapter_params => $adapter_params,
    };
}

sub _new_adapter_for_entry {
    my ( $self, $entry, $category ) = @_;

    return $entry->{adapter_class}
      ->new( @{ $entry->{adapter_params} }, category => $category );
}

sub set_default {
    my ( $self, $category, $adapter_name, @adapter_params ) = @_;
    my $adapter_class = $self->_get_adapter_class($adapter_name);
    $self->{default_adapter}{$category} = [$adapter_class, \@adapter_params];
}

sub set {
    my $self = shift;
    my $options;
    if ( ref( $_[0] ) eq 'HASH' ) {
        $options = shift(@_);
    }
    my ( $adapter_name, @adapter_params ) = @_;

    croak "expected adapter name"
      unless defined($adapter_name) && $adapter_name =~ /\S/;

    my $pattern = $options->{category};
    if ( !defined($pattern) ) {
        $pattern = qr/.*/;
    }
    elsif ( !ref($pattern) ) {
        $pattern = qr/^\Q$pattern\E$/;
    }

    my $adapter_class = $self->_get_adapter_class($adapter_name);
    _require_dynamic($adapter_class);

    my $entry = $self->_new_entry( $pattern, $adapter_class, \@adapter_params );
    unshift( @{ $self->{entries} }, $entry );

    $self->_reselect_matching_adapters($pattern);

    if ( my $lex_ref = $options->{lexically} ) {
        $$lex_ref = Log::Any::Manager::_Guard->new(
            sub { $self->remove($entry) unless _in_global_destruction() } );
    }

    return $entry;
}

sub remove {
    my ( $self, $entry ) = @_;

    my $pattern = $entry->{pattern};
    $self->{entries} = [ grep { $_ ne $entry } @{ $self->{entries} } ];
    $self->_reselect_matching_adapters($pattern);
}

sub _new_entry {
    my ( $self, $pattern, $adapter_class, $adapter_params ) = @_;

    return {
        pattern        => $pattern,
        adapter_class  => $adapter_class,
        adapter_params => $adapter_params,
    };
}

sub _track_proxy {
    my ( $self, $proxy )= @_;
    my $category_info = $self->{category_cache}{ $proxy->{category} };

    # Proxies are tracked per-channel
    my $tracked= ($category_info->{tracked_proxies} ||= []);
    push @$tracked, $proxy;
    weaken( $tracked->[-1] );

    # Every 8th proxy allocated to the same channel, we check that the
    # weak references are getting cleaned up.
    if ( 0 == ( 7 & @$tracked ) ) {
        @$tracked= grep { defined } @$tracked;
        weaken( $tracked->[$_] ) for 0 .. $#$tracked;
    }

    if ($category_info->{adapter} and $category_info->{adapter}->can('connect_proxy')) {
        $category_info->{adapter}->connect_proxy($proxy);
    }
}

sub _reselect_matching_adapters {
    my ( $self, $pattern ) = @_;

    return if _in_global_destruction();

    # Reselect adapter for each category matching $pattern
    #
    while ( my ( $category, $category_info ) =
        each( %{ $self->{category_cache} } ) )
    {
        my $new_entry = $self->_choose_entry_for_category($category);
        if ( $new_entry ne $category_info->{entry} ) {
            # Disconnect proxies from this adapter
            my $proxies = $category_info->{tracked_proxies} || [];
            for my $proxy ( grep { defined } @$proxies ) {
                $category_info->{adapter}->disconnect_proxy($proxy)
                    if $category_info->{adapter}->can('disconnect_proxy');
            }

            my $new_adapter =
              $self->_new_adapter_for_entry( $new_entry, $category );
            %{ $category_info->{adapter} } = %$new_adapter;
            bless( $category_info->{adapter}, ref($new_adapter) );
            $category_info->{entry} = $new_entry;

            # Connect proxies to the new adapter
            for my $proxy ( grep { defined } @$proxies ) {
                $category_info->{adapter}->connect_proxy($proxy)
                    if $category_info->{adapter}->can('connect_proxy');
            }
        }
    }
}

sub _get_adapter_class {
    my ( $self, $adapter_name ) = @_;
    return $Log::Any::OverrideDefaultAdapterClass if $Log::Any::OverrideDefaultAdapterClass;
    $adapter_name =~ s/^Log:://;    # Log::Dispatch -> Dispatch, etc.
    my $adapter_class = (
          substr( $adapter_name, 0, 1 ) eq '+'
        ? substr( $adapter_name, 1 )
        : "Log::Any::Adapter::$adapter_name"
    );
    return $adapter_class;
}

# This is adapted from the pure perl parts of Devel::GlobalDestruction
if ( defined ${^GLOBAL_PHASE} ) {
    eval 'sub _in_global_destruction () { ${^GLOBAL_PHASE} eq q[DESTRUCT] }; 1' ## no critic
      or die $@;
}
else {
    require B;
    my $started = !B::main_start()->isa(q[B::NULL]);
    unless ($started) {
        eval '0 && $started; CHECK { $started = 1 }; 1' ## no critic
          or die $@;
    }
    eval ## no critic
      '0 && $started; sub _in_global_destruction () { $started && B::main_start()->isa(q[B::NULL]) }; 1'
      or die $@;
}

# XXX not DRY and not a great way to do this, but oh, well.
sub _require_dynamic {
    my ($class) = @_;

    return 1 if $class->can('new'); # duck-type that class is loaded

    unless ( defined( eval "require $class; 1" ) )
    {    ## no critic (ProhibitStringyEval)
        die $@;
    }
}

package    # hide from PAUSE
  Log::Any::Manager::_Guard;

sub new { bless $_[1], $_[0] }

sub DESTROY { $_[0]->() }

1;
