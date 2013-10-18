use 5.008001;
use strict;
use warnings;

package Log::Any::Proxy;

# ABSTRACT: Log::Any generator proxy object
# VERSION

use Log::Any;

sub _default_formatter {
    my ( $format, @params ) = @_;
    my @new_params =
      map { !defined($_) ? '<undef>' : ref($_) ? _dump_one_line($_) : $_ }
      @params;
    return sprintf( $format, @new_params );
}

sub _dump_one_line {
    my ($value) = @_;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
      ->Terse(1)->Useqq(1)->Dump();
}

sub new {
    my $class = shift;
    my $self = { formatter => \&_default_formatter, @_ };
    Carp::croak("$class requires an 'adapter' parameter")
      unless $self->{adapter};
    bless $self, $class;
    $self->init(@_);
    return $self;
}

sub init { }

for my $attr ( qw/adapter filter formatter prefix/ ) {
    no strict 'refs';
    *{$attr} = sub { return $_[0]->{$attr} };
}

my %aliases = Log::Any->log_level_aliases;

# Set up methods/aliases and detection methods/aliases
foreach my $name ( Log::Any->logging_methods, keys(%aliases) ) {
    my $realname    = $aliases{$name} || $name;
    my $namef       = $name . "f";
    my $is_name     = "is_$name";
    my $is_realname = "is_$realname";
    no strict 'refs';
    *{$is_name} = sub {
        my ($self) = @_;
        return $self->{adapter}->$is_realname;
    };
    *{$name} = sub {
        my ( $self, $message ) = @_;
        return unless defined $message and length $message;
        $message = $self->{filter}->($message) if defined $self->{filter};
        return unless defined $message and length $message;
        $message = "$self->{prefix}$message"
          if defined $self->{prefix} && length $self->{prefix};
        return $self->{adapter}->$realname($message);
    };
    *{$namef} = sub {
        my ( $self, @args ) = @_;
        return unless $self->{adapter}->$is_realname;
        my $message = $self->{formatter}->(@args);
        return unless defined $message and length $message;
        return $self->$name($message);
    };
}

1;

=attr adapter (required)

A L<Log::Any::Adapter> object to receive any messages logged.

=attr filter

A code reference to transform messages before passing them to a
Log::Any::Adapter.  It takes a single string argument and should
return a scalar.  If the return value is undef or the empty string,
no message will be logged.  Otherwise, the return value is passed
to the logging adapter.

=attr formatter

A code reference to format messages given to the C<*f> methods
(C<tracef>, C<debugf>, C<infof>, etc..)  It takes a single
string argument and must return a string argument.

The default formatter acts like C<sprintf>, except that undef
arguments are changed to C<< <undef> >> and any references or
objects are dumped via L<Data::Dumper> (but without newlines).

=attr prefix

If defined, this string will be prepended to all messages.
It will not include a trailing space, so add that yourself
if you want.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 USAGE

=head2 Logging

=head2 Filtering

=head3 Formatting

=head3 Setting a prefix

=cut
