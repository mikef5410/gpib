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
has '_keys'   => ( is => 'rw',  isa => 'Maybe[ArrayRef]', default => undef );
has 'index'  => ( is => 'rw', isa => 'Int', default => -1 );

sub BUILD {
  my $self = shift;

  #print join(",", keys(%{$self->values}));
  my @k = keys( %{ $self->values } ) ;
  $self->{_keys} = \@k;
}

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  $self->index( $self->index + 1 );
  if ( $self->index >= scalar( @{ $self->_keys } ) ) {
    $self->done(1);
    return (undef);
  }
  my $k = ( $self->_keys->[ $self->index ] );
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
use PDL;
use PDL::Math;
use namespace::autoclean;

extends 'Iterator';

has 'start'          => ( is => 'ro', isa => 'Num',         );
has 'stop'           => ( is => 'ro', isa => 'Num',         );
has 'npts'           => ( is => 'ro', isa => 'Maybe[Num]',  );
has 'increment'      => ( is => 'ro', isa => 'Maybe[Num]',  );
has 'index'          => ( is => 'ro', isa => 'Int',        default => -1 );
has '_npts_specified' => ( is => 'ro',isa => 'Bool',       default => 0 );

sub BUILD {
  my $self = shift;
  $self->{_npts_specified}=1 if ( defined( $self->npts ) );
  if ($self->{_npts_specified}) {
    $self->{increment} = ( (  $self->stop - $self->start ) / ($self->npts - 1) );
  } else {
    $self->{npts} = floor( ( abs( $self->stop - $self->start )) / $self->increment );
  }
}

sub next {
  my $self = shift;

  return (undef) if ( $self->done );
  $self->{index}=( $self->index + 1 );
  if ( $self->index > ($self->npts-1) ) {
    $self->done(1);
    return (undef);
  }
  return ( ( $self->index * $self->increment ) + $self->start );
}

sub reset {
  my $self = shift;
  $self->{index}=-1;
  $self->done(0);
}

__PACKAGE__->meta->make_immutable;
1;

package Iterator::Logspace;
use Moose;
use PDL;
use PDL::Math;
use namespace::autoclean;

extends 'Iterator';

#f(x) = base ^ (x*log_base(Span)/n) + start

has 'start'   => ( is => 'ro', isa => 'Num' );
has 'stop'    => ( is => 'ro', isa => 'Num' );
has 'npts'    => ( is => 'ro', isa => 'Num', default => 101 );
has 'logbase' => ( is => 'ro', isa => 'Num', default => 10 );
has 'index'   => ( is => 'ro', isa => 'Int', default => -1 );
has 'span'    => ( is => 'ro', isa => 'Num', default => 0 );
has '_dir'     => ( is => 'ro', isa => 'Num', default => 1.0 );

sub BUILD {
  my $self = shift;

  $self->{span} = ( abs( $self->stop - $self->start ) );
  $self->{_dir} = ( $self->stop >= $self->start ) ? 1.0 : -1.0;
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
  $self->{index}=$ix;
  return ( ( $self->_dir * pow(10,($ix * $self->_logb( $self->span ) / ($self->npts-1) )) + $self->start ));
}

sub reset {
  my $self = shift;
  $self->done(0);
  $self->{index}=-1;
}

__PACKAGE__->meta->make_immutable;
1;
