# -*- mode: perl -*-
#
package Iterator;
use Moose;
use namespace::autoclean;

has 'filter' => ( is => 'rw', default => sub { return (@_); } );
has 'done' => ( is => 'rw', isa => 'Bool', default => 0 );

#return next value or undef
sub next {
  my $self = shift;
  return (undef);
}

sub reset {
  my $self = shift;
  return;
}

__PACKAGE__->meta->make_immutable;
1;

package Iterator::Array;
use Moose;
use namespace::autoclean;

extends 'Iterator';

has 'values' => ( is => 'rw', isa => 'ArrayRef' );
has 'index'  => ( is => 'rw', isa => 'Int', default => -1 );

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  $self->index( $self->index + 1 );
  if ( $self->index >= scalar( @{ $self->values } ) ) {
    $self->done(1);
    return (undef);
  }
  return ( $self->values->[ $self->index ] );

}

sub reset {
  my $self = shift;
  $self->index(-1);
  $self->done(0);
}

__PACKAGE__->meta->make_immutable;
1;

package Iterator::Hash;
use Moose;
use namespace::autoclean;

extends 'Iterator';

has 'values' => ( is => 'rw', isa => 'HashRef' );
has 'keys'   => ( is => 'rw', isa => 'Array', default => sub { undef; } );
has 'index'  => ( is => 'rw', isa => 'Int', default => -1 );

sub BUILD {
  my $self = shift;

  $self->keys( keys( %{ $self->values } ) );
}

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  $self->index( $self->index + 1 );
  if ( $self->index >= scalar( @{ $self->keys } ) ) {
    $self->done(1);
    return (undef);
  }
  my $k = ( $self->keys->[ $self->index ] );
  return ( wantarray ? ( $k, $self->values->{$k} ) : $k );
}

sub reset {
  my $self = shift;
  $self->index(-1);
  $self->done(0);
}

__PACKAGE__->meta->make_immutable;
1;

package Iterator::Linspace;
use Moose;
use PDL::Math;
use namespace::autoclean;

extends 'Iterator';

has 'start'          => ( is => 'rw', isa => 'Num',        trigger => &_update_start_stop );
has 'stop'           => ( is => 'rw', isa => 'Num',        trigger => &_update_start_stop );
has 'npts'           => ( is => 'rw', isa => 'Maybe[Num]', trigger => &_update_npts );
has 'increment'      => ( is => 'rw', isa => 'Maybe[Num]', trigger => &_update_increment );
has 'index'          => ( is => 'rw', isa => 'Int',        default => -1 );
has 'npts_specified' => ( is => 'rw', isa => 'Bool',       default => 0 );

sub BUILD {
  my $self = shift;
  $self->npts_specified(1) if ( defined( $self->npts ) );
}

sub _update_start_stop {
  my $self   = shift;
  my $newval = shift;
  my $oldval = shift;

  if ( $self->npts_specified ) {
    $self->{increment} = ( ( $self->stop - $self->start ) / $self->npts );
  } else {
    $self->{npts} = floor( abs( $self->stop - $self->start ) / $self->increment );
  }
}

sub _update_npts {
  my $self   = shift;
  my $newval = shift;
  my $oldval = shift;

  $self->npts_specified(1);
  $self->{increment} = ( ( $self->stop - $self->start ) / $self->npts );
}

sub _update_increment {
  my $self   = shift;
  my $newval = shift;
  my $oldval = shift;

  $self->npts_specified(0);
  $self->{npts} = floor( abs( $self->stop - $self->start ) / $self->increment );
}

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  $self->index( $self->index + 1 );
  if ( $self->index >= $self->npts ) {
    $self->done(1);
    return (undef);
  }
  return ( ( $self->index * $self->increment ) + $self->start );
}

sub reset {
  my $self = shift;
  $self->index( $self->start );
  $self->done(0);
}

__PACKAGE__->meta->make_immutable;
1;

package Iterator::Logspace;
use Moose;
use namespace::autoclean;

extends 'Iterator';

#f(x) = base ^ (x*log_base(Span)/n) + start

has 'start'   => ( is => 'rw', isa => 'Num' );
has 'stop'    => ( is => 'rw', isa => 'Num' );
has 'npts'    => ( is => 'rw', isa => 'Num', default => 101 );
has 'logbase' => ( is => 'rw', isa => 'Num', default => 10 );
has 'index'   => ( is => 'rw', isa => 'Int', default => 0 );
has 'span'    => ( is => 'rw', isa => 'Num', default => 0 );
has 'dir'     => ( is => 'rw', isa => 'Num', default => 1.0 );

sub BUILD {
  my $self = shift;

  $self->span( abs( $self->stop - $self->start ) );
  $self->_dir = ( $self->stop >= $self->start ) ? 1.0 : -1.0;
}

sub _logb {
  my $self = shift;
  my $arg  = shift;
  return ( log($arg) / log( $self->logbase ) );
}

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  my $ix = $self->index + 1;
  if ( $ix >= $self->npts ) {
    $self->done(1);
    return (undef);
  }
  $self->index($ix);
  return ( ( $self->_dir * $ix * $self->_logb( $self->span ) / $self->npts ) + $self->start );
}

sub reset {
  my $self = shift;
  $self->done(0);
  $self->index(0);
}

__PACKAGE__->meta->make_immutable;
1;
